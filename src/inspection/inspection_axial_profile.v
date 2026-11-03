`timescale 1ns/1ps
// 主体附近固定4像素分箱，远端引脚归入两端汇总箱；全长仍按原像素测量。
module inspection_axial_profile #(
    parameter MAX_RUNS=2048, MEMORY_TIMEOUT=64, PIPELINED_BODY=1, PACKED_WIDTH=1, PIPELINED_PIXELS=1, GROUPED_BOUNDS=1,EDGE_FEATURES=0
)(
    input wire clk,rst_n,start_valid,
    output wire start_ready,
    input wire [31:0] frame_id,
    input wire [2:0] object_id,
    input wire [$clog2(MAX_RUNS):0] run_count,
    input wire [18:0] center_x_q8,center_y_q8,
    input wire signed [15:0] cosine_q14,sine_q14,
    input wire invalid_geometry,
    output wire record_read,
    output wire [$clog2(MAX_RUNS)-1:0] record_index,
    input wire record_valid,
    input wire [31:0] record_frame_id,
    input wire [10:0] record_x0,record_x1,record_y,
    input wire [2:0] record_object_id,
    output wire result_valid,
    input wire result_ready,
    output reg [31:0] result_frame_id,
    output reg [2:0] result_object_id,
    output wire [1837:0] descriptor, // 主体面积22、轴向长12/宽12、64个宽度12、64个计数16
    output reg invalid,
    output reg [31:0] cycles,accesses,max_wait
);
    localparam IDLE=0,CLEAR=1,READ=2,WAIT=3,PIXEL=4,FINISH=5,OUTPUT=6,CHECK_BODY=7,
               BODY_WIDTH=8,BODY_TEST=9,BODY_ACCUM=10,DRAIN=11,EDGE_EXTENSIONS=12;
    localparam AW=$clog2(MAX_RUNS);
    reg [3:0] state;
    reg [6:0] clear_index;
    reg [AW:0] index,total;
    reg [18:0] cx,cy;
    reg signed [15:0] c,s;
    reg [10:0] x,last_x,y;
    reg [15:0] histogram[0:63];
    reg signed [11:0] lower[0:63],upper[0:63];
    reg [63:0] occupied;
    reg signed [11:0] min_u,max_u,min_v,max_v;
    reg [21:0] area;
    reg [21:0] body_area;
    reg [31:0] waiting;
    reg [6:0] body_index;
    reg body_seen,previous_body;
    reg [5:0] first_body,last_body;
    reg [10:0] left_extension,right_extension;
    wire signed [13:0] body_left=$signed({6'd0,first_body,2'd0})-14'sd128;
    wire signed [13:0] body_right=$signed({6'd0,last_body,2'd0})-14'sd125;
    wire signed [13:0] lead_left=body_left-$signed({{2{min_u[11]}},min_u});
    wire signed [13:0] lead_right=$signed({{2{max_u[11]}},max_u})-body_right;
    // 每次只寄存当前箱；帧/目标标识沿用本任务锁存值，不增加描述符副本。
    reg signed [11:0] body_upper,body_lower;
    reg [15:0] body_count;
    reg [11:0] body_width,body_half;
    reg body_occupied,body_selected_valid,body_selected_here;
    // 同一任务可连续发射像素；跨行段只插入原RAM等待，不逐段排空。
    reg p0_valid,p1_valid,p2_valid,p3_valid,fetch_error;
    reg signed [20:0] p0_dx,p0_dy;
    reg signed [36:0] p1_xc,p1_ys,p1_xs,p1_yc;
    reg signed [15:0] p2_u,p2_v;
    reg signed [11:0] p3_u,p3_v;
    reg [5:0] p3_bin;
    reg p3_range;
    wire signed [37:0] pipe_u_full=$signed(p1_xc)+$signed(p1_ys);
    wire signed [37:0] pipe_v_full=-$signed(p1_xs)+$signed(p1_yc);
    wire signed [15:0] pipe_bin=(p2_u>>>2)+16'sd32;
    wire pipeline_empty=!(p0_valid || p1_valid || p2_valid || p3_valid);
    wire signed [20:0] dx=$signed({2'd0,x,8'd0})-$signed({2'd0,cx});
    wire signed [20:0] dy=$signed({2'd0,y,8'd0})-$signed({2'd0,cy});
    wire signed [36:0] xc=dx*c,ys=dy*s,xs=dx*s,yc=dy*c;
    wire signed [37:0] u_full=$signed(xc)+$signed(ys),v_full=-$signed(xs)+$signed(yc);
    wire signed [15:0] u=u_full>>>22,v=v_full>>>22;
    wire signed [15:0] bin=(u>>>2)+16'sd32;
    wire [5:0] bin_address=bin<0?6'd0:(bin>63?6'd63:bin[5:0]);
    wire [11:0] length=(area==0)?12'd0:max_u-min_u+1'b1;
    wire [11:0] height=(area==0)?12'd0:max_v-min_v+1'b1;
    wire [1023:0] counts;
    wire [767:0] widths;
    wire body_here=widths[body_index[5:0]*12 +:12]>=((height+1'b1)>>1) && histogram[body_index[5:0]]!=0;
    // 保留原12位模运算（包括异常输入边界），不能扩大/截断成另一种公式。
    wire [11:0] selected_width=body_occupied?(body_upper-body_lower+12'd1):12'd0;
    genvar g,lane;
    generate for(g=0;g<64;g=g+1)begin: pack_bins
        assign counts[g*16 +:16]=histogram[g];
        // 主体统计消费本箱后，上边界不再使用，原位改存宽度，避免输出端再做64路减法。
        assign widths[g*12 +:12]=(PACKED_WIDTH && PIPELINED_BODY)?upper[g]:
                                   (occupied[g]?(upper[g]-lower[g]+12'd1):12'd0);
    end endgenerate
    // 边缘路径头部22位改存两端延伸，各11位像素；绝不把边缘计数当实心面积。
    assign descriptor=EDGE_FEATURES?{left_extension,right_extension,length,height,widths,counts}:{body_area,length,height,widths,counts};
    assign start_ready=state==IDLE;
    assign result_valid=state==OUTPUT;
    assign record_read=state==READ && index<total && (!PIPELINED_PIXELS || (!invalid && !fetch_error));
    assign record_index=index[AW-1:0];
    // 各表只出现一个写地址表达式，避免独立状态分支被展开为多写口选择网络。
    wire clear_bank=state==CLEAR;
    wire commit_bank=p3_valid && !invalid && p3_range && area<(EDGE_FEATURES?2073600:16384) &&
        (state==PIXEL || state==READ || state==WAIT || state==DRAIN);
    wire pack_bank=state==BODY_ACCUM && PACKED_WIDTH && body_selected_valid;
    wire [5:0] bank_address=clear_bank?clear_index[5:0]:p3_bin;
    wire [5:0] upper_address=clear_bank?clear_index[5:0]:(pack_bank?body_index[5:0]:p3_bin);
    wire [15:0] histogram_data=clear_bank?16'd0:histogram[p3_bin]+16'd1;
    wire [11:0] lower_data=clear_bank?12'd0:p3_v;
    wire [11:0] upper_data=clear_bank?12'd0:(pack_bank?body_width:p3_v);
    generate if(PIPELINED_PIXELS)begin: single_write_banks
        always @(posedge clk)begin
            if(rst_n && (clear_bank || commit_bank))histogram[bank_address]<=histogram_data;
        end
        if(GROUPED_BOUNDS)begin: grouped_bounds
            // 每组只选8个旧边界；在本提交拍读取，保持同箱连续像素的最新值。
            for(lane=0;lane<8;lane=lane+1)begin: bank
                localparam [2:0] GROUP=lane;
                wire signed [11:0] old_lower=lower[{GROUP,p3_bin[2:0]}];
                wire signed [11:0] old_upper=upper[{GROUP,p3_bin[2:0]}];
                wire occupied_here=occupied[{GROUP,p3_bin[2:0]}];
                wire selected=p3_bin[5:3]==GROUP;
                wire clear_here=clear_bank && clear_index[5:3]==GROUP;
                wire pack_here=pack_bank && body_index[5:3]==GROUP;
                always @(posedge clk)begin
                    if(rst_n && (clear_here || (commit_bank && selected && (!occupied_here || p3_v<old_lower))))
                        lower[{GROUP,bank_address[2:0]}]<=lower_data;
                    if(rst_n && (clear_here || pack_here || (commit_bank && selected && (!occupied_here || p3_v>old_upper))))
                        upper[{GROUP,upper_address[2:0]}]<=upper_data;
                end
            end
        end else begin: flat_bounds_reference
            always @(posedge clk)begin
                if(rst_n && (clear_bank || (commit_bank && (!occupied[p3_bin] || p3_v<lower[p3_bin]))))lower[bank_address]<=lower_data;
                if(rst_n && (clear_bank || pack_bank || (commit_bank && (!occupied[p3_bin] || p3_v>upper[p3_bin]))))upper[upper_address]<=upper_data;
            end
        end
    end endgenerate
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            p0_valid<=0;p1_valid<=0;p2_valid<=0;p3_valid<=0;
            p0_dx<=0;p0_dy<=0;p1_xc<=0;p1_ys<=0;p1_xs<=0;p1_yc<=0;
            p2_u<=0;p2_v<=0;p3_u<=0;p3_v<=0;p3_bin<=0;p3_range<=0;
        end else if(PIPELINED_PIXELS)begin
            p0_valid<=state==PIXEL && !invalid;
            p1_valid<=p0_valid;p2_valid<=p1_valid;p3_valid<=p2_valid;
            if(state==PIXEL && !invalid)begin p0_dx<=dx;p0_dy<=dy;end
            if(p0_valid)begin p1_xc<=p0_dx*c;p1_ys<=p0_dy*s;p1_xs<=p0_dx*s;p1_yc<=p0_dy*c;end
            if(p1_valid)begin p2_u<=pipe_u_full>>>22;p2_v<=pipe_v_full>>>22;end
            if(p2_valid)begin
                p3_u<=p2_u[11:0];p3_v<=p2_v[11:0];
                p3_bin<=pipe_bin<0?6'd0:(pipe_bin>63?6'd63:pipe_bin[5:0]);
                p3_range<=p2_u>=-2048 && p2_u<=2047 && p2_v>=-2048 && p2_v<=2047;
            end
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;clear_index<=0;index<=0;total<=0;cx<=0;cy<=0;c<=0;s<=0;
            x<=0;last_x<=0;y<=0;occupied<=0;area<=0;body_area<=0;min_u<=0;max_u<=0;min_v<=0;max_v<=0;
            waiting<=0;body_index<=0;body_seen<=0;previous_body<=0;result_frame_id<=0;result_object_id<=0;invalid<=0;cycles<=0;accesses<=0;max_wait<=0;
            body_upper<=0;body_lower<=0;body_count<=0;body_width<=0;body_half<=0;
            body_occupied<=0;body_selected_valid<=0;body_selected_here<=0;
            fetch_error<=0;
        end else begin
            if(state!=IDLE && state!=OUTPUT)cycles<=cycles+1'b1;
            // 在提交拍读取最新箱值，同箱连续像素不使用滞后的边界/计数副本。
            if(PIPELINED_PIXELS && p3_valid && !invalid &&
               (state==PIXEL || state==READ || state==WAIT || state==DRAIN))begin
                if(!p3_range || area>=(EDGE_FEATURES?2073600:16384))invalid<=1;
                else begin
                    occupied[p3_bin]<=1;area<=area+1'b1;
                    if(area==0 || p3_u<min_u)min_u<=p3_u;if(area==0 || p3_u>max_u)max_u<=p3_u;
                    if(area==0 || p3_v<min_v)min_v<=p3_v;if(area==0 || p3_v>max_v)max_v<=p3_v;
                end
            end
            case(state)
                IDLE:if(start_valid)begin
                    result_frame_id<=frame_id;result_object_id<=object_id;cx<=center_x_q8;cy<=center_y_q8;c<=cosine_q14;s<=sine_q14;
                    total<=run_count;index<=0;clear_index<=0;occupied<=0;area<=0;body_area<=0;invalid<=invalid_geometry || run_count>MAX_RUNS;
                    first_body<=0;last_body<=0;left_extension<=0;right_extension<=0;
                    body_selected_valid<=0;body_selected_here<=0;
                    fetch_error<=0;
                    min_u<=0;max_u<=0;min_v<=0;max_v<=0;cycles<=0;accesses<=0;max_wait<=0;state<=CLEAR;
                end
                CLEAR:begin
                    if(!PIPELINED_PIXELS)begin
                        histogram[clear_index[5:0]]<=0;lower[clear_index[5:0]]<=0;upper[clear_index[5:0]]<=0;
                    end
                    if(clear_index==63)state<=READ;else clear_index<=clear_index+1'b1;
                end
                READ:begin
                    waiting<=0;
                    if(index>=total || invalid || fetch_error)state<=PIPELINED_PIXELS?DRAIN:FINISH;
                    else begin accesses<=accesses+1'b1;state<=WAIT;end
                end
                WAIT:begin
                    waiting<=waiting+1'b1;
                    if(record_valid)begin
                        if(waiting>max_wait)max_wait<=waiting;
                        if(record_frame_id!=result_frame_id || record_x0>record_x1 || record_x1>=1920 || record_y>=1080)begin
                            // 后续读错误不能丢弃已发射的较早像素，先排空再发布异常。
                            if(PIPELINED_PIXELS)begin fetch_error<=1;state<=DRAIN;end
                            else begin invalid<=1;state<=FINISH;end
                        end
                        else if(record_object_id==result_object_id)begin x<=record_x0;last_x<=record_x1;y<=record_y;state<=PIXEL;end
                        else begin index<=index+1'b1;state<=READ;end
                    end else if(waiting>=MEMORY_TIMEOUT)begin
                        if(PIPELINED_PIXELS)begin fetch_error<=1;state<=DRAIN;end
                        else begin invalid<=1;state<=FINISH;end
                    end
                end
                PIXEL:begin
                    if(PIPELINED_PIXELS)begin
                        if(invalid)state<=DRAIN;
                        else if(x==last_x)begin index<=index+1'b1;state<=READ;end
                        else x<=x+1'b1;
                    end else begin
                    if(u< -2048 || u>2047 || v< -2048 || v>2047 || area>=(EDGE_FEATURES?2073600:16384))begin invalid<=1;state<=FINISH;end
                    else begin
                        histogram[bin_address]<=histogram[bin_address]+1'b1;
                        if(!occupied[bin_address] || v<lower[bin_address])lower[bin_address]<=v[11:0];
                        if(!occupied[bin_address] || v>upper[bin_address])upper[bin_address]<=v[11:0];
                        occupied[bin_address]<=1;area<=area+1'b1;
                        if(area==0 || u<min_u)min_u<=u[11:0];if(area==0 || u>max_u)max_u<=u[11:0];
                        if(area==0 || v<min_v)min_v<=v[11:0];if(area==0 || v>max_v)max_v<=v[11:0];
                        if(x==last_x)begin index<=index+1'b1;state<=READ;end else x<=x+1'b1;
                    end
                    end
                end
                DRAIN:if(pipeline_empty)state<=FINISH;
                FINISH:begin
                    // 边缘跨度表为12位，不沿用实心细长器件的64像素厚度限制。
                    // 原实心区域路径仍保持原上限；边缘路径保持坐标量程保护。
                    if(area==0 || height>(EDGE_FEATURES?2048:64) || fetch_error)invalid<=1;
                    body_index<=0;body_seen<=0;previous_body<=0;
                    body_half<=(height+12'd1)>>1;body_selected_valid<=0;
                    state<=CHECK_BODY;
                end
                CHECK_BODY:begin
                    if(PIPELINED_BODY)begin
                        // 同步读取现有箱表；指针一直保持到BODY_ACCUM消费完毕。
                        if(body_index>=64)begin invalid<=1;body_selected_valid<=0;state<=OUTPUT;end
                        else begin
                            body_upper<=upper[body_index[5:0]];body_lower<=lower[body_index[5:0]];
                            body_count<=histogram[body_index[5:0]];body_occupied<=occupied[body_index[5:0]];
                            body_selected_valid<=1;state<=BODY_WIDTH;
                        end
                    end else begin
                    // 两个分离的粗主体不能当成一个标准轴向器件。
                    if(body_here && !previous_body)begin if(body_seen)invalid<=1;body_seen<=1;end
                    if(body_here)body_area<=body_area+histogram[body_index[5:0]];
                    previous_body<=body_here;
                    if(body_index==63)state<=OUTPUT;else body_index<=body_index+1'b1;
                    end
                end
                BODY_WIDTH:begin
                    if(!body_selected_valid)invalid<=1;
                    body_width<=selected_width;state<=BODY_TEST;
                end
                BODY_TEST:begin
                    if(!body_selected_valid)invalid<=1;
                    body_selected_here<=body_selected_valid && body_width>=body_half && body_count!=0;
                    state<=BODY_ACCUM;
                end
                BODY_ACCUM:begin
                    if(!body_selected_valid)invalid<=1;
                    if(!PIPELINED_PIXELS && PACKED_WIDTH && body_selected_valid)upper[body_index[5:0]]<=body_width;
                    if(body_selected_valid && body_selected_here)begin
                        if(!body_seen)first_body<=body_index[5:0];
                        last_body<=body_index[5:0];
                        if(!previous_body)begin if(body_seen && !EDGE_FEATURES)invalid<=1;body_seen<=1;end
                        body_area<=body_area+body_count;
                    end
                    previous_body<=body_selected_valid && body_selected_here;
                    body_selected_valid<=0;
                    // 第63箱的面积/异常更新同拍落地，下一拍才向下游置valid。
                    if(body_index==63)state<=EDGE_FEATURES?EDGE_EXTENSIONS:OUTPUT;else begin body_index<=body_index+1'b1;state<=CHECK_BODY;end
                end
                EDGE_EXTENSIONS:begin
                    if(!body_seen || height<3 || lead_left>2047 || lead_right>2047)invalid<=1;
                    left_extension<=lead_left>0?lead_left[10:0]:11'd0;
                    right_extension<=lead_right>0?lead_right[10:0]:11'd0;state<=OUTPUT;
                end
                OUTPUT:if(result_ready)state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
endmodule
