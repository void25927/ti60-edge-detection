`timescale 1ns/1ps
// 单器件碎边缘工作表：仅聚合一个空间假设；保留段索引，不要求闭合或填充。
// 少量短小孤立段可忽略；多个显著假设、容量/记录错误均置uncertain。
module inspection_edge_target #(
    parameter IMAGE_WIDTH=1920,IMAGE_HEIGHT=1080,MAX_RUNS=2048,CENTER_SELECT=0,
    parameter JOIN_GAP=5,MIN_POINTS=16,MIN_LENGTH=24,BORDER_MARGIN=16,READ_TIMEOUT=64,TASK_TIMEOUT=250000
)(
    input wire clk,rst_n,start,
    output wire ready,
    input wire [31:0] frame_id,
    input wire [$clog2(MAX_RUNS):0] run_count,
    input wire [7:0] frame_error,
    input wire [10:0] focus_x,focus_y,
    output wire record_read,
    output wire [$clog2(MAX_RUNS)-1:0] record_index,
    input wire record_valid,record_error,
    input wire [10:0] record_x0,record_x1,record_y,
    output wire result_valid,
    input wire result_ready,
    output reg [31:0] result_frame_id,
    output reg uncertain,
    output reg [7:0] reasons,
    output reg [21:0] edge_points,
    output reg [31:0] sum_x,sum_y,
    output reg [43:0] sum_xx,sum_yy,sum_xy,
    output reg [10:0] x0,x1,y0,y1,
    output reg [31:0] cycles,accesses,max_wait,
    input wire mask_read,
    input wire [$clog2(MAX_RUNS)-1:0] mask_index,
    output reg mask_valid,mask_error,mask_selected
);
    localparam AW=$clog2(MAX_RUNS);
    localparam IDLE=0,CLEAR=1,REQUEST=2,WAIT_RECORD=3,FIND=4,MERGE=5,SAVE=6,
        CHOOSE=7,RESOLVE=8,POINTS=9,OUTPUT=10,POINT_CALC=11,
        SUPPORT_REQ=12,SUPPORT_WAIT=13,GROW_REQ=14,GROW_WAIT=15,MERGE_WRITE=16,CHOOSE_SAMPLE=17;
    reg [4:0] state;
    reg [1:0] phase;
    reg [10:0] focus_x_q,focus_y_q;
    reg [11:0] best_distance,second_distance;
    reg [AW:0] probe_index;
    reg support_checked,reverse_scan,growth_changed;
    reg [3:0] growth_pairs;
    reg second_pass;
    reg [AW:0] total,index;
    reg [4:0] slot,first_hit,free_slot,chosen,node,hops;
    reg [15:0] hits,used,parent_check;
    reg [3:0] parent[0:15];
    reg [10:0] lx[0:15],hx[0:15],ly[0:15],hy[0:15];
    reg [21:0] weight[0:15];
    reg [5:0] labels[0:MAX_RUNS-1]; // 偶校验+忽略标志+工作表引用。
    reg [1:0] selected_runs[0:MAX_RUNS-1]; // 偶校验+该段属于唯一目标。
    reg [5:0] label_q;
    reg [1:0] mask_q;
    reg mask_pending,mask_bad;
    reg [10:0] rx0,rx1,ry,px;
    reg [11:0] run_length;
    reg [21:0] point_xx,point_yy,point_xy;
    reg [31:0] waiting;
    reg selected_any;
    reg [31:0] budget_cycles;
    reg [15:0] merge_mask;
    reg merge_last,significant_q;
    reg [11:0] distance_q;
    reg [10:0] mdx0,mdx1,mdy0,mdy1,msx0,msx1,msy0,msy1;
    reg [21:0] mdweight,msweight;
    wire root_slot=slot<16 && used[slot[3:0]] && parent[slot[3:0]]==slot[3:0];
    localparam SEED_GAP=CENTER_SELECT?12:JOIN_GAP;
    wire near_run=root_slot && ({1'b0,rx0}<={1'b0,hx[slot[3:0]]}+SEED_GAP) &&
        ({1'b0,lx[slot[3:0]]}<={1'b0,rx1}+SEED_GAP) && ({1'b0,ry}<={1'b0,hy[slot[3:0]]}+SEED_GAP) &&
        ({1'b0,ly[slot[3:0]]}<={1'b0,ry}+SEED_GAP);
    wire [11:0] span_x={1'b0,hx[slot[3:0]]}-{1'b0,lx[slot[3:0]]}+12'd1;
    wire [11:0] span_y={1'b0,hy[slot[3:0]]}-{1'b0,ly[slot[3:0]]}+12'd1;
    wire significant=root_slot && weight[slot[3:0]]>=MIN_POINTS && (span_x>=MIN_LENGTH || span_y>=MIN_LENGTH || weight[slot[3:0]]>=32);
    wire write_label=state==SAVE;
    wire [4:0] label_payload=first_hit<16?{1'b0,first_hit[3:0]}:5'b10000;
    wire label_value_parity=^label_payload;
    wire [11:0] group_cx=({1'b0,lx[slot[3:0]]}+{1'b0,hx[slot[3:0]]})>>1;
    wire [11:0] group_cy=({1'b0,ly[slot[3:0]]}+{1'b0,hy[slot[3:0]]})>>1;
    wire [11:0] distance_x=group_cx>focus_x_q?group_cx-focus_x_q:focus_x_q-group_cx;
    wire [11:0] distance_y=group_cy>focus_y_q?group_cy-focus_y_q:focus_y_q-group_cy;
    wire [11:0] group_distance=distance_x+distance_y;
    localparam CENTER_MARGIN=(IMAGE_WIDTH+IMAGE_HEIGHT)/64>32?(IMAGE_WIDTH+IMAGE_HEIGHT)/64:32;
    // 中央种子近方形，避免圆盖帽上下连接弧被扁长窗口排除而拆成左右目标。
    // 只改变建种子范围，完整记录仍参与后续外向生长；多候选仍拒绝。
    localparam FOCUS_HALF_Y=(IMAGE_WIDTH/6<IMAGE_HEIGHT/3)?IMAGE_WIDTH/6:IMAGE_HEIGHT/3;
    wire in_focus=({1'b0,record_x0}<={1'b0,focus_x_q}+IMAGE_WIDTH/6) &&
        ({1'b0,record_x1}+IMAGE_WIDTH/6>={1'b0,focus_x_q}) &&
        ({1'b0,record_y}<={1'b0,focus_y_q}+FOCUS_HALF_Y) &&
        ({1'b0,record_y}+FOCUS_HALF_Y>={1'b0,focus_y_q});
    wire grown_near=({1'b0,record_x0}<={1'b0,x1}+JOIN_GAP) &&
        ({1'b0,record_x1}+JOIN_GAP>={1'b0,x0}) &&
        ({1'b0,record_y}<={1'b0,y1}+JOIN_GAP) &&
        ({1'b0,record_y}+JOIN_GAP>={1'b0,y0});
    wire grow_accept=state==GROW_WAIT && record_valid && !record_error && ((^mask_q)===1'b0) && (mask_q[0] || grown_near);
    wire write_mask=(state==RESOLVE && node<16 && parent[node[3:0]]==node[3:0]) || (CENTER_SELECT && state==SAVE) || grow_accept;
    wire selected_now=node==chosen;
    wire mask_value=grow_accept?1'b1:((CENTER_SELECT && state==SAVE)?1'b0:selected_now);
    assign ready=state==IDLE;
    assign result_valid=state==OUTPUT;
    assign record_read=(state==REQUEST && index<total) || state==SUPPORT_REQ || state==GROW_REQ;
    assign record_index=(state==SUPPORT_REQ || state==SUPPORT_WAIT)?probe_index[AW-1:0]:index[AW-1:0];
    wire [AW-1:0] mask_address=(CENTER_SELECT && state!=OUTPUT)?index[AW-1:0]:mask_index;
    always @(posedge clk)begin
        if(rst_n && write_label)labels[index[AW-1:0]]<={label_value_parity,label_payload};
        label_q<=labels[index[AW-1:0]];
        if(rst_n && write_mask)selected_runs[index[AW-1:0]]<={mask_value,mask_value};
        mask_q<=selected_runs[mask_address];
    end
    integer j;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;second_pass<=0;total<=0;index<=0;slot<=0;first_hit<=16;free_slot<=16;chosen<=16;node<=0;hops<=0;budget_cycles<=0;
            hits<=0;used<=0;parent_check<=0;rx0<=0;rx1<=0;ry<=0;px<=0;run_length<=0;waiting<=0;selected_any<=0;point_xx<=0;point_yy<=0;point_xy<=0;
            result_frame_id<=0;uncertain<=0;reasons<=0;edge_points<=0;sum_x<=0;sum_y<=0;sum_xx<=0;sum_yy<=0;sum_xy<=0;
            x0<=0;x1<=0;y0<=0;y1<=0;cycles<=0;accesses<=0;max_wait<=0;
            mask_pending<=0;mask_valid<=0;mask_error<=0;mask_selected<=0;mask_bad<=0;
            phase<=0;focus_x_q<=0;focus_y_q<=0;best_distance<=4095;second_distance<=4095;
            probe_index<=0;support_checked<=0;reverse_scan<=0;growth_changed<=0;growth_pairs<=0;
            // 仅16项工作寄存器复位；行段RAM内容不清零。
            for(j=0;j<16;j=j+1)begin parent[j]<=j;lx[j]<=0;hx[j]<=0;ly[j]<=0;hy[j]<=0;weight[j]<=0;end
        end else begin
            mask_pending<=mask_read;mask_valid<=mask_pending;mask_error<=0;
            if(mask_read)mask_bad<=state!=OUTPUT || uncertain || {1'b0,mask_index}>=total;
            if(mask_pending)begin
                mask_error<=mask_bad || ((^mask_q)!==1'b0);
                mask_selected<=!mask_bad && ((^mask_q)===1'b0) && mask_q[0];
            end
            if(state!=IDLE && state!=OUTPUT)begin
                cycles<=cycles+1'b1;
                // 原工作步骤超时预算不变；cycles仍统计包含新增流水拍的真实耗时。
                if(state!=MERGE_WRITE && state!=CHOOSE_SAMPLE)budget_cycles<=budget_cycles+1'b1;
                if(budget_cycles>=TASK_TIMEOUT)begin uncertain<=1;reasons[7]<=1;state<=OUTPUT;end
            end
            case(state)
                IDLE:if(start)begin
                    phase<=0;focus_x_q<=focus_x;focus_y_q<=focus_y;best_distance<=4095;second_distance<=4095;
                    result_frame_id<=frame_id;total<=run_count;index<=0;slot<=0;used<=0;chosen<=16;selected_any<=0;second_pass<=0;
                    uncertain<=frame_error!=0 || run_count==0 || run_count>MAX_RUNS;
                    // 采集容量超限与工作表容量统一为E36；协议错误仍不能进入几何/评分。
                    reasons<=frame_error!=0?((frame_error==8'h01)?(CENTER_SELECT?8'h08:8'h20):8'h80):((CENTER_SELECT && run_count==0)?8'h02:8'd0);
                    edge_points<=0;sum_x<=0;sum_y<=0;sum_xx<=0;sum_yy<=0;sum_xy<=0;cycles<=0;budget_cycles<=0;accesses<=0;max_wait<=0;
                    state<=frame_error!=0 || run_count==0 || run_count>MAX_RUNS?OUTPUT:CLEAR;
                end
                CLEAR:begin parent[slot[3:0]]<=slot[3:0];parent_check[slot[3:0]]<=^slot[3:0];weight[slot[3:0]]<=0;
                    if(slot==15)begin slot<=0;state<=REQUEST;end else slot<=slot+1'b1;end
                REQUEST:begin
                    waiting<=0;
                    if(index>=total)begin
                        if(CENTER_SELECT && phase==1)begin phase<=2;index<=total-1'b1;reverse_scan<=1;growth_changed<=0;growth_pairs<=0;state<=GROW_REQ;end
                        else if(second_pass)state<=OUTPUT;
                        else begin slot<=0;chosen<=16;state<=CHOOSE_SAMPLE;end
                    end else begin accesses<=accesses+1'b1;state<=WAIT_RECORD;end
                end
                WAIT_RECORD:begin
                    waiting<=waiting+1'b1;
                    if(record_valid)begin
                        if(waiting>max_wait)max_wait<=waiting;
                        if(record_error || record_x0>record_x1 || record_x1>=IMAGE_WIDTH || record_y>=IMAGE_HEIGHT || (second_pass && phase!=3 && ((^label_q)!==1'b0)) || (CENTER_SELECT && phase==3 && ((^mask_q)!==1'b0)))begin
                            uncertain<=1;reasons[6]<=1;state<=OUTPUT;
                        end else begin
                            rx0<=record_x0;rx1<=record_x1;ry<=record_y;run_length<={1'b0,record_x1}-{1'b0,record_x0}+12'd1;
                            if(CENTER_SELECT && phase==3)begin
                                if(mask_q[0])begin px<=record_x0;state<=POINT_CALC;end
                                else begin index<=index+1'b1;state<=REQUEST;end
                            end else if(second_pass)begin
                                if(CENTER_SELECT && label_q[4])begin index<=index+1'b1;state<=REQUEST;end
                                else begin node<={1'b0,label_q[3:0]};hops<=0;state<=RESOLVE;end
                            end else begin
                                slot<=0;first_hit<=16;free_slot<=16;hits<=0;support_checked<=0;
                                state<=(CENTER_SELECT && !in_focus)?SAVE:FIND;
                            end
                        end
                    end else if(waiting>=READ_TIMEOUT)begin uncertain<=1;reasons[7]<=1;state<=OUTPUT;end
                end
                FIND:begin
                    if(!used[slot[3:0]] && free_slot==16)free_slot<=slot;
                    if(near_run)begin hits[slot[3:0]]<=1;if(first_hit==16)first_hit<=slot;end
                    if(slot==15)begin slot<=0;state<=MERGE;end else slot<=slot+1'b1;
                end
                MERGE:begin
                    if(first_hit==16)begin
                        if(CENTER_SELECT && !support_checked && run_length<MIN_POINTS)begin
                            if(index+1'b1>=total)state<=SAVE;
                            else begin probe_index<=index+1'b1;state<=SUPPORT_REQ;end
                        end else if(free_slot==16)begin uncertain<=1;reasons[5]<=1;state<=OUTPUT;end
                        else begin
                            first_hit<=free_slot;used[free_slot[3:0]]<=1;parent[free_slot[3:0]]<=free_slot[3:0];
                            parent_check[free_slot[3:0]]<=^free_slot[3:0];
                            lx[free_slot[3:0]]<=rx0;hx[free_slot[3:0]]<=rx1;ly[free_slot[3:0]]<=ry;hy[free_slot[3:0]]<=ry;
                            weight[free_slot[3:0]]<=run_length;state<=SAVE;
                        end
                    end else if(slot==16)begin
                        mdx0<=lx[first_hit[3:0]];mdx1<=hx[first_hit[3:0]];mdy0<=ly[first_hit[3:0]];mdy1<=hy[first_hit[3:0]];mdweight<=weight[first_hit[3:0]];
                        msx0<=rx0;msx1<=rx1;msy0<=ry;msy1<=ry;msweight<=run_length;
                        merge_mask<=16'd1<<first_hit[3:0];merge_last<=1;state<=MERGE_WRITE;
                    end else begin
                        if(hits[slot[3:0]] && slot!=first_hit)begin
                            parent[slot[3:0]]<=first_hit[3:0];
                            parent_check[slot[3:0]]<=^first_hit[3:0];
                            mdx0<=lx[first_hit[3:0]];mdx1<=hx[first_hit[3:0]];mdy0<=ly[first_hit[3:0]];mdy1<=hy[first_hit[3:0]];mdweight<=weight[first_hit[3:0]];
                            msx0<=lx[slot[3:0]];msx1<=hx[slot[3:0]];msy0<=ly[slot[3:0]];msy1<=hy[slot[3:0]];msweight<=weight[slot[3:0]];
                            merge_mask<=16'd1<<first_hit[3:0];merge_last<=0;state<=MERGE_WRITE;
                        end else slot<=slot+1'b1;
                    end
                end
                MERGE_WRITE:begin
                    // 读表和写回分拍；每个目标只接收已寄存的一热写使能。
                    for(j=0;j<16;j=j+1)if(merge_mask[j])begin
                        lx[j]<=msx0<mdx0?msx0:mdx0;hx[j]<=msx1>mdx1?msx1:mdx1;
                        ly[j]<=msy0<mdy0?msy0:mdy0;hy[j]<=msy1>mdy1?msy1:mdy1;
                        weight[j]<=mdweight+msweight;
                    end
                    if(merge_last)state<=SAVE;else begin slot<=slot+1'b1;state<=MERGE;end
                end
                SAVE:begin index<=index+1'b1;state<=REQUEST;end
                CHOOSE_SAMPLE:begin significant_q<=significant;distance_q<=group_distance;state<=CHOOSE;end
                CHOOSE:begin
                    if(used[slot[3:0]] && (((^parent[slot[3:0]])!==parent_check[slot[3:0]]) || parent[slot[3:0]]>slot[3:0] || !used[parent[slot[3:0]]]))begin uncertain<=1;reasons[6]<=1;end
                    if(significant_q)begin
                        if(CENTER_SELECT)begin
                            if(distance_q<best_distance)begin second_distance<=best_distance;best_distance<=distance_q;chosen<=slot;end
                            else if(distance_q<second_distance)second_distance<=distance_q;
                        end else if(chosen!=16)begin uncertain<=1;reasons[0]<=1;end
                        else chosen<=slot;
                    end
                    if(slot==15)begin slot<=0;state<=RESOLVE;node<=16;end else begin slot<=slot+1'b1;state<=CHOOSE_SAMPLE;end
                end
                RESOLVE:begin
                    if(!second_pass)begin
                        if(CENTER_SELECT && chosen!=16 && second_distance!=4095 && second_distance<=best_distance+CENTER_MARGIN)begin uncertain<=1;reasons[0]<=1;state<=OUTPUT;end
                        else if(chosen==16 || uncertain)begin uncertain<=1;reasons[1]<=chosen==16;state<=OUTPUT;end
                        else begin
                            x0<=lx[chosen[3:0]];x1<=hx[chosen[3:0]];y0<=ly[chosen[3:0]];y1<=hy[chosen[3:0]];
                            // 多级3x3的无效边框可能把被截断器件伪装成完整短件；近边界保守UNKNOWN。
                            if(lx[chosen[3:0]]<=BORDER_MARGIN || hx[chosen[3:0]]>=IMAGE_WIDTH-1-BORDER_MARGIN || ly[chosen[3:0]]<=BORDER_MARGIN || hy[chosen[3:0]]>=IMAGE_HEIGHT-1-BORDER_MARGIN)begin uncertain<=1;reasons[2]<=1;state<=OUTPUT;end
                            else begin second_pass<=1;phase<=1;index<=0;state<=REQUEST;end
                        end
                    end else if(node>=16 || !used[node[3:0]] || hops>=16 || parent[node[3:0]]>node[3:0] || ((^parent[node[3:0]])!==parent_check[node[3:0]]))begin uncertain<=1;reasons[6]<=1;state<=OUTPUT;end
                    else if(parent[node[3:0]]!=node[3:0])begin node<={1'b0,parent[node[3:0]]};hops<=hops+1'b1;end
                    else if(selected_now && !CENTER_SELECT)begin px<=rx0;state<=POINT_CALC;end
                    else begin index<=index+1'b1;state<=REQUEST;end
                end
                POINT_CALC:begin point_xx<=px*px;point_yy<=ry*ry;point_xy<=px*ry;state<=POINTS;end
                SUPPORT_REQ:begin waiting<=0;state<=SUPPORT_WAIT;end
                SUPPORT_WAIT:begin
                    waiting<=waiting+1'b1;
                    if(record_valid)begin
                        if(record_error || record_x0>record_x1 || record_x1>=IMAGE_WIDTH || record_y>=IMAGE_HEIGHT)begin uncertain<=1;reasons[6]<=1;state<=OUTPUT;end
                        else if(record_y<=ry+JOIN_GAP && record_x0<=rx1+JOIN_GAP && record_x1+JOIN_GAP>=rx0)begin support_checked<=1;state<=MERGE;end
                        else if(probe_index+1'b1>=total || record_y>ry+JOIN_GAP)state<=SAVE;
                        else begin probe_index<=probe_index+1'b1;state<=SUPPORT_REQ;end
                    end else if(waiting>=READ_TIMEOUT)begin uncertain<=1;reasons[7]<=1;state<=OUTPUT;end
                end
                GROW_REQ:begin waiting<=0;state<=GROW_WAIT;end
                GROW_WAIT:begin
                    waiting<=waiting+1'b1;
                    if(record_valid)begin
                        if(record_error || record_x0>record_x1 || record_x1>=IMAGE_WIDTH || record_y>=IMAGE_HEIGHT || ((^mask_q)!==1'b0))begin uncertain<=1;reasons[6]<=1;state<=OUTPUT;end
                        else begin
                            if(grow_accept)begin
                                if(!mask_q[0])growth_changed<=1;
                                if(record_x0<x0)x0<=record_x0;if(record_x1>x1)x1<=record_x1;
                                if(record_y<y0)y0<=record_y;if(record_y>y1)y1<=record_y;
                            end
                            if(reverse_scan && index==0)begin reverse_scan<=0;index<=0;state<=GROW_REQ;end
                            else if(!reverse_scan && index+1'b1>=total)begin
                                if(growth_changed || (grow_accept && !mask_q[0]))begin
                                    if(growth_pairs==7)begin uncertain<=1;reasons[7]<=1;state<=OUTPUT;end
                                    else begin growth_pairs<=growth_pairs+1'b1;reverse_scan<=1;growth_changed<=0;index<=total-1'b1;state<=GROW_REQ;end
                                end else if(x0<=BORDER_MARGIN || x1>=IMAGE_WIDTH-1-BORDER_MARGIN || y0<=BORDER_MARGIN || y1>=IMAGE_HEIGHT-1-BORDER_MARGIN)begin uncertain<=1;reasons[2]<=1;state<=OUTPUT;end
                                else begin phase<=3;index<=0;state<=REQUEST;end
                            end else begin index<=reverse_scan?index-1'b1:index+1'b1;state<=GROW_REQ;end
                        end
                    end else if(waiting>=READ_TIMEOUT)begin uncertain<=1;reasons[7]<=1;state<=OUTPUT;end
                end
                POINTS:begin
                    edge_points<=edge_points+1'b1;sum_x<=sum_x+px;sum_y<=sum_y+ry;
                    sum_xx<=sum_xx+point_xx;sum_yy<=sum_yy+point_yy;sum_xy<=sum_xy+point_xy;
                    if(px==rx1)begin index<=index+1'b1;state<=REQUEST;end else begin px<=px+1'b1;state<=POINT_CALC;end
                end
                OUTPUT:if(result_ready)state<=IDLE;
                default:state<=IDLE;
            endcase
            // 看门狗优先于正常状态转移，不能被case同拍覆盖。
            if(state!=IDLE && state!=OUTPUT && cycles>=TASK_TIMEOUT)begin uncertain<=1;reasons[7]<=1;state<=OUTPUT;end
        end
    end
endmodule
