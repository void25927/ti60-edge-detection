`timescale 1ns/1ps
// 边缘特征：像素长度/厚度、两端引脚延伸和64箱跨度；没有实心面积判据。
// 保留正反向×邻接三箱的六候选；模板一份，宽度表同步RAM，数据带偶校验。
module inspection_edge_compare #(
    parameter SCORE_TOLERANCE=48,REQUIRE_BODY=0
)(
    input wire clk,rst_n,start,
    output wire ready,
    input wire [1837:0] descriptor,
    input wire [31:0] frame_id,config_word,
    input wire [15:0] track_id,
    input wire invalid,learn,enable,cancel,
    output wire result_valid,
    input wire result_ready,
    output reg [31:0] result_frame_id,
    output reg [15:0] result_track_id,
    output reg [1:0] status,
    output reg [7:0] reasons,
    output reg template_valid,learned,learn_rejected,
    output reg [31:0] template_frame_id,template_config,
    output reg [31:0] cycles,
    output reg [21:0] best_score
);
    localparam IDLE=0,LOAD_PICK=1,LOAD_WRITE=2,SCAN_READ=3,SCAN_USE=4,CANDIDATE=5,DECIDE=6,OUTPUT=7,LOAD_BIN=8;
    reg [3:0] state;
    reg [2:0] candidate;
    reg [95:0] selected_group;
    reg [6:0] index;
    reg [12:0] scene_width[0:63],template_width[0:63];
    reg [12:0] scene_q,template_q;
    reg [11:0] picked;
    reg [45:0] geometry,reference;
    reg learn_q,enable_q,bad,available,any_pass;
    reg [31:0] config_q;
    reg [21:0] score;
    wire signed [8:0] shifted=$signed({2'b00,index})+$signed({7'd0,candidate[1:0]})-9'sd1;
    // 三个偏移编码0,1,2；候选3..5由candidate-3产生。
    wire [1:0] offset=(candidate>=3)?candidate-3:candidate;
    wire signed [8:0] target_index=$signed({2'b00,index})+$signed({7'd0,offset})-9'sd1;
    wire inside=target_index>=0 && target_index<64;
    wire [5:0] ti=(candidate>=3)?6'd63-target_index[5:0]:target_index[5:0];
    reg read_inside;
    reg [6:0] thin_bins,thick_bins;
    wire is_thin=picked!=0 && {picked,1'b0}<{1'b0,geometry[11:0]};
    wire [11:0] sw=scene_q[11:0],tw=read_inside?template_q[11:0]:12'd0;
    wire [11:0] difference=sw>tw?sw-tw:tw-sw;
    wire [11:0] length_delta=geometry[23:12]>reference[23:12]?geometry[23:12]-reference[23:12]:reference[23:12]-geometry[23:12];
    wire [11:0] height_delta=geometry[11:0]>reference[11:0]?geometry[11:0]-reference[11:0]:reference[11:0]-geometry[11:0];
    wire [10:0] template_left=(candidate>=3)?reference[34:24]:reference[45:35];
    wire [10:0] template_right=(candidate>=3)?reference[45:35]:reference[34:24];
    wire [10:0] left_delta=geometry[45:35]>template_left?geometry[45:35]-template_left:template_left-geometry[45:35];
    wire [10:0] right_delta=geometry[34:24]>template_right?geometry[34:24]-template_right:template_right-geometry[34:24];
    wire [11:0] length_tolerance=(reference[23:12]>>4)>8?(reference[23:12]>>4):12'd8;
    wire [11:0] height_tolerance=(reference[11:0]>>3)>4?(reference[11:0]>>3):12'd4;
    wire [10:0] left_tolerance=(template_left>>3)>8?(template_left>>3):11'd8;
    wire [10:0] right_tolerance=(template_right>>3)>8?(template_right>>3):11'd8;
    wire geometry_ok=length_delta<=length_tolerance && height_delta<=height_tolerance && left_delta<=left_tolerance && right_delta<=right_tolerance;
    assign ready=state==IDLE;
    assign result_valid=state==OUTPUT;
    always @(posedge clk)begin
        if(rst_n && state==LOAD_WRITE)begin
            scene_width[index[5:0]]<={^picked,picked};
            if(learn_q && !bad)template_width[index[5:0]]<={^picked,picked};
        end
        scene_q<=scene_width[index[5:0]];
        template_q<=template_width[ti];
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;candidate<=0;index<=0;picked<=0;geometry<=0;reference<=0;learn_q<=0;enable_q<=0;bad<=0;available<=0;any_pass<=0;config_q<=0;
            status<=0;reasons<=0;template_valid<=0;learned<=0;learn_rejected<=0;template_frame_id<=0;template_config<=0;
            thin_bins<=0;thick_bins<=0;
            cycles<=0;best_score<=0;score<=0;result_frame_id<=0;result_track_id<=0;read_inside<=0;
        end else begin
            learned<=0;learn_rejected<=0;
            if(state!=IDLE && state!=OUTPUT)cycles<=cycles+1'b1;
            case(state)
                IDLE:if(start)begin
                    result_frame_id<=frame_id;result_track_id<=track_id;geometry<=descriptor[1837:1792];config_q<=config_word;
                    learn_q<=learn;enable_q<=enable;bad<=invalid;available<=template_valid && template_config==config_word;
                    if(learn)template_valid<=0; // 写入期间模板绝不暴露为可用。
                    if(template_valid && template_config!=config_word)template_valid<=0;
                    index<=0;candidate<=0;score<=0;best_score<=22'h3fffff;any_pass<=0;cycles<=0;status<=0;reasons<=0;
                    thin_bins<=0;thick_bins<=0;
                    state<=invalid?DECIDE:LOAD_PICK;
                end
                // 两级选择保留全部64箱及12位精度，避免一次跨越768位的选择路径。
                LOAD_PICK:begin selected_group<=descriptor[1024+index[5:3]*96+:96];state<=LOAD_BIN;end
                LOAD_BIN:begin picked<=selected_group[index[2:0]*12+:12];state<=LOAD_WRITE;end
                LOAD_WRITE:begin
                    if(is_thin)thin_bins<=thin_bins+1'b1;
                    else if(picked!=0)thick_bins<=thick_bins+1'b1;
                    if(index==63)begin
                        index<=0;
                        if(learn_q)begin
                            if(REQUIRE_BODY && (thin_bins+(is_thin?1:0)<4 || thick_bins+((picked!=0 && !is_thin)?1:0)<2))begin
                                template_valid<=0;learn_rejected<=1;reasons[4]<=1;status<=0;state<=OUTPUT;
                            end else begin reference<=geometry;template_valid<=1;template_frame_id<=result_frame_id;template_config<=config_q;learned<=1;state<=OUTPUT;end
                        end
                        else state<=!available || !enable_q?DECIDE:SCAN_READ;
                    end else begin index<=index+1'b1;state<=LOAD_PICK;end
                end
                SCAN_READ:begin read_inside<=inside;state<=SCAN_USE;end
                SCAN_USE:begin
                    if(((^scene_q)!==1'b0) || (read_inside && ((^template_q)!==1'b0)))begin bad<=1;reasons[7]<=1;end
                    // 每箱允许2像素边缘抖动；总评分单位为超差跨度像素之和。
                    score<=score+(difference>2?difference-2:12'd0);
                    if(index==63)state<=CANDIDATE;else begin index<=index+1'b1;state<=SCAN_READ;end
                end
                CANDIDATE:begin
                    if(score<best_score)best_score<=score;
                    if(score<=SCORE_TOLERANCE && geometry_ok)any_pass<=1;
                    if(candidate==5)state<=DECIDE;
                    else begin candidate<=candidate+1'b1;index<=0;score<=0;state<=SCAN_READ;end
                end
                DECIDE:begin
                    if(bad)begin status<=0;reasons[7]<=1;if(learn_q)learn_rejected<=1;end
                    else if(!available)begin status<=0;reasons[6]<=1;end
                    else if(!enable_q)status<=0;
                    else begin status<=any_pass?2'd1:2'd2;reasons[0]<=!any_pass;end
                    state<=OUTPUT;
                end
                OUTPUT:if(result_ready)state<=IDLE;
                default:state<=IDLE;
            endcase
            if(cancel)begin
                if(state!=IDLE && learn_q)template_valid<=0;
                state<=IDLE;learned<=0;learn_rejected<=0;status<=0;
            end
        end
    end
endmodule
