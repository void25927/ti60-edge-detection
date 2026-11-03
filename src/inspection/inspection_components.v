`timescale 1ns/1ps
// 有界行段连通域；先接收完整帧，再合并八邻域标签并统计原始矩。
// 输出为几何数据，不是PASS判定。超限、错序或缺帧时不输出正常目标。
module inspection_components #(
    parameter IMAGE_WIDTH=1920, IMAGE_HEIGHT=1080,
    parameter MAX_RUNS=8192, MAX_LABELS=128, MIN_AREA=16,
    parameter CONNECT_DIAGONAL=1, DROP_BORDER=0, PIPELINED_MOMENTS=1
)(
    input wire clk,rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [31:0] start_frame_id,
    input wire run_valid,
    output wire run_ready,
    input wire [10:0] in_x0,in_x1,in_y,
    input wire [31:0] in_frame_id,
    input wire frame_done,frame_bad,
    input wire [21:0] pixel_count,
    output reg result_valid,
    input wire result_ready,
    output reg [31:0] result_frame_id,
    output reg [7:0] result_error, // bit0段容量，1标签容量，2目标数，3格式，4不完整，5父表，6存储
    output reg [2:0] object_count,
    output reg [31:0] process_cycles,
    output reg object_valid,
    input wire object_ready,
    output reg [2:0] object_id,
    output reg object_clipped,
    output reg [21:0] object_area,
    output reg [10:0] object_x0,object_x1,object_y0,object_y1,
    output reg [10:0] object_seed_x,object_seed_y,
    output reg [31:0] object_sum_x,object_sum_y,
    output reg [43:0] object_sum_xx,object_sum_yy,object_sum_xy,
    output reg protocol_fault, // 忙时强送新帧/行段，复位后清零
    input wire record_read,
    input wire [$clog2(MAX_RUNS)-1:0] record_index,
    output reg record_valid,
    output reg [31:0] record_frame_id,
    output reg [10:0] record_x0,record_x1,record_y,
    output reg [2:0] record_object_id
);
    localparam RW=$clog2(MAX_RUNS), LW=$clog2(MAX_LABELS+1);
    localparam IDLE=0,CAPTURE=1,PREP=2,LOAD_WAIT=3,LOAD_RUN=4,
               SCAN_WAIT=5,SCAN=6,ROOT=7,UNION=8,SAVE=9,
               STAT_PREP=10,STAT_WAIT=11,STAT_LOAD=12,STAT_ROOT=13,
               STAT_CALC=14,STAT_ADD=15,COUNT_PREP=16,COUNT=17,
               HEADER=18,OBJ_LOAD=19,OBJ_SEND=20,DONE=21,COUNT_WAIT=22,OBJ_WAIT=23,
               MOMENT_A=24,MOMENT_B=25,MOMENT_DIV=26,MOMENT_DIFF=27;
    reg [4:0] state;
    // 两份同写、各自同步读的行段RAM，避免三端口存储被展开为逻辑。
    // 每字最高位为偶校验；RAM内容不复位，仅复位有效范围和状态机。
    reg [33:0] records_current[0:MAX_RUNS-1];
    reg [33:0] records_previous[0:MAX_RUNS-1];
    reg [LW:0] labels[0:MAX_RUNS-1];
    reg [LW-1:0] parent[0:MAX_LABELS];
    reg [2:0] object_map[0:MAX_LABELS];
    reg [LW-1:0] roots[0:3];
    // 每标签统一几何记录：面积、四边界、种子、一次矩和二次矩，共284位。
    reg [284:0] statistics[0:MAX_LABELS];
    reg parent_parity[0:MAX_LABELS],map_parity[0:MAX_LABELS];
    // 非2幂深度的小表显式补齐只读选择器；非法地址仍由范围检查报错。
    // 避免综合为未定义的选择器叶节点接地，合法标签容量不变。
    wire [LW-1:0] parent_lookup[0:(1<<LW)-1];
    wire [2:0] map_lookup[0:(1<<LW)-1];
    wire parent_check[0:(1<<LW)-1],map_check[0:(1<<LW)-1];
    genvar lookup_i;
    generate for(lookup_i=0;lookup_i<(1<<LW);lookup_i=lookup_i+1)begin: bounded_lookup
        if(lookup_i<=MAX_LABELS)begin
            assign parent_lookup[lookup_i]=parent[lookup_i];
            assign map_lookup[lookup_i]=object_map[lookup_i];
            assign parent_check[lookup_i]=parent_parity[lookup_i];
            assign map_check[lookup_i]=map_parity[lookup_i];
        end else begin
            assign parent_lookup[lookup_i]=0;assign map_lookup[lookup_i]=0;
            assign parent_check[lookup_i]=0;assign map_check[lookup_i]=0;
        end
    end endgenerate
    reg [RW:0] run_count,current_i,scan_i,row_begin,prev_begin,prev_end;
    reg [LW:0] label_count,count_i;
    reg [LW-1:0] root,node;
    reg [LW:0] hops;
    reg [10:0] row_y,x0,x1,y,last_x1,last_y;
    reg have_run;
    reg [2:0] send_i;
    reg [33:0] current_raw,previous_raw;
    reg [LW:0] label_raw;
    reg [284:0] stats_raw;
    wire [32:0] current_q=current_raw[32:0],previous_q=previous_raw[32:0];
    wire [LW-1:0] read_label=label_raw[LW-1:0];
    reg [31:0] read_id;
    reg read_d;
    wire [10:0] px0=previous_q[10:0],px1=previous_q[21:11];
    wire overlap=({1'b0,px0}<={1'b0,x1}+CONNECT_DIAGONAL) &&
                 ({1'b0,x0}<={1'b0,px1}+CONNECT_DIAGONAL);
    wire malformed=(in_x0>in_x1 || in_x1>=IMAGE_WIDTH || in_y>=IMAGE_HEIGHT ||
                    in_frame_id!=result_frame_id || (have_run &&
                    (in_y<last_y || (in_y==last_y && {1'b0,in_x0}<={1'b0,last_x1}+12'd1))));
    assign start_ready=(state==IDLE || state==DONE) && !read_d && !record_valid && !record_read;
    assign run_ready=(state==CAPTURE);

    // 平方和前缀F(n)，仅用于每段统计。乘除法映射待用户综合检查。
    function [43:0] square_prefix;
        input [10:0] n;
        reg [23:0] a;
        reg [35:0] b;
        begin
            a={1'b0,n}*({1'b0,n}+12'd1);
            b=a*({1'b0,n,1'b0}+13'd1);
            square_prefix=b/6;
        end
    endfunction
    reg [11:0] length_q;
    reg [31:0] sum_x_q,sum_y_q;
    reg [43:0] sum_xx_q,sum_yy_q,sum_xy_q;
    // 一次只处理当前行段，帧号/根标签/坐标保持到STAT_ADD，不复制记录。
    reg [10:0] moment_lo,moment_hi;
    reg moment_zero;
    reg [23:0] moment_a_lo,moment_a_hi;
    reg [35:0] moment_b_lo,moment_b_hi,moment_q_lo,moment_q_hi;
    reg moment_valid;
    reg [21:0] moment_y_square;
    // 除法单独占一拍，既不串联前级乘法，也不与后级44位前缀差串联。
    wire [11:0] length_now={1'b0,x1}-{1'b0,x0}+12'd1;
    wire [23:0] sum_x_twice=length_now*({1'b0,x0}+{1'b0,x1});
    wire [31:0] sum_x_now=sum_x_twice>>1;
    wire [21:0] y_square=y*y;
    // 计数器保留满容量状态；实际RAM地址只使用合法索引位宽。
    wire [LW-1:0] next_label=label_count[LW-1:0]+1'b1;
    wire [LW-1:0] count_address=count_i[LW-1:0];
    wire current_corrupt=(^current_raw)!==1'b0;
    wire previous_corrupt=(^previous_raw)!==1'b0;
    wire label_corrupt=(^label_raw)!==1'b0;
    wire stats_corrupt=(^stats_raw)!==1'b0;
    wire parent_corrupt=(^parent_lookup[node])!==parent_check[node];
    wire parent_bad=node==0 || node>label_count || parent_lookup[node]>node || parent_lookup[node]==0 ||
                    hops>=MAX_LABELS || parent_corrupt;
    wire new_label_write=state==SAVE && root==0 && label_count<MAX_LABELS;
    wire label_write= new_label_write || (state==SAVE && root!=0) ||
                      (state==STAT_ROOT && !parent_bad && parent_lookup[node]==node);
    wire [LW-1:0] label_data=new_label_write?next_label:((state==SAVE)?root:node);
    wire external_read=record_read && state==DONE && record_index<run_count;
    wire [RW-1:0] current_address=external_read?record_index:current_i[RW-1:0];
    wire [RW-1:0] label_address=external_read?record_index:
        ((state==SCAN || state==SCAN_WAIT)?scan_i[RW-1:0]:current_i[RW-1:0]);
    wire [LW-1:0] stats_address=(state==COUNT || state==COUNT_WAIT)?count_address:
        ((state==OBJ_WAIT || state==OBJ_LOAD || state==OBJ_SEND)?roots[send_i[1:0]]:node);
    wire [21:0] qa;
    wire [10:0] qx0,qx1,qy0,qy1,qsx,qsy;
    wire [31:0] qs_x,qs_y;
    wire [43:0] qs_xx,qs_yy,qs_xy;
    assign {qa,qx0,qx1,qy0,qy1,qsx,qsy,qs_x,qs_y,qs_xx,qs_yy,qs_xy}=stats_raw[283:0];
    localparam [10:0] MAX_X=IMAGE_WIDTH-1,MAX_Y=IMAGE_HEIGHT-1;
    wire [283:0] initial_stats={22'd0,MAX_X,11'd0,MAX_Y,11'd0,x0,y,32'd0,32'd0,44'd0,44'd0,44'd0};
    wire [283:0] updated_stats={qa+length_q,
        (x0<qx0)?x0:qx0,(x1>qx1)?x1:qx1,(y<qy0)?y:qy0,(y>qy1)?y:qy1,
        qsx,qsy,qs_x+sum_x_q,qs_y+sum_y_q,
        qs_xx+sum_xx_q,qs_yy+sum_yy_q,qs_xy+sum_xy_q};
    wire [283:0] stats_data=new_label_write?initial_stats:updated_stats;
    wire [LW-1:0] stats_write_address=new_label_write?next_label:node;
    wire record_corrupt=current_corrupt || label_corrupt || read_label==0 || read_label>label_count ||
        ((^map_lookup[read_label])!==map_check[read_label]) || map_lookup[read_label]>object_count ||
        current_q[10:0]>current_q[21:11] || current_q[21:11]>=IMAGE_WIDTH || current_q[32:22]>=IMAGE_HEIGHT;

    // 先在RAM外选择地址；每个读寄存器仅有一个数组读表达式，保持read-first。
    always @(posedge clk)begin
        if(rst_n && state==CAPTURE && run_valid && run_count<MAX_RUNS)begin
            records_current[run_count[RW-1:0]]<={^{in_y,in_x1,in_x0},in_y,in_x1,in_x0};
            records_previous[run_count[RW-1:0]]<={^{in_y,in_x1,in_x0},in_y,in_x1,in_x0};
        end
        current_raw<=records_current[current_address];
        previous_raw<=records_previous[scan_i[RW-1:0]];
    end
    always @(posedge clk)begin
        if(rst_n && label_write)labels[current_i[RW-1:0]]<={^label_data,label_data};
        label_raw<=labels[label_address];
    end
    always @(posedge clk)begin
        if(rst_n && (new_label_write || (state==STAT_ADD && !stats_corrupt)))
            statistics[stats_write_address]<={^stats_data,stats_data};
        stats_raw<=statistics[stats_address];
    end
    always @(posedge clk)if(external_read)read_id<=result_frame_id;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;result_valid<=0;result_frame_id<=0;result_error<=0;
            object_count<=0;process_cycles<=0;object_valid<=0;object_id<=0;
            object_clipped<=0;object_area<=0;object_x0<=0;object_x1<=0;object_y0<=0;object_y1<=0;
            object_seed_x<=0;object_seed_y<=0;
            object_sum_x<=0;object_sum_y<=0;object_sum_xx<=0;object_sum_yy<=0;object_sum_xy<=0;
            protocol_fault<=0;run_count<=0;current_i<=0;scan_i<=0;row_begin<=0;
            prev_begin<=0;prev_end<=0;label_count<=0;count_i<=0;root<=0;node<=0;hops<=0;
            row_y<=0;x0<=0;x1<=0;y<=0;last_x1<=0;last_y<=0;have_run<=0;send_i<=0;
            length_q<=0;sum_x_q<=0;sum_y_q<=0;sum_xx_q<=0;sum_yy_q<=0;sum_xy_q<=0;
            moment_lo<=0;moment_hi<=0;moment_zero<=0;moment_a_lo<=0;moment_a_hi<=0;
            moment_b_lo<=0;moment_b_hi<=0;moment_q_lo<=0;moment_q_hi<=0;
            moment_valid<=0;moment_y_square<=0;
            record_valid<=0;record_frame_id<=0;record_x0<=0;record_x1<=0;record_y<=0;record_object_id<=0;read_d<=0;
            // 标签0是保留的无效项；显式定义小型查表的0项，避免综合产生悬空网络。
            parent[0]<=0;parent_parity[0]<=0;object_map[0]<=0;map_parity[0]<=0;
        end else begin
            read_d<=record_read && state==DONE && record_index<run_count && result_error==0;
            record_valid<=read_d && !record_corrupt;
            if(read_d)begin
                if(record_corrupt)begin protocol_fault<=1;result_error[6]<=1;record_object_id<=0;end
                else begin
                    record_frame_id<=read_id;
                    record_x0<=current_q[10:0];record_x1<=current_q[21:11];record_y<=current_q[32:22];
                    record_object_id<=map_lookup[read_label];
                end
            end
            if(record_read && (state!=DONE || record_index>=run_count || result_error!=0))begin
                protocol_fault<=1;
                result_error[6]<=1;
            end
            if((start_valid && !start_ready)||(run_valid && !run_ready))protocol_fault<=1;
            if((state>=PREP && state<HEADER) || state==COUNT_WAIT ||
               (state>=MOMENT_A && state<=MOMENT_DIFF))process_cycles<=process_cycles+1'b1;
            case(state)
                IDLE,DONE:if(start_valid && start_ready)begin
                    state<=CAPTURE;result_frame_id<=start_frame_id;result_error<=0;
                    run_count<=0;have_run<=0;result_valid<=0;object_valid<=0;object_count<=0;
                    process_cycles<=0;label_count<=0;read_d<=0;
                end
                CAPTURE:begin
                    if(run_valid)begin
                        if(malformed)result_error[3]<=1;
                        if(run_count==MAX_RUNS)result_error[0]<=1;
                        else begin
                            run_count<=run_count+1'b1;
                        end
                        have_run<=1;last_x1<=in_x1;last_y<=in_y;
                    end
                    if(frame_done)begin
                        if(frame_bad || pixel_count!=IMAGE_WIDTH*IMAGE_HEIGHT)result_error[4]<=1;
                        state<=PREP;
                    end
                end
                PREP:begin
                    current_i<=0;scan_i<=0;row_begin<=0;prev_begin<=0;prev_end<=0;row_y<=0;
                    if(result_error!=0 || run_count==0)state<=HEADER;
                    else state<=LOAD_WAIT;
                end
                LOAD_WAIT:state<=LOAD_RUN;
                LOAD_RUN:begin
                    if(current_corrupt)begin result_error[6]<=1;state<=HEADER;end
                    else begin
                    x0<=current_q[10:0];x1<=current_q[21:11];y<=current_q[32:22];root<=0;
                    if(current_i==0 || current_q[32:22]!=row_y)begin
                        prev_begin<=row_begin;
                        prev_end<=(current_i!=0 && current_q[32:22]==row_y+1'b1)?current_i:row_begin;
                        scan_i<=row_begin;row_begin<=current_i;row_y<=current_q[32:22];
                    end else scan_i<=prev_begin;
                    state<=SCAN_WAIT;
                    end
                end
                SCAN_WAIT:state<=SCAN;
                SCAN:begin
                    if(scan_i>=prev_end)state<=SAVE;
                    else if(previous_corrupt || label_corrupt)begin result_error[6]<=1;state<=HEADER;end
                    else if(overlap)begin node<=read_label;hops<=0;state<=ROOT;end
                    else begin scan_i<=scan_i+1'b1;state<=SCAN_WAIT;end
                end
                ROOT:begin
                    if(parent_bad)begin
                        result_error[5]<=1;state<=HEADER;
                    end else if(parent_lookup[node]==node)state<=UNION;
                    else begin node<=parent_lookup[node];hops<=hops+1'b1;end
                end
                UNION:begin
                    if(root==0)root<=node;
                    else if(root!=node)begin
                        if(root<node)begin parent[node]<=root;parent_parity[node]<=^root;end
                        else begin parent[root]<=node;parent_parity[root]<=^node;root<=node;end
                    end
                    scan_i<=scan_i+1'b1;state<=SCAN_WAIT;
                end
                SAVE:begin
                    if(root==0)begin
                        if(label_count==MAX_LABELS)begin result_error[1]<=1;state<=HEADER;end
                        else begin
                            parent[next_label]<=next_label;
                            parent_parity[next_label]<=^next_label;
                            object_map[next_label]<=0;map_parity[next_label]<=0;label_count<=label_count+1'b1;
                            current_i<=current_i+1'b1;
                            state<=(current_i+1==run_count)?STAT_PREP:LOAD_WAIT;
                        end
                    end else begin
                        current_i<=current_i+1'b1;
                        state<=(current_i+1==run_count)?STAT_PREP:LOAD_WAIT;
                    end
                end
                STAT_PREP:begin current_i<=0;state<=STAT_WAIT;end
                STAT_WAIT:state<=STAT_LOAD;
                STAT_LOAD:begin
                    if(current_corrupt || label_corrupt)begin result_error[6]<=1;state<=HEADER;end
                    else begin
                    x0<=current_q[10:0];x1<=current_q[21:11];y<=current_q[32:22];
                    node<=read_label;hops<=0;state<=STAT_ROOT;
                    end
                end
                STAT_ROOT:begin
                    if(parent_bad)begin
                        result_error[5]<=1;state<=HEADER;
                    end else if(parent_lookup[node]==node)state<=STAT_CALC;
                    else begin node<=parent_lookup[node];hops<=hops+1'b1;end
                end
                STAT_CALC:begin
                    length_q<=length_now;sum_x_q<=sum_x_now;sum_y_q<=length_now*y;
                    if(PIPELINED_MOMENTS)begin
                        moment_lo<=x0-11'd1;moment_hi<=x1;moment_zero<=x0==0;
                        moment_y_square<=y_square;moment_valid<=1;state<=MOMENT_A;
                    end else begin
                        // 原位宽公式仅供等价自检，正式候选启用精确流水路径。
                        sum_xx_q<=square_prefix(x1)-((x0==0)?44'd0:square_prefix(x0-1'b1));
                        sum_yy_q<=length_now*y_square;sum_xy_q<=sum_x_now*y;state<=STAT_ADD;
                    end
                end
                MOMENT_A:begin
                    if(!moment_valid)begin result_error[6]<=1;state<=HEADER;end
                    else begin
                    moment_a_lo<={1'b0,moment_lo}*({1'b0,moment_lo}+12'd1);
                    moment_a_hi<={1'b0,moment_hi}*({1'b0,moment_hi}+12'd1);
                    sum_yy_q<=length_q*moment_y_square;sum_xy_q<=sum_x_q*y;
                    state<=MOMENT_B;
                    end
                end
                MOMENT_B:begin
                    if(!moment_valid)begin result_error[6]<=1;state<=HEADER;end
                    else begin
                    moment_b_lo<=moment_a_lo*({1'b0,moment_lo,1'b0}+13'd1);
                    moment_b_hi<=moment_a_hi*({1'b0,moment_hi,1'b0}+13'd1);
                    state<=MOMENT_DIV;
                    end
                end
                MOMENT_DIV:begin
                    if(!moment_valid)begin result_error[6]<=1;state<=HEADER;end
                    else begin
                        moment_q_lo<=moment_b_lo/36'd6;moment_q_hi<=moment_b_hi/36'd6;
                        state<=MOMENT_DIFF;
                    end
                end
                MOMENT_DIFF:begin
                    if(!moment_valid)begin result_error[6]<=1;state<=HEADER;end
                    else begin
                    sum_xx_q<={8'd0,moment_q_hi}-(moment_zero?44'd0:{8'd0,moment_q_lo});
                    moment_valid<=0;state<=STAT_ADD;
                    end
                end
                STAT_ADD:begin
                    if(stats_corrupt)begin result_error[6]<=1;state<=HEADER;end
                    else begin current_i<=current_i+1'b1;state<=(current_i+1==run_count)?COUNT_PREP:STAT_WAIT;end
                end
                COUNT_PREP:begin count_i<=1;object_count<=0;state<=COUNT_WAIT;end
                COUNT_WAIT:state<=COUNT;
                COUNT:begin
                    if(count_i>label_count)state<=HEADER;
                    else if(stats_corrupt || ((^parent_lookup[count_address])!==parent_check[count_address]))begin result_error[6]<=1;state<=HEADER;end
                    else begin
                        state<=COUNT_WAIT;
                        if(parent_lookup[count_address]==count_i && qa>=MIN_AREA &&
                           (!DROP_BORDER || (qx0!=0 && qx1!=IMAGE_WIDTH-1 && qy0!=0 && qy1!=IMAGE_HEIGHT-1)))begin
                            if(object_count==4)begin result_error[2]<=1;object_count<=0;state<=HEADER;end
                            else begin
                                roots[object_count[1:0]]<=count_i;object_map[count_address]<=object_count+1'b1;
                                map_parity[count_address]<=^(object_count+3'd1);
                                object_count<=object_count+1'b1;
                            end
                        end
                        count_i<=count_i+1'b1;
                    end
                end
                HEADER:begin
                    result_valid<=1;
                    if(result_error!=0)object_count<=0;
                    if(result_valid && result_ready)begin
                        result_valid<=0;send_i<=0;
                        state<=(result_error!=0 || object_count==0)?DONE:OBJ_WAIT;
                    end
                end
                OBJ_WAIT:state<=OBJ_LOAD;
                OBJ_LOAD:if(stats_corrupt)begin result_error[6]<=1;object_count<=0;state<=HEADER;end
                else begin
                    object_id<=send_i+1'b1;
                    object_area<=qa;
                    object_x0<=qx0;object_x1<=qx1;object_y0<=qy0;object_y1<=qy1;
                    object_seed_x<=qsx;object_seed_y<=qsy;
                    object_sum_x<=qs_x;object_sum_y<=qs_y;
                    object_sum_xx<=qs_xx;object_sum_yy<=qs_yy;object_sum_xy<=qs_xy;
                    object_clipped<=(qx0==0 || qx1==IMAGE_WIDTH-1 || qy0==0 || qy1==IMAGE_HEIGHT-1);
                    object_valid<=1;state<=OBJ_SEND;
                end
                OBJ_SEND:if(object_ready)begin
                    object_valid<=0;send_i<=send_i+1'b1;
                    state<=(send_i+1==object_count)?DONE:OBJ_WAIT;
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
