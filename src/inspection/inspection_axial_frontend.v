`timescale 1ns/1ps
// 完整像素帧前端：底板分离、行段连通域、主轴估计及四目标紧凑描述。
// 后处理必须在下一源帧到达前排空；忙时新帧只报错，不假装采集成功。
module inspection_axial_frontend #(
    parameter IMAGE_WIDTH=1920,IMAGE_HEIGHT=1080,MAX_RUNS=2048,MAX_LABELS=64,OUTPUT_CYCLE=0,LUMA_DISTANCE=0,STREAM_DESCRIPTORS=0,SINGLE_TARGET=0
)(
    input wire clk,rst_n,in_valid,in_frame_start,
    input wire [10:0] in_x,in_y,
    input wire [31:0] in_frame_id,
    input wire [23:0] in_rgb,cfg_background,
    input wire [7:0] cfg_threshold,
    input wire cfg_ready,in_learn,
    output wire ready_for_frame,
    output wire result_valid,
    input wire result_ready,
    output reg [31:0] result_frame_id,
    output reg [2:0] object_count,
    output wire [7351:0] descriptors,
    input wire descriptor_read,
    input wire [31:0] descriptor_read_frame,
    input wire [1:0] descriptor_read_object,
    input wire [4:0] descriptor_read_word,
    output reg descriptor_valid,descriptor_error,
    output reg [63:0] descriptor_data,
    output reg [31:0] descriptor_frame,
    output reg [1:0] descriptor_object,
    output reg [4:0] descriptor_word,
    output reg [43:0] centers_x,centers_y,boxes_x0,boxes_x1,boxes_y0,boxes_y1,
    output reg [87:0] areas,
    output reg [67:0] angles_q8,
    output reg [3:0] invalid_objects,
    output reg result_learn,
    output reg [7:0] frame_error,
    output reg fault,
    output reg [31:0] frame_cycles,processing_cycles,post_cycles,profile_cycles,ram_accesses,max_ram_wait,
    input wire session_clear
);
    localparam IDLE=0,CAPTURE=1,OBJECTS=2,GEO=3,GEO_WAIT=4,TRIG=5,TRIG_WAIT=6,PROFILE=7,PROFILE_WAIT=8,OUTPUT=9,STORE=10,SELECT_ONE=11,SELECT_WAIT=12;
    localparam AW=$clog2(MAX_RUNS);
    reg [3:0] state;
    reg [7351:0] legacy_descriptors;
    assign descriptors=STREAM_DESCRIPTORS?7352'd0:legacy_descriptors;
    reg [64:0] descriptor_ram[0:(SINGLE_TARGET?32:128)-1];
    reg [64:0] descriptor_q;
    reg [4:0] store_word;
    reg [1:0] store_phase;
    reg [63:0] store_selected;
    reg store_parity;
    reg [3:0] stored_objects;
    reg descriptor_pending,read_bad;
    reg [31:0] read_frame;
    reg [1:0] read_object;
    reg [4:0] read_word;
    reg [2:0] received,selected;
    reg learn_pending,input_bad,abort_processing;
    // 必须先声明再在generate内引用，防止生成域出现隐式同名悬空复位网。
    wire processing_rst_n=rst_n && !abort_processing && !(SINGLE_TARGET && session_clear===1'b1);
    reg [1:0] original_object;
    wire [2:0] profile_object=SINGLE_TARGET?({1'b0,original_object}+3'd1):(selected+3'd1);
    wire select_ready,select_valid,select_ok,select_uncertain;
    wire [1:0] select_index;wire [31:0] select_frame;
    generate if(SINGLE_TARGET)begin: single_selection
        inspection_single_selector select_target(.clk(clk),.rst_n(processing_rst_n),.clear(session_clear===1'b1),
            .in_valid(state==SELECT_ONE),.in_ready(select_ready),.frame_id(result_frame_id),.count(object_count),.frame_error(frame_error),
            .areas(areas),.boxes_x0(boxes_x0),.boxes_x1(boxes_x1),.boxes_y0(boxes_y0),.boxes_y1(boxes_y1),.invalid_objects(invalid_objects),
            .out_valid(select_valid),.out_ready(state==SELECT_WAIT),.out_frame_id(select_frame),.selected_valid(select_ok),.uncertain(select_uncertain),
            .selected_index(select_index),.ignored_count(),.cycles());
    end else begin: legacy_selection
        assign select_ready=1'b0;assign select_valid=1'b0;assign select_ok=1'b0;assign select_uncertain=1'b0;assign select_index=0;assign select_frame=0;
    end endgenerate
    reg [31:0] sx[0:3],sy[0:3];
    reg [43:0] sxx[0:3],syy[0:3],sxy[0:3];
    reg [18:0] cx,cy;
    reg signed [15:0] axis,c,s;
    reg bad_geometry;
    reg [31:0] input_id;
    wire fg_valid,fg_mask,fg_start,fg_fault;
    wire [10:0] fg_x,fg_y;wire [31:0] fg_id;
    inspection_foreground #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),.LUMA_DISTANCE(LUMA_DISTANCE)) foreground(
        .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_frame_start(in_frame_start),.in_hsync(1'b0),.in_vsync(1'b0),
        .in_x(in_x),.in_y(in_y),.in_frame_id(in_frame_id),.in_rgb(in_rgb),.cfg_background(cfg_background),.cfg_threshold(cfg_threshold),.cfg_ready(cfg_ready),
        .out_valid(fg_valid),.out_mask(fg_mask),.out_frame_start(fg_start),.out_hsync(),.out_vsync(),.out_x(fg_x),.out_y(fg_y),.out_frame_id(fg_id),.fault_seen(fg_fault));
    wire rv,fd,fb;wire [10:0] rx0,rx1,ry;wire [31:0] rid;wire [21:0] pixels;wire [20:0] runs;
    inspection_run_encoder #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT)) encoder(
        .clk(clk),.rst_n(processing_rst_n),.in_valid(fg_valid),.in_mask(fg_mask),.in_frame_start(fg_start),.in_x(fg_x),.in_y(fg_y),.in_frame_id(fg_id),
        .run_valid(rv),.run_x0(rx0),.run_x1(rx1),.run_y(ry),.run_frame_id(rid),.frame_done(fd),.frame_bad(fb),.frame_pixels(pixels),.frame_runs(runs));
    wire cs,cr,cv,ov,clipped,pfault,read_valid;
    wire [31:0] cfid,ccycles,osx,osy,read_fid;
    wire [7:0] cerr;wire [2:0] cn,oid,read_oid;
    wire [21:0] oa;wire [10:0] ox0,ox1,oy0,oy1,read_x0,read_x1,read_y;
    wire [43:0] osxx,osyy,osxy;
    wire read_enable;wire [AW-1:0] read_index;
    inspection_components #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),.MAX_RUNS(MAX_RUNS),.MAX_LABELS(MAX_LABELS),.MIN_AREA(16)) components(
        .clk(clk),.rst_n(processing_rst_n),.start_valid(fg_start),.start_ready(cs),.start_frame_id(fg_id),
        .run_valid(rv),.run_ready(cr),.in_x0(rx0),.in_x1(rx1),.in_y(ry),.in_frame_id(rid),.frame_done(fd),.frame_bad(fb || input_bad),.pixel_count(pixels),
        .result_valid(cv),.result_ready(state==CAPTURE),.result_frame_id(cfid),.result_error(cerr),.object_count(cn),.process_cycles(ccycles),
        .object_valid(ov),.object_ready(state==OBJECTS),.object_id(oid),.object_clipped(clipped),.object_area(oa),.object_x0(ox0),.object_x1(ox1),.object_y0(oy0),.object_y1(oy1),
        .object_seed_x(),.object_seed_y(),.object_sum_x(osx),.object_sum_y(osy),.object_sum_xx(osxx),.object_sum_yy(osyy),.object_sum_xy(osxy),.protocol_fault(pfault),
        .record_read(read_enable),.record_index(read_index),.record_valid(read_valid),.record_frame_id(read_fid),.record_x0(read_x0),.record_x1(read_x1),.record_y(read_y),.record_object_id(read_oid));
    wire gr,gv,gb,gm;wire [31:0] gfid;wire [2:0] goid;wire [18:0] gcx,gcy;wire signed [15:0] ga;
    inspection_geometry geometry(.clk(clk),.rst_n(processing_rst_n),.in_valid(state==GEO),.in_ready(gr),.in_frame_id(result_frame_id),.in_object_id(selected+3'd1),
        .in_area(areas[selected[1:0]*22 +:22]),.in_sum_x(sx[selected[1:0]]),.in_sum_y(sy[selected[1:0]]),.in_sum_xx(sxx[selected[1:0]]),.in_sum_yy(syy[selected[1:0]]),.in_sum_xy(sxy[selected[1:0]]),
        .out_valid(gv),.out_ready(state==GEO_WAIT),.out_frame_id(gfid),.out_object_id(goid),.center_x_q8(gcx),.center_y_q8(gcy),.axis_angle_q8(ga),.axis_unreliable(gb),.invalid_moments(gm));
    wire tr,tv,tbad;wire [31:0] tfid;wire [2:0] toid;wire signed [15:0] tc,ts;
    inspection_angle_sincos trig(.clk(clk),.rst_n(processing_rst_n),.in_valid(state==TRIG),.in_ready(tr),.frame_id(result_frame_id),.template_frame_id(result_frame_id),.object_id(selected+3'd1),.angle_q8({axis[15],axis}),
        .out_valid(tv),.out_ready(state==TRIG_WAIT),.out_frame_id(tfid),.out_template_id(),.out_object_id(toid),.cosine_q14(tc),.sine_q14(ts),.invalid_angle(tbad));
    wire pr,pv,pbad;wire [31:0] pfid,pcycles,paccess,pwait;wire [2:0] poid;wire [1837:0] profile;
    inspection_axial_profile #(.MAX_RUNS(MAX_RUNS)) projector(.clk(clk),.rst_n(processing_rst_n),.start_valid(state==PROFILE),.start_ready(pr),
        .frame_id(result_frame_id),.object_id(profile_object),.run_count(runs[AW:0]),.center_x_q8(cx),.center_y_q8(cy),.cosine_q14(c),.sine_q14(s),.invalid_geometry(bad_geometry),
        .record_read(read_enable),.record_index(read_index),.record_valid(read_valid),.record_frame_id(read_fid),.record_x0(read_x0),.record_x1(read_x1),.record_y(read_y),.record_object_id(read_oid),
        .result_valid(pv),.result_ready(STREAM_DESCRIPTORS?(state==STORE && store_phase==2 && store_word==28):(state==PROFILE_WAIT)),.result_frame_id(pfid),.result_object_id(poid),.descriptor(profile),.invalid(pbad),.cycles(pcycles),.accesses(paccess),.max_wait(pwait));
    wire [63:0] profile_words[0:28];
    genvar word_chunk;
    generate for(word_chunk=0;word_chunk<29;word_chunk=word_chunk+1)begin: profile_chunks
        if(word_chunk<28)assign profile_words[word_chunk]=profile[word_chunk*64+:64];
        else assign profile_words[word_chunk]={18'd0,profile[1837:1792]};
    end endgenerate
    wire [63:0] store_data=profile_words[store_word];
    // 一个同步写口和一个同步读口；不通过复位清空RAM，valid掩码界定本帧完整记录。
    always @(posedge clk)begin
        if(rst_n && STREAM_DESCRIPTORS && state==STORE && pv && store_phase==2 && store_word<=28 && !abort_processing)
            descriptor_ram[SINGLE_TARGET?{2'd0,store_word}:{selected[1:0],store_word}]<={store_parity,store_selected};
        descriptor_q<=descriptor_ram[SINGLE_TARGET?{2'd0,descriptor_read_word}:{descriptor_read_object,descriptor_read_word}];
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            descriptor_pending<=0;descriptor_valid<=0;descriptor_error<=0;descriptor_data<=0;
            descriptor_frame<=0;descriptor_object<=0;descriptor_word<=0;
            read_bad<=0;read_frame<=0;read_object<=0;read_word<=0;
        end else begin
            descriptor_pending<=STREAM_DESCRIPTORS && descriptor_read;
            descriptor_valid<=descriptor_pending;descriptor_error<=0;
            if(STREAM_DESCRIPTORS && descriptor_read)begin
                read_frame<=result_frame_id;read_object<=descriptor_read_object;read_word<=descriptor_read_word;
                read_bad<=state!=OUTPUT || !result_valid || descriptor_read_frame!=result_frame_id ||
                    {1'b0,descriptor_read_object}>=object_count || descriptor_read_word>=29 || !stored_objects[descriptor_read_object];
            end
            if(descriptor_pending)begin
                descriptor_frame<=read_frame;descriptor_object<=read_object;descriptor_word<=read_word;
                descriptor_error<=read_bad || ((^descriptor_q)!==1'b0);
                descriptor_data<=(read_bad || ((^descriptor_q)!==1'b0))?64'd0:descriptor_q[63:0];
            end
        end
    end
    assign ready_for_frame=state==IDLE && cs;
    // 固定提交时刻仅用于结果帧节拍；不放宽处理时钟，也不改变像素接收速率。
    assign result_valid=state==OUTPUT && frame_cycles>=OUTPUT_CYCLE;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;received<=0;selected<=0;original_object<=0;cx<=0;cy<=0;axis<=0;c<=0;s<=0;bad_geometry<=0;learn_pending<=0;input_bad<=0;input_id<=0;abort_processing<=0;store_word<=0;stored_objects<=0;
            store_phase<=0;store_selected<=0;store_parity<=0;
            result_frame_id<=0;object_count<=0;legacy_descriptors<=0;centers_x<=0;centers_y<=0;boxes_x0<=0;boxes_x1<=0;boxes_y0<=0;boxes_y1<=0;areas<=0;angles_q8<=0;invalid_objects<=0;result_learn<=0;frame_error<=0;
            fault<=0;frame_cycles<=0;processing_cycles<=0;post_cycles<=0;profile_cycles<=0;ram_accesses<=0;max_ram_wait<=0;
        end else begin
            abort_processing<=0;
            if(in_frame_start)begin learn_pending<=in_learn;input_id<=in_frame_id;input_bad<=0;end
            else if(in_valid && in_frame_id!=input_id)input_bad<=1;
            if(state!=IDLE && state!=OUTPUT)frame_cycles<=frame_cycles+1'b1;
            if(state==OUTPUT && processing_cycles==0)processing_cycles<=frame_cycles;
            if(state==OUTPUT && frame_cycles<OUTPUT_CYCLE)frame_cycles<=frame_cycles+1'b1;
            if(state!=IDLE && state!=CAPTURE && state!=OUTPUT)post_cycles<=post_cycles+1'b1;
            if(fg_fault || pfault)fault<=1;
            if(STREAM_DESCRIPTORS && descriptor_valid && descriptor_error)fault<=1;
            if(fg_start && !ready_for_frame)begin fault<=1;frame_error[7]<=1;end
            case(state)
                IDLE:if(fg_start)begin
                    state<=CAPTURE;result_frame_id<=fg_id;object_count<=0;legacy_descriptors<=0;stored_objects<=0;centers_x<=0;centers_y<=0;boxes_x0<=0;boxes_x1<=0;boxes_y0<=0;boxes_y1<=0;areas<=0;angles_q8<=0;invalid_objects<=0;
                    frame_error<=0;received<=0;selected<=0;result_learn<=learn_pending;frame_cycles<=0;processing_cycles<=0;post_cycles<=0;profile_cycles<=0;ram_accesses<=0;max_ram_wait<=0;
                end
                CAPTURE:if(cv)begin
                    object_count<=cn;frame_error<=cerr;
                    if(cfid!=result_frame_id)begin frame_error[6]<=1;object_count<=0;state<=OUTPUT;end
                    else if(cn==0 || cerr!=0)state<=SINGLE_TARGET?SELECT_ONE:OUTPUT;
                    else state<=OBJECTS;
                end
                OBJECTS:if(ov)begin
                    areas[received[1:0]*22 +:22]<=oa;boxes_x0[received[1:0]*11 +:11]<=ox0;boxes_x1[received[1:0]*11 +:11]<=ox1;
                    boxes_y0[received[1:0]*11 +:11]<=oy0;boxes_y1[received[1:0]*11 +:11]<=oy1;
                    sx[received[1:0]]<=osx;sy[received[1:0]]<=osy;sxx[received[1:0]]<=osxx;syy[received[1:0]]<=osyy;sxy[received[1:0]]<=osxy;
                    invalid_objects[received[1:0]]<=clipped || oid!=received+1'b1;received<=received+1'b1;
                    if(received+1==object_count)state<=SINGLE_TARGET?SELECT_ONE:GEO;
                end
                SELECT_ONE:if(select_ready)state<=SELECT_WAIT;
                SELECT_WAIT:if(select_valid)begin
                    if(!select_ok || select_uncertain || select_frame!=result_frame_id)begin object_count<=0;invalid_objects<=0;state<=OUTPUT;end
                    else begin
                        original_object<=select_index;object_count<=1;selected<=0;
                        areas<={66'd0,areas[select_index*22+:22]};
                        boxes_x0<={33'd0,boxes_x0[select_index*11+:11]};boxes_x1<={33'd0,boxes_x1[select_index*11+:11]};
                        boxes_y0<={33'd0,boxes_y0[select_index*11+:11]};boxes_y1<={33'd0,boxes_y1[select_index*11+:11]};
                        sx[0]<=sx[select_index];sy[0]<=sy[select_index];sxx[0]<=sxx[select_index];syy[0]<=syy[select_index];sxy[0]<=sxy[select_index];
                        invalid_objects<={3'd0,invalid_objects[select_index]};state<=GEO;
                    end
                end
                GEO:if(gr)state<=GEO_WAIT;
                GEO_WAIT:if(gv)begin
                    cx<=gcx;cy<=gcy;axis<=ga;bad_geometry<=gb || gm || invalid_objects[selected[1:0]] || gfid!=result_frame_id || goid!=selected+1'b1;
                    centers_x[selected[1:0]*11 +:11]<=gcx[18:8];centers_y[selected[1:0]*11 +:11]<=gcy[18:8];angles_q8[selected[1:0]*17 +:17]<={ga[15],ga};state<=TRIG;
                end
                TRIG:if(tr)state<=TRIG_WAIT;
                TRIG_WAIT:if(tv)begin c<=tc;s<=ts;bad_geometry<=bad_geometry || tbad || tfid!=result_frame_id || toid!=selected+1'b1;state<=PROFILE;end
                PROFILE:if(pr)state<=PROFILE_WAIT;
                PROFILE_WAIT:if(pv)begin
                    if(STREAM_DESCRIPTORS)begin store_word<=0;store_phase<=0;state<=STORE;end
                    else begin
                    // 固定写使能和分片，避免综合7352位动态写掩码。
                    case(selected[1:0])
                        0:legacy_descriptors[1837:0]<=profile;
                        1:legacy_descriptors[3675:1838]<=profile;
                        2:legacy_descriptors[5513:3676]<=profile;
                        default:legacy_descriptors[7351:5514]<=profile;
                    endcase
                    invalid_objects[selected[1:0]]<=bad_geometry || pbad || pfid!=result_frame_id || poid!=profile_object;
                    profile_cycles<=profile_cycles+pcycles;ram_accesses<=ram_accesses+paccess;if(pwait>max_ram_wait)max_ram_wait<=pwait;
                    if(selected+1==object_count)state<=OUTPUT;else begin selected<=selected+1'b1;state<=GEO;end
                    end
                end
                STORE:if(!pv)begin fault<=1;frame_error[6]<=1;object_count<=0;stored_objects<=0;state<=OUTPUT;end
                // 只锁存选中的64位；任务帧号、对象号和投影结果保持到最后一字实际写入。
                else if(store_phase==0)begin store_selected<=store_data;store_phase<=1;end
                else if(store_phase==1)begin store_parity<=^store_selected;store_phase<=2;end
                else if(store_phase!=2 || store_word>28)begin fault<=1;frame_error[6]<=1;object_count<=0;stored_objects<=0;state<=OUTPUT;end
                else if(store_word==28)begin
                    stored_objects[selected[1:0]]<=pfid==result_frame_id && poid==profile_object;
                    invalid_objects[selected[1:0]]<=bad_geometry || pbad || pfid!=result_frame_id || poid!=profile_object;
                    profile_cycles<=profile_cycles+pcycles;ram_accesses<=ram_accesses+paccess;if(pwait>max_ram_wait)max_ram_wait<=pwait;
                    if(selected+1==object_count)state<=OUTPUT;else begin selected<=selected+1'b1;state<=GEO;end
                end else begin store_word<=store_word+1'b1;store_phase<=0;end
                OUTPUT:if(result_valid && result_ready)state<=IDLE;
                default:state<=IDLE;
            endcase
            // 缺像素或异常复杂输入不能阻塞后续视频帧；终止本帧并报告UNKNOWN。
            if(state!=IDLE && state!=OUTPUT && frame_cycles>=2440000)begin
                abort_processing<=1;frame_error<=8'h80;invalid_objects<=4'hf;object_count<=0;legacy_descriptors<=0;stored_objects<=0;state<=OUTPUT;
            end
            if(SINGLE_TARGET && session_clear===1'b1)begin
                state<=IDLE;object_count<=0;stored_objects<=0;learn_pending<=0;input_bad<=0;received<=0;selected<=0;
            end
        end
    end
endmodule
