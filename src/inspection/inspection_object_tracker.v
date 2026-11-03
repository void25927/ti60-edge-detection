`timescale 1ns/1ps
// 四目标保守关联。只接受互为唯一近邻的匹配，不确定时不给旧ID。
module inspection_object_tracker #(
    parameter MAX_MISSED=2,SERIAL_SELECT=1,PIPELINED_APPLY=1,TRACK_CAPACITY=4
)(
    input wire clk,rst_n,in_valid,
    output wire in_ready,
    input wire [31:0] frame_id,config_frame_id,
    input wire [127:0] object_frame_ids,
    input wire [2:0] object_count,
    input wire [43:0] centers_x,centers_y,boxes_x0,boxes_x1,boxes_y0,boxes_y1,
    input wire [87:0] areas,
    input wire [67:0] angles_q8,
    input wire [127:0] contour_scores,
    input wire [3:0] invalid_objects,
    input wire [11:0] max_distance,
    input wire [21:0] max_area_change,
    input wire [16:0] max_angle_change_q8,
    input wire [31:0] max_contour_change,ambiguity_margin,
    input wire [10:0] proximity_gap,
    output reg out_valid,
    input wire out_ready,
    output reg [31:0] out_frame_id,
    output reg [2:0] out_count,
    output reg [63:0] track_ids,
    output reg [31:0] risk_flags, // 每目标8位：数据、近接、关联歧义、新建/缺帧、容量、特征突变、合并/分裂、帧号
    output reg [31:0] process_cycles
);
    localparam IDLE=0,COST=1,SELECT=2,RESOLVE=3,RISK=4,APPLY=5,OUTPUT=6,
               ROW_SCAN=7,ROW_CHECK=8,COL_SCAN=9,COL_CHECK=10,APPLY_WRITE=11;
    reg [3:0] state;
    reg [2:0] n;
    reg [31:0] scan_min,scan_runner;
    reg [1:0] scan_index,scan_best,row_best;
    reg [3:0] valid_tracks,used,invalids;
    reg [15:0] next_id;
    reg [15:0] ids[0:3];
    reg [7:0] age[0:3];
    reg [10:0] px[0:3],py[0:3],px0[0:3],px1[0:3],py0[0:3],py1[0:3];
    reg [21:0] pa[0:3];
    reg signed [16:0] pang[0:3];
    reg [31:0] pc[0:3];
    reg [10:0] x[0:3],y[0:3],x0[0:3],x1[0:3],y0[0:3],y1[0:3];
    reg [21:0] a[0:3];
    reg signed [16:0] ang[0:3];
    reg [31:0] cs[0:3];
    // 16项代价表使用固定片选寄存器，避开旧版工具多读端口RAM地址压缩断言。
    reg [511:0] costs_flat;
    reg [31:0] last_frame,margin,ctol;
    reg have_frame,frame_bad;
    reg [11:0] dtol;
    reg [21:0] atol;
    reg [16:0] rtol;
    reg [10:0] gap;
    reg [4:0] pos;
    reg [2:0] selected[0:3];
    reg [3:0] selected_ok,near_old;
    reg [3:0] structure_risks;
    // 只寄存当前目标的决定；下一目标必须等本次写入后再分配槽位。
    reg [7:0] apply_risks;
    reg [1:0] apply_slot,apply_pos;
    reg apply_allow,apply_existing,apply_valid;
    integer i,j,k,slot,matches;
    reg [31:0] first_cost,runner_cost,other_first,other_runner;
    reg [2:0] first_slot,other_slot;
    reg [7:0] risks;
    reg [11:0] dd;
    reg [21:0] da;
    reg [16:0] dr;
    reg [31:0] dc;
    reg overlap;
    function [16:0] angle_distance;
        input signed [16:0] p,q;
        reg signed [17:0] d;
        begin d=$signed(p)-$signed(q);if(d<0)d=-d;if(d>46080)d=92160-d;angle_distance=d;end
    endfunction
    assign in_ready=(state==IDLE);
    wire [31:0] pair_cost=(i<n && valid_tracks[j[1:0]] && age[j[1:0]]<=MAX_MISSED && dd<=dtol &&
        da<=atol && dr<=rtol && dc<=ctol)?(dd<<4)+(da>>4)+(dr>>8)+(dc>>4)+(overlap?0:16):32'hffffffff;
    function [31:0] cost_at;
        input [3:0] address;
        begin case(address)
            0:cost_at=costs_flat[31:0];1:cost_at=costs_flat[63:32];
            2:cost_at=costs_flat[95:64];3:cost_at=costs_flat[127:96];
            4:cost_at=costs_flat[159:128];5:cost_at=costs_flat[191:160];
            6:cost_at=costs_flat[223:192];7:cost_at=costs_flat[255:224];
            8:cost_at=costs_flat[287:256];9:cost_at=costs_flat[319:288];
            10:cost_at=costs_flat[351:320];11:cost_at=costs_flat[383:352];
            12:cost_at=costs_flat[415:384];13:cost_at=costs_flat[447:416];
            14:cost_at=costs_flat[479:448];default:cost_at=costs_flat[511:480];
        endcase end
    endfunction
    wire [31:0] scan_cost=cost_at(state==COL_SCAN?{scan_index,row_best}:{pos[1:0],scan_index});
    wire scan_unique=scan_runner==32'hffffffff || {1'b0,scan_runner}>{1'b0,scan_min}+{1'b0,margin};
    // COST必定写完16项才进入SELECT，无需复位数据；与原表每拍写入语义一致。
    always @(posedge clk)if(rst_n && state==COST && pos<(TRACK_CAPACITY==1?1:16))begin
        case(pos[3:0])
            0:costs_flat[31:0]<=pair_cost;1:costs_flat[63:32]<=pair_cost;
            2:costs_flat[95:64]<=pair_cost;3:costs_flat[127:96]<=pair_cost;
            4:costs_flat[159:128]<=pair_cost;5:costs_flat[191:160]<=pair_cost;
            6:costs_flat[223:192]<=pair_cost;7:costs_flat[255:224]<=pair_cost;
            8:costs_flat[287:256]<=pair_cost;9:costs_flat[319:288]<=pair_cost;
            10:costs_flat[351:320]<=pair_cost;11:costs_flat[383:352]<=pair_cost;
            12:costs_flat[415:384]<=pair_cost;13:costs_flat[447:416]<=pair_cost;
            14:costs_flat[479:448]<=pair_cost;15:costs_flat[511:480]<=pair_cost;
        endcase
    end
    // 每拍计算一对目标代价；门限都是本帧握手时锁定的参数。
    always @* begin
        i=pos[3:2];j=pos[1:0];
        dd=(x[i[1:0]]>px[j[1:0]]?x[i[1:0]]-px[j[1:0]]:px[j[1:0]]-x[i[1:0]])+(y[i[1:0]]>py[j[1:0]]?y[i[1:0]]-py[j[1:0]]:py[j[1:0]]-y[i[1:0]]);
        da=a[i[1:0]]>pa[j[1:0]]?a[i[1:0]]-pa[j[1:0]]:pa[j[1:0]]-a[i[1:0]];dr=angle_distance(ang[i[1:0]],pang[j[1:0]]);
        dc=cs[i[1:0]]>pc[j[1:0]]?cs[i[1:0]]-pc[j[1:0]]:pc[j[1:0]]-cs[i[1:0]];
        overlap=(x0[i[1:0]]<=px1[j[1:0]] && x1[i[1:0]]>=px0[j[1:0]] && y0[i[1:0]]<=py1[j[1:0]] && y1[i[1:0]]>=py0[j[1:0]]);
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;n<=0;valid_tracks<=0;used<=0;invalids<=0;next_id<=1;last_frame<=0;have_frame<=0;frame_bad<=0;
            margin<=0;ctol<=0;dtol<=0;atol<=0;rtol<=0;gap<=0;pos<=0;selected_ok<=0;near_old<=0;structure_risks<=0;
            scan_min<=0;scan_runner<=0;scan_index<=0;scan_best<=0;row_best<=0;
            apply_risks<=0;apply_slot<=0;apply_pos<=0;apply_allow<=0;apply_existing<=0;apply_valid<=0;
            out_valid<=0;out_frame_id<=0;out_count<=0;track_ids<=0;risk_flags<=0;process_cycles<=0;
            for(k=0;k<TRACK_CAPACITY;k=k+1)begin
                ids[k]<=0;age[k]<=0;px[k]<=0;py[k]<=0;px0[k]<=0;px1[k]<=0;py0[k]<=0;py1[k]<=0;pa[k]<=0;pang[k]<=0;pc[k]<=0;
                x[k]<=0;y[k]<=0;x0[k]<=0;x1[k]<=0;y0[k]<=0;y1[k]<=0;a[k]<=0;ang[k]<=0;cs[k]<=0;selected[k]<=0;
            end
        end else begin
            if(state!=IDLE && state!=OUTPUT)process_cycles<=process_cycles+1'b1;
            case(state)
                IDLE:if(in_valid)begin
                    n<=object_count;out_count<=object_count;out_frame_id<=frame_id;track_ids<=0;risk_flags<=0;process_cycles<=0;
                    dtol<=max_distance;atol<=max_area_change;rtol<=max_angle_change_q8;ctol<=max_contour_change;margin<=ambiguity_margin;gap<=proximity_gap;
                    invalids<=invalid_objects;used<=0;selected_ok<=0;near_old<=0;structure_risks<=0;pos<=0;
                    apply_valid<=0;
                    frame_bad<=object_count>TRACK_CAPACITY || config_frame_id!=frame_id || (have_frame && frame_id!=last_frame+32'd1);
                    last_frame<=frame_id;have_frame<=1;
                    for(k=0;k<TRACK_CAPACITY;k=k+1)begin
                        x[k]<=centers_x[k*11 +:11];y[k]<=centers_y[k*11 +:11];
                        x0[k]<=boxes_x0[k*11 +:11];x1[k]<=boxes_x1[k*11 +:11];y0[k]<=boxes_y0[k*11 +:11];y1[k]<=boxes_y1[k*11 +:11];
                        a[k]<=areas[k*22 +:22];ang[k]<=angles_q8[k*17 +:17];cs[k]<=contour_scores[k*32 +:32];
                        if(k<object_count && object_frame_ids[k*32 +:32]!=frame_id)frame_bad<=1;
                    end
                    state<=COST;
                end
                COST:begin
                    if(pos<(TRACK_CAPACITY==1?1:16))begin
                        if(i<n && valid_tracks[j[1:0]] && age[j[1:0]]<=MAX_MISSED && dd<=dtol)begin
                            near_old[i[1:0]]<=1;
                        end
                        pos<=pos+1'b1;
                    end else begin pos<=0;state<=SELECT;end
                end
                SELECT:begin
                    if(SERIAL_SELECT)begin
                        // 原行/列最小与次小值两条长链改为每拍一个候选；
                        // 顺序、严格小于比较、并列歧义及33位margin加法完全保留。
                        if(pos<n && pos<4)begin
                            scan_min<=32'hffffffff;scan_runner<=32'hffffffff;
                            scan_index<=0;scan_best<=0;state<=ROW_SCAN;
                        end else begin pos<=0;state<=RESOLVE;end
                    end else if(pos<n && pos<4)begin
                        first_cost=32'hffffffff;runner_cost=32'hffffffff;first_slot=0;
                        for(k=0;k<TRACK_CAPACITY;k=k+1)begin
                            if(cost_at({pos[1:0],k[1:0]})<first_cost)begin runner_cost=first_cost;first_cost=cost_at({pos[1:0],k[1:0]});first_slot=k;end
                            else if(cost_at({pos[1:0],k[1:0]})<runner_cost)runner_cost=cost_at({pos[1:0],k[1:0]});
                        end
                        if(first_cost!=32'hffffffff && (runner_cost==32'hffffffff || {1'b0,runner_cost}>{1'b0,first_cost}+{1'b0,margin}))begin
                            other_first=32'hffffffff;other_runner=32'hffffffff;other_slot=0;
                            for(k=0;k<TRACK_CAPACITY;k=k+1)if(k<n)begin
                                if(cost_at({k[1:0],first_slot[1:0]})<other_first)begin other_runner=other_first;other_first=cost_at({k[1:0],first_slot[1:0]});other_slot=k;end
                                else if(cost_at({k[1:0],first_slot[1:0]})<other_runner)other_runner=cost_at({k[1:0],first_slot[1:0]});
                            end
                            if(other_slot==pos && (other_runner==32'hffffffff || {1'b0,other_runner}>{1'b0,other_first}+{1'b0,margin}))begin
                                selected_ok[pos[1:0]]<=1;selected[pos[1:0]]<=first_slot;
                            end
                        end
                        pos<=pos+1'b1;
                    end else begin pos<=0;state<=RESOLVE;end
                end
                ROW_SCAN:begin
                    if(scan_cost<scan_min)begin scan_runner<=scan_min;scan_min<=scan_cost;scan_best<=scan_index;end
                    else if(scan_cost<scan_runner)scan_runner<=scan_cost;
                    if(scan_index==TRACK_CAPACITY-1)state<=ROW_CHECK;else scan_index<=scan_index+1'b1;
                end
                ROW_CHECK:begin
                    if(scan_min!=32'hffffffff && scan_unique)begin
                        row_best<=scan_best;scan_min<=32'hffffffff;scan_runner<=32'hffffffff;
                        scan_best<=0;scan_index<=0;state<=COL_SCAN;
                    end else begin pos<=pos+1'b1;state<=SELECT;end
                end
                COL_SCAN:begin
                    if(scan_index<n)begin
                        if(scan_cost<scan_min)begin scan_runner<=scan_min;scan_min<=scan_cost;scan_best<=scan_index;end
                        else if(scan_cost<scan_runner)scan_runner<=scan_cost;
                    end
                    if(scan_index==TRACK_CAPACITY-1)state<=COL_CHECK;else scan_index<=scan_index+1'b1;
                end
                COL_CHECK:begin
                    if(scan_best==pos[1:0] && scan_unique)begin
                        selected_ok[pos[1:0]]<=1;selected[pos[1:0]]<={1'b0,row_best};
                    end
                    pos<=pos+1'b1;state<=SELECT;
                end
                RESOLVE:begin
                    // 未被使用的历史目标保留有限帧，避免短暂漏检立刻复用ID。
                    for(k=0;k<TRACK_CAPACITY;k=k+1)if(valid_tracks[k])begin
                        matches=0;
                        for(slot=0;slot<TRACK_CAPACITY;slot=slot+1)if(selected_ok[slot[1:0]] && selected[slot[1:0]]==k)matches=1;
                        if(age[k]>=MAX_MISSED && !matches)valid_tracks[k]<=0;
                        else age[k]<=age[k]+1'b1;
                    end
                    state<=RISK;
                end
                RISK:begin
                    // 先对整帧历史快照判断合并/分裂，再更新轨迹，避免目标遍历顺序影响结果。
                    if(pos<n && pos<4)begin
                        matches=0;
                        for(k=0;k<TRACK_CAPACITY;k=k+1)if(valid_tracks[k] && px[k]>=x0[pos[1:0]] && px[k]<=x1[pos[1:0]] && py[k]>=y0[pos[1:0]] && py[k]<=y1[pos[1:0]])matches=matches+1;
                        if(matches>1)structure_risks[pos[1:0]]<=1;
                        if(selected_ok[pos[1:0]])begin
                            slot=selected[pos[1:0]];matches=0;
                            for(k=0;k<TRACK_CAPACITY;k=k+1)if(k<n && x[k]>=px0[slot[1:0]] && x[k]<=px1[slot[1:0]] && y[k]>=py0[slot[1:0]] && y[k]<=py1[slot[1:0]])matches=matches+1;
                            if(matches>1)structure_risks[pos[1:0]]<=1;
                        end
                        pos<=pos+1'b1;
                    end else begin pos<=0;state<=APPLY;end
                end
                APPLY:begin
                    if(pos<n && pos<4)begin
                        risks=0;slot=-1;
                        if(frame_bad)risks[7]=1;
                        if(invalids[pos[1:0]] || a[pos[1:0]]==0 || x0[pos[1:0]]>=x1[pos[1:0]] || y0[pos[1:0]]>=y1[pos[1:0]] || x1[pos[1:0]]>=1919 || y1[pos[1:0]]>=1079 ||
                            x0[pos[1:0]]==0 || y0[pos[1:0]]==0 || x[pos[1:0]]<x0[pos[1:0]] || x[pos[1:0]]>x1[pos[1:0]] || y[pos[1:0]]<y0[pos[1:0]] || y[pos[1:0]]>y1[pos[1:0]])risks[0]=1;
                        for(k=0;k<TRACK_CAPACITY;k=k+1)if(k<n && k!=pos)begin
                            if({1'b0,x0[pos[1:0]]}<={1'b0,x1[k]}+gap && {1'b0,x1[pos[1:0]]}+gap>={1'b0,x0[k]} &&
                               {1'b0,y0[pos[1:0]]}<={1'b0,y1[k]}+gap && {1'b0,y1[pos[1:0]]}+gap>={1'b0,y0[k]})risks[1]=1;
                        end
                        risks[6]=structure_risks[pos[1:0]];
                        if(selected_ok[pos[1:0]])begin
                            slot=selected[pos[1:0]];
                            if(age[slot[1:0]]>1)risks[3]=1;
                        end else if(near_old[pos[1:0]])begin risks[2]=1;risks[5]=1;end
                        else begin
                            for(k=TRACK_CAPACITY-1;k>=0;k=k-1)if(!valid_tracks[k] && !used[k])slot=k;
                            if(slot<0 || next_id==0)risks[4]=1;
                            else risks[3]=1;
                        end
                        if(PIPELINED_APPLY)begin
                            apply_risks<=risks;apply_slot<=slot[1:0];apply_pos<=pos[1:0];
                            apply_allow<=(risks & 8'hf7)==0 && slot>=0;
                            apply_existing<=selected_ok[pos[1:0]];apply_valid<=1;state<=APPLY_WRITE;
                        end else begin
                        if((risks & 8'hf7)==0 && slot>=0)begin
                            used[slot[1:0]]<=1;valid_tracks[slot[1:0]]<=1;age[slot[1:0]]<=0;
                            if(selected_ok[pos[1:0]])track_ids[pos[1:0]*16 +:16]<=ids[slot[1:0]];
                            else begin ids[slot[1:0]]<=next_id;track_ids[pos[1:0]*16 +:16]<=next_id;next_id<=next_id+1'b1;end
                            px[slot[1:0]]<=x[pos[1:0]];py[slot[1:0]]<=y[pos[1:0]];px0[slot[1:0]]<=x0[pos[1:0]];px1[slot[1:0]]<=x1[pos[1:0]];py0[slot[1:0]]<=y0[pos[1:0]];py1[slot[1:0]]<=y1[pos[1:0]];
                            pa[slot[1:0]]<=a[pos[1:0]];pang[slot[1:0]]<=ang[pos[1:0]];pc[slot[1:0]]<=cs[pos[1:0]];
                        end
                        risk_flags[pos[1:0]*8 +:8]<=risks;pos<=pos+1'b1;
                        end
                    end else begin
                        if(frame_bad)begin valid_tracks<=0;risk_flags<=32'h80808080;end
                        state<=OUTPUT;
                    end
                end
                APPLY_WRITE:begin
                    if(!apply_valid || apply_pos!=pos[1:0])begin
                        valid_tracks<=0;track_ids<=0;risk_flags<=32'h80808080;frame_bad<=1;state<=OUTPUT;
                    end else begin
                        if(apply_allow)begin
                            used[apply_slot]<=1;valid_tracks[apply_slot]<=1;age[apply_slot]<=0;
                            if(apply_existing)track_ids[apply_pos*16 +:16]<=ids[apply_slot];
                            else begin ids[apply_slot]<=next_id;track_ids[apply_pos*16 +:16]<=next_id;next_id<=next_id+1'b1;end
                            px[apply_slot]<=x[apply_pos];py[apply_slot]<=y[apply_pos];px0[apply_slot]<=x0[apply_pos];px1[apply_slot]<=x1[apply_pos];py0[apply_slot]<=y0[apply_pos];py1[apply_slot]<=y1[apply_pos];
                            pa[apply_slot]<=a[apply_pos];pang[apply_slot]<=ang[apply_pos];pc[apply_slot]<=cs[apply_pos];
                        end
                        risk_flags[apply_pos*8 +:8]<=apply_risks;
                        apply_valid<=0;pos<=pos+1'b1;state<=APPLY;
                    end
                end
                OUTPUT:begin out_valid<=1;if(out_valid && out_ready)begin out_valid<=0;state<=IDLE;end end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
