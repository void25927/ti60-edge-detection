`timescale 1ns/1ps
// 同步RAM顺序取箱：64箱和六候选不变。valid须保持至装载完成的ready握手。
module inspection_axial_compare_ram #(
    parameter AREA_TOLERANCE=100,LENGTH_TOLERANCE=4,WIDTH_TOLERANCE=3,
    parameter PROFILE_TOLERANCE=720,WIDTH_SUM_TOLERANCE=42,QUEUED_SCENE=0,SHARED_TEMPLATE=0,STREAM_WORDS=0
)(
    input wire clk,rst_n,start_valid,
    output wire start_ready,
    input wire [31:0] frame_id,
    input wire [15:0] track_id,
    input wire [1837:0] scene_descriptor,template_descriptor,
    input wire template_valid,data_invalid,
    input wire word_valid,
    output wire word_ready,
    input wire [4:0] word_index,
    input wire [63:0] word_data,
    input wire [31:0] word_frame,
    input wire [15:0] word_track,
    input wire word_is_template,abort_job,template_start,
    output wire template_ready,
    input wire [31:0] template_frame_id,template_version_in,task_template_version,
    output reg template_done,template_fault,shared_template_valid,
    output reg [31:0] shared_template_version,result_template_version,
    output wire result_valid,
    input wire result_ready,
    output reg [31:0] result_frame_id,
    output reg [15:0] result_track_id,
    output reg [1:0] status,
    output reg [7:0] reasons,
    output reg [31:0] cycles,
    output reg [21:0] count_difference,width_difference
);
    localparam IDLE=0,LOAD=1,FETCH=2,USE=3,REDUCE=4,DECIDE=5,OUTPUT=6,TLOAD=7,DCOUNT=8,DREAD=9,DWRITE=10,SCORE_DIFF=11,SCORE_SUM=12;
    reg [3:0] state;
    reg [5:0] load_index;
    reg [6:0] i;
    reg [2:0] candidate;
    reg [28:0] scene_ram[0:63],template_ram[0:63];
    reg [28:0] scene_q,template_q;
    reg [64:0] count_words[0:15],width_words[0:15];
    reg [64:0] count_q,width_q;
    reg [1:0] load_phase;
    reg [15:0] load_count;
    reg [63:0] load_width_low;
    reg [45:0] packet_geometry;
    reg [4:0] next_word;
    reg packet_valid,packet_bad;
    reg [31:0] packet_frame;
    reg [15:0] packet_track;
    reg [45:0] a_geometry,legacy_b_geometry,shared_geometry;
    reg shared_geometry_parity,template_loading;
    reg [31:0] template_source_frame;
    wire [45:0] b_geometry=SHARED_TEMPLATE?shared_geometry:legacy_b_geometry;
    wire word_mode_ok=!SHARED_TEMPLATE || word_is_template==template_loading;
    wire word_fire=word_valid && (!STREAM_WORDS || word_ready);
    reg [75:0] decode_width;
    reg [6:0] decode_bits,decode_bin;
    reg [1:0] decode_piece;
    reg decode_template;
    wire decoding=STREAM_WORDS && (state==DREAD || state==DWRITE);
    wire [28:0] decode_q=decode_template?template_q:scene_q;
    // 计数字与宽度字分阶段消费，共用解包暂存；不存在同时有效的两份数据。
    wire [27:0] decode_data=state==DCOUNT?{12'd0,decode_width[15:0]}:{decode_width[11:0],decode_q[15:0]};
    wire decoder_bad=STREAM_WORDS && state==DWRITE && (decode_bin>=64 || ((^decode_q)!==1'b0));
    reg [75:0] appended_width;
    reg width_alignment_bad;
    // 64位输入/12位输出只可能剩0、4、8位；用固定接线而非76位通用桶移位。
    // 其余状态及残留高位均报错，不能靠截断掩盖损坏。
    always @*begin
        appended_width=0;width_alignment_bad=0;
        case(decode_bits)
            0:begin appended_width={12'd0,word_data};width_alignment_bad=|decode_width;end
            4:begin appended_width={8'd0,word_data,decode_width[3:0]};width_alignment_bad=|decode_width[75:4];end
            8:begin appended_width={4'd0,word_data,decode_width[7:0]};width_alignment_bad=|decode_width[75:8];end
            default:width_alignment_bad=1;
        endcase
    end
    wire append_bad=STREAM_WORDS && word_fire && word_mode_ok && word_index>=16 && word_index<28 && width_alignment_bad;
    assign word_ready=state==IDLE && !(SHARED_TEMPLATE && template_start && template_ready);
    reg a_inside,b_inside,bad,tv;
    reg [15:0] ap1,ap2,bp1,bp2;
    reg [11:0] aw1,bw1;
    reg [21:0] sum_count,sum_width,best_count,best_width;
    // 利用原FETCH/USE节拍交叠：RAM输出平滑值、差值、累计分别落在独立寄存器边界。
    // 只暂存当前分箱标量；每候选末尾排空两拍，原22位模累加不变。
    reg [17:0] score_a,score_b,count_delta_q;
    reg [11:0] width_cost,width_delta_q;
    reg score_pending,score_valid;
    wire [17:0] count_delta=score_a>score_b?score_a-score_b:score_b-score_a;
    wire signed [8:0] ai=$signed({2'b00,i})-9'sd1;
    wire signed [8:0] bi=candidate<3 ? $signed({2'b00,i})-9'sd2+$signed({6'd0,candidate}) :
                             9'sd63-$signed({2'b00,i})+$signed({6'd0,candidate})-9'sd3;
    wire [9:0] width_bit=load_index*10'd12;
    wire [3:0] width_address=width_bit[9:6];
    wire [127:0] joined_width={width_q[63:0],load_width_low};
    wire [127:0] shifted_width=joined_width>>width_bit[5:0];
    wire [27:0] scene_load=QUEUED_SCENE?{shifted_width[11:0],load_count}:
                             {scene_descriptor[1024+load_index*12+:12],scene_descriptor[load_index*16+:16]};
    wire [27:0] template_load={template_descriptor[1024+load_index*12+:12],template_descriptor[load_index*16+:16]};
    // 不复位RAM，只有64字完整装载后才扫描；一个写口、一个同步读口。
    always @(posedge clk)begin
        if(rst_n && !STREAM_WORDS && state==LOAD && start_valid && (!QUEUED_SCENE || load_phase==2))begin
            scene_ram[load_index]<={^scene_load,scene_load};
            if(!SHARED_TEMPLATE)template_ram[load_index]<={^template_load,template_load};
        end
        // 单一有效模板：仅录入转存时写；正常任务只同步读取，不再复制模板。
        if(rst_n && !STREAM_WORDS && SHARED_TEMPLATE && state==TLOAD && load_phase==2)
            template_ram[load_index]<={^scene_load,scene_load};
        if(rst_n && STREAM_WORDS && (state==DCOUNT || state==DWRITE) && decode_bin<64)begin
            if(decode_template)template_ram[decode_bin[5:0]]<={^decode_data,decode_data};
            else scene_ram[decode_bin[5:0]]<={^decode_data,decode_data};
        end
        scene_q<=scene_ram[(decoding && !decode_template)?decode_bin[5:0]:ai[5:0]];
        template_q<=template_ram[(decoding && decode_template)?decode_bin[5:0]:bi[5:0]];
        if(rst_n && !STREAM_WORDS && QUEUED_SCENE && word_valid && word_mode_ok && state==IDLE && word_index<29)begin
            if(word_index<16)count_words[word_index[3:0]]<={^word_data,word_data};
            else width_words[word_index[3:0]]<={^word_data,word_data};
        end
        count_q<=count_words[load_index[5:2]];
        width_q<=width_words[width_address+(load_phase==1?4'd1:4'd0)];
    end
    // 帧/目标标识与连续29字一同验证；不完整或乱序装载不允许PASS。
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin next_word<=0;packet_valid<=0;packet_bad<=0;packet_frame<=0;packet_track<=0;packet_geometry<=0;end
        else if(SHARED_TEMPLATE && (abort_job || (template_start && template_ready) || (state==TLOAD && load_index==63 && load_phase==2)))begin
            next_word<=0;packet_valid<=0;packet_bad<=0;
        end else if(decoder_bad || append_bad)begin packet_bad<=1;packet_valid<=0;
        end else if(QUEUED_SCENE && word_fire)begin
            if(word_index==0)begin
                next_word<=1;packet_valid<=0;packet_bad<=state!=IDLE || !word_mode_ok;
                packet_frame<=word_frame;packet_track<=word_track;
            end else begin
                if(state!=IDLE || !word_mode_ok || word_index!=next_word || word_frame!=packet_frame || word_track!=packet_track || word_index>=29)begin
                    packet_bad<=1;packet_valid<=0;
                end else if(word_index==28)begin
                    packet_valid<=!packet_bad && word_data[63:46]==0 && (!SHARED_TEMPLATE || !word_is_template) && (!STREAM_WORDS || (decode_bin==64 && decode_bits==0));
                    packet_bad<=packet_bad || word_data[63:46]!=0 || (STREAM_WORDS && (decode_bin!=64 || decode_bits!=0));packet_geometry<=word_data[45:0];
                end
                next_word<=word_index+1'b1;
            end
        end else if(QUEUED_SCENE && state==OUTPUT && result_ready)packet_valid<=0;
    end
    wire [27:0] a=a_inside?scene_q[27:0]:28'd0;
    wire [27:0] b=b_inside?template_q[27:0]:28'd0;
    wire [21:0] aa=a_geometry[45:24],ba=b_geometry[45:24];
    wire [11:0] al=a_geometry[23:12],bl=b_geometry[23:12],ah=a_geometry[11:0],bh=b_geometry[11:0];
    wire [11:0] half_a=(ah+12'd1)>>1,half_b=(bh+12'd1)>>1;
    wire [15:0] an=(a[27:16]>=half_a)?a[15:0]:16'd0;
    wire [15:0] bn=(b[27:16]>=half_b)?b[15:0]:16'd0;
    wire [17:0] ac={2'b0,ap2}+{1'b0,ap1,1'b0}+{2'b0,an};
    wire [17:0] bc={2'b0,bp2}+{1'b0,bp1,1'b0}+{2'b0,bn};
    wire [11:0] width_delta=aw1>bw1?aw1-bw1:bw1-aw1;
    wire [11:0] height_delta=ah>bh?ah-bh:bh-ah;
    wire global_bad=(aa>ba?aa-ba:ba-aa)>AREA_TOLERANCE || (al>bl?al-bl:bl-al)>LENGTH_TOLERANCE ||
                    height_delta>WIDTH_TOLERANCE || best_count>PROFILE_TOLERANCE || best_width>WIDTH_SUM_TOLERANCE;
    wire load_fault=!start_valid || frame_id!=result_frame_id || track_id!=result_track_id ||
                    data_invalid!=bad || template_valid!=tv;
    wire shared_header_bad=(^{shared_geometry_parity,shared_geometry})!==1'b0;
    assign template_ready=SHARED_TEMPLATE && state==IDLE && !template_loading && !abort_job;
    assign start_ready=(state==IDLE && (!start_valid || STREAM_WORDS) && !template_loading)||(state==LOAD && load_index==63 && (!QUEUED_SCENE || load_phase==2))||(state==DECIDE && start_valid);
    assign result_valid=state==OUTPUT;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;load_index<=0;load_phase<=0;load_count<=0;load_width_low<=0;i<=0;candidate<=0;a_geometry<=0;legacy_b_geometry<=0;
            shared_geometry<=0;shared_geometry_parity<=0;template_loading<=0;template_source_frame<=0;
            decode_width<=0;decode_bits<=0;decode_bin<=0;decode_piece<=0;decode_template<=0;
            template_done<=0;template_fault<=0;shared_template_valid<=0;shared_template_version<=0;result_template_version<=0;
            a_inside<=0;b_inside<=0;bad<=0;tv<=0;ap1<=0;ap2<=0;bp1<=0;bp2<=0;aw1<=0;bw1<=0;
            sum_count<=0;sum_width<=0;best_count<=0;best_width<=0;
            score_a<=0;score_b<=0;count_delta_q<=0;width_cost<=0;width_delta_q<=0;score_pending<=0;score_valid<=0;
            result_frame_id<=0;result_track_id<=0;status<=0;reasons<=0;cycles<=0;count_difference<=0;width_difference<=0;
        end else begin
            if(state!=IDLE && state!=OUTPUT)cycles<=cycles+1'b1;
            if(SHARED_TEMPLATE && abort_job)begin
                state<=IDLE;
                if(template_loading)begin shared_template_valid<=0;template_fault<=1;template_done<=1;end
                template_loading<=0;
            end else case(state)
                IDLE:if(SHARED_TEMPLATE && template_start && template_ready)begin
                    template_loading<=1;template_source_frame<=template_frame_id;shared_template_version<=template_version_in;
                    shared_template_valid<=0;template_done<=0;template_fault<=template_version_in==0;
                end else if(SHARED_TEMPLATE && template_loading && word_fire && word_is_template && word_index==28)begin
                    if(packet_bad || next_word!=28 || word_frame!=packet_frame || word_frame!=template_source_frame || word_track!=0 || packet_track!=0 || word_data[63:46]!=0 || template_fault || (STREAM_WORDS && (decode_bin!=64 || decode_bits!=0)))begin
                        template_fault<=1;template_done<=1;template_loading<=0;shared_template_valid<=0;
                    end else begin
                        shared_geometry<=word_data[45:0];shared_geometry_parity<=^word_data[45:0];load_index<=0;load_phase<=0;
                        if(STREAM_WORDS)begin shared_template_valid<=1;template_done<=1;template_loading<=0;end else state<=TLOAD;
                    end
                end else if(STREAM_WORDS && word_fire && word_mode_ok)begin
                    // 计数每字4箱；宽度用最多72有效位的齿轮箱拼接，按箱同步读改写。
                    // 队列原槽由上游持有，完整解包前不接受任务，不另存29字副本。
                    if(word_index<16)begin
                        decode_width<={12'd0,word_data};decode_piece<=0;decode_bin<={word_index[3:0],2'b00};decode_template<=SHARED_TEMPLATE && word_is_template;
                        if(word_index==0)decode_bits<=0;
                        state<=DCOUNT;
                    end else if(word_index<28)begin
                        decode_width<=appended_width;decode_bits<=decode_bits+7'd64;
                        if(width_alignment_bad && word_is_template)template_fault<=1;
                        if(word_index==16)decode_bin<=0;
                        decode_template<=SHARED_TEMPLATE && word_is_template;state<=DREAD;
                    end
                end else if(start_valid && !template_loading)begin
                    load_index<=0;load_phase<=0;i<=0;candidate<=0;bad<=data_invalid;tv<=template_valid;
                    result_frame_id<=frame_id;result_track_id<=track_id;a_geometry<=QUEUED_SCENE?packet_geometry:scene_descriptor[1837:1792];
                    if(!SHARED_TEMPLATE)legacy_b_geometry<=template_descriptor[1837:1792];
                    result_template_version<=task_template_version;
                    status<=0;reasons<=0;cycles<=0;count_difference<=0;width_difference<=0;
                    ap1<=0;ap2<=0;bp1<=0;bp2<=0;aw1<=0;bw1<=0;sum_count<=0;sum_width<=0;best_count<=22'h3fffff;best_width<=22'h3fffff;
                    score_pending<=0;score_valid<=0;
                    if(SHARED_TEMPLATE && (!shared_template_valid || task_template_version!=shared_template_version || shared_header_bad))begin bad<=1;state<=DECIDE;end
                    else if(QUEUED_SCENE && (!packet_valid || packet_bad || packet_frame!=frame_id || packet_track!=track_id))begin bad<=1;state<=DECIDE;end
                    else state<=STREAM_WORDS?(data_invalid || !template_valid?DECIDE:FETCH):LOAD;
                end
                LOAD:begin
                    if(load_fault)begin bad<=1;state<=DECIDE;end
                    else if(QUEUED_SCENE && load_phase==0)load_phase<=1;
                    else if(QUEUED_SCENE && load_phase==1)begin
                        load_count<=count_q[load_index[1:0]*16+:16];load_width_low<=width_q[63:0];load_phase<=2;
                        if(((^count_q)!==1'b0)||((^width_q)!==1'b0))bad<=1;
                    end else begin
                        if(QUEUED_SCENE && width_bit[5:0]>52 && ((^width_q)!==1'b0))bad<=1;
                        if(load_index==63)state<=bad || !tv?DECIDE:FETCH;
                        else begin load_index<=load_index+1'b1;load_phase<=0;end
                    end
                end
                TLOAD:begin
                    if(load_phase==0)load_phase<=1;
                    else if(load_phase==1)begin
                        load_count<=count_q[load_index[1:0]*16+:16];load_width_low<=width_q[63:0];load_phase<=2;
                        if(((^count_q)!==1'b0)||((^width_q)!==1'b0))template_fault<=1;
                    end else begin
                        if(width_bit[5:0]>52 && ((^width_q)!==1'b0))template_fault<=1;
                        if(load_index==63)begin
                            shared_template_valid<=!template_fault && !(width_bit[5:0]>52 && ((^width_q)!==1'b0));
                            template_done<=1;template_loading<=0;state<=IDLE;
                        end else begin load_index<=load_index+1'b1;load_phase<=0;end
                    end
                end
                DCOUNT:begin
                    decode_width<=decode_width>>16;decode_bin<=decode_bin+1'b1;
                    if(decode_piece==3)state<=IDLE;else decode_piece<=decode_piece+1'b1;
                end
                DREAD:state<=DWRITE;
                DWRITE:begin
                    if(decoder_bad && decode_template)template_fault<=1;
                    decode_width<=decode_width>>12;decode_bits<=decode_bits-7'd12;decode_bin<=decode_bin+1'b1;
                    if(decode_bits>=24 && decode_bin<63)state<=DREAD;else state<=IDLE;
                end
                FETCH:begin
                    count_delta_q<=count_delta;width_delta_q<=width_cost;score_valid<=score_pending;
                    a_inside<=ai>=0 && ai<64;b_inside<=bi>=0 && bi<64;state<=USE;
                end
                USE:begin
                    if((a_inside && ((^scene_q)!==1'b0))||(b_inside && ((^template_q)!==1'b0)))bad<=1;
                    if(SHARED_TEMPLATE && b_inside && ((^template_q)!==1'b0))begin shared_template_valid<=0;template_fault<=1;end
                    ap2<=ap1;ap1<=an;bp2<=bp1;bp1<=bn;aw1<=a[27:16];bw1<=b[27:16];
                    score_a<=ac;score_b<=bc;width_cost<=width_delta>1?width_delta-1'b1:12'd0;score_pending<=1;
                    if(score_valid)begin sum_count<=sum_count+count_delta_q;sum_width<=sum_width+width_delta_q;end
                    if(i==67)state<=SCORE_DIFF;else begin i<=i+1'b1;state<=FETCH;end
                end
                SCORE_DIFF:begin count_delta_q<=count_delta;width_delta_q<=width_cost;state<=SCORE_SUM;end
                SCORE_SUM:begin sum_count<=sum_count+count_delta_q;sum_width<=sum_width+width_delta_q;score_pending<=0;score_valid<=0;state<=REDUCE;end
                REDUCE:begin
                    if(sum_count<best_count || (sum_count==best_count && sum_width<best_width))begin best_count<=sum_count;best_width<=sum_width;end
                    if(candidate==5)state<=DECIDE;
                    else begin
                        candidate<=candidate+1'b1;i<=0;ap1<=0;ap2<=0;bp1<=0;bp2<=0;aw1<=0;bw1<=0;sum_count<=0;sum_width<=0;state<=FETCH;
                        score_pending<=0;score_valid<=0;
                    end
                end
                DECIDE:begin
                    count_difference<=best_count;width_difference<=best_width;
                    if(bad || !tv || (SHARED_TEMPLATE && (!shared_template_valid || shared_header_bad)))begin status<=0;reasons<=bad || (SHARED_TEMPLATE && (!shared_template_valid || shared_header_bad))?8'h80:8'h40;end
                    else begin
                        reasons[0]<=(aa>ba?aa-ba:ba-aa)>AREA_TOLERANCE;
                        reasons[1]<=(al>bl?al-bl:bl-al)>LENGTH_TOLERANCE;
                        reasons[2]<=(ah>bh?ah-bh:bh-ah)>WIDTH_TOLERANCE;
                        reasons[3]<=best_count>PROFILE_TOLERANCE;reasons[4]<=best_width>WIDTH_SUM_TOLERANCE;
                        // 保留明显结构缺陷评分，轻微边缘起伏不单独触发UNKNOWN。
                        status<=global_bad?2:1;
                    end
                    state<=OUTPUT;
                end
                OUTPUT:if(result_ready)state<=IDLE;
                default:state<=IDLE;
            endcase
            if(SHARED_TEMPLATE && shared_template_valid && shared_header_bad)begin shared_template_valid<=0;template_fault<=1;bad<=1;end
            if(SHARED_TEMPLATE && !STREAM_WORDS && word_valid && state!=IDLE)begin bad<=1;if(template_loading)template_fault<=1;end
        end
    end
endmodule
