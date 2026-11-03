`timescale 1ns/1ps
// 四目标事件调度；队列中直接保存紧凑描述，排队不再引用可被覆盖的整帧行段。
module inspection_axial_manager #(
    parameter JOB_TIMEOUT=2048,DRAIN_LIMIT=5000,QUEUE_TIMEOUT=29700000,INPUT_STREAM=0,READ_TIMEOUT=64,RAM_WORKER=0,
    parameter SHARED_TEMPLATE=0,TEMPLATE_DRAIN_LIMIT=12000,TEMPLATE_LOAD_LIMIT=256,STREAM_WORDS=0,PARALLEL_EXPIRE=1,TRACK_CAPACITY=4,SESSION_CONTROL=0
)(
    input wire clk,rst_n,in_valid,
    output wire in_ready,
    input wire [31:0] frame_id,config_frame_id,
    input wire [2:0] object_count,
    input wire [7351:0] descriptors,
    output wire source_read,
    output wire [31:0] source_read_frame,
    output wire [1:0] source_read_object,
    output wire [4:0] source_read_word,
    input wire source_valid,source_error,
    input wire [63:0] source_data,
    input wire [31:0] source_frame,
    input wire [1:0] source_object,
    input wire [4:0] source_word,
    input wire [43:0] centers_x,centers_y,boxes_x0,boxes_x1,boxes_y0,boxes_y1,
    input wire [87:0] areas,
    input wire [67:0] angles_q8,
    input wire [3:0] invalid_objects,
    input wire [7:0] frame_error,
    input wire learn,backend_pause,
    output wire result_valid,
    input wire result_ready,
    output reg [31:0] result_frame_id,
    output reg [2:0] result_count,
    output reg [63:0] result_track_ids,
    output reg [7:0] result_status,
    output reg [127:0] detection_frame_ids,
    output reg [3:0] cached_results,
    output reg [31:0] result_reasons,
    output reg template_valid,
    output reg learned,fault,
    output reg [31:0] submitted,completed,stale_results,overflows,timeouts,
    output reg [31:0] frame_cycles,max_job_cycles,max_queue_wait,
    output reg [2:0] queue_depth,queue_high_water,
    input wire session_clear
);
    localparam IDLE=0,TRACK=1,TRACK_WAIT=2,SCAN=3,EXPIRE=4,DRAIN=5,OUTPUT=6,
               WORD_READ=7,WORD_USE=8,WORD_QUEUE=9,COMMIT=10,CAPTURE=11,CAPTURE_ACK=12,WORD_WAIT=13,LEARN_READ=14,LEARN_WAIT=15,
               LEARN_DRAIN=16,LEARN_BEGIN=17,LEARN_COMMIT=18;
    reg [4:0] state;
    reg [2:0] index,n;
    // 上游在valid且未ready时保持整组输入；116字完成后才确认接受。
    // 每目标32字槽、使用29字，全部字段和4目标容量不变。
    reg [64:0] snapshot_ram[0:127];
    reg [64:0] snapshot_q;
    reg [1:0] capture_object;
    reg [4:0] capture_word;
    reg stream_hold;
    reg [63:0] stream_data;
    reg [31:0] source_wait;
    reg [1837:0] reference;
    reg [872:0] observations;
    reg [3:0] active,seen,pending,good;
    reg [15:0] ids[0:TRACK_CAPACITY-1];
    reg [31:0] generation[0:TRACK_CAPACITY-1],detect_fid[0:TRACK_CAPACITY-1];
    reg [7:0] stable[0:TRACK_CAPACITY-1];
    reg [1:0] status[0:TRACK_CAPACITY-1];
    // 0..127为4个anchor，128..255为4项队列；每槽32字，实际使用29字。
    reg [64:0] descriptor_ram[0:TRACK_CAPACITY*64-1];
    reg [64:0] descriptor_q;
    reg [3:0] anchor_valid;
    reg [4:0] word_i,load_i;
    reg [1:0] selected_slot,reserved_slot;
    reg [15:0] selected_track;
    reg selected_invalid,selected_changed,selected_bad,selected_has_slot,reserved;
    reg [1:0] load_state;
    reg [1855:0] load_descriptor;
    reg load_bad;
    reg [63:0] track_ids;
    reg [31:0] risks;
    reg [31:0] qfid[0:TRACK_CAPACITY-1],qgen[0:TRACK_CAPACITY-1],qtime[0:TRACK_CAPACITY-1];
    reg [31:0] qtemplate[0:TRACK_CAPACITY-1];
    reg [31:0] template_version,work_template_version;
    reg [15:0] qtid[0:TRACK_CAPACITY-1];
    reg [1:0] qslot[0:TRACK_CAPACITY-1];
    reg [1:0] wr,rd;
    reg busy,reset_worker,reset_tracker;
    reg [31:0] clock_count,work_start,work_generation,work_frame;
    reg [15:0] work_track;
    reg [1:0] work_slot;
    reg [31:0] drain_cycles;
    wire tr,tv;wire [31:0] tfid,trisks,tc;wire [2:0] tn;wire [63:0] tids;
    wire [31:0] ofid,cfg;wire [127:0] ofids;
    wire [2:0] on;wire [43:0] ox,oy,ox0,ox1,oy0,oy1;
    wire [87:0] oa;wire [67:0] oangles;wire [127:0] scores;wire [3:0] obad;
    wire [11:0] distance_limit;wire [21:0] area_limit;wire [16:0] angle_limit;wire [31:0] contour_limit,margin;wire [10:0] gap;
    assign {ofid,cfg,ofids,on,ox,oy,ox0,ox1,oy0,oy1,oa,oangles,scores,obad,distance_limit,area_limit,angle_limit,contour_limit,margin,gap}=observations;
    inspection_object_tracker #(.TRACK_CAPACITY(TRACK_CAPACITY)) tracker(.clk(clk),.rst_n(rst_n&&!reset_tracker),.in_valid(state==TRACK),.in_ready(tr),
        .frame_id(ofid),.config_frame_id(cfg),.object_frame_ids(ofids),.object_count(on),.centers_x(ox),.centers_y(oy),.boxes_x0(ox0),.boxes_x1(ox1),.boxes_y0(oy0),.boxes_y1(oy1),.areas(oa),.angles_q8(oangles),.contour_scores(scores),.invalid_objects(obad),
        .max_distance(distance_limit),.max_area_change(area_limit),.max_angle_change_q8(angle_limit),.max_contour_change(contour_limit),.ambiguity_margin(margin),.proximity_gap(gap),
        .out_valid(tv),.out_ready(state==TRACK_WAIT),.out_frame_id(tfid),.out_count(tn),.track_ids(tids),.risk_flags(trisks),.process_cycles(tc));
    wire worker_ready,wv;wire [31:0] wfid,wcycles;wire [15:0] wtid;wire [1:0] wstatus;wire [7:0] wreasons;
    wire shared_mode=RAM_WORKER && INPUT_STREAM && SHARED_TEMPLATE;
    wire source_bad=source_error || source_frame!=result_frame_id || source_object!=source_read_object || source_word!=word_i;
    wire template_draining=shared_mode && state==LEARN_DRAIN;
    // 数据来源由稳定阶段选择；帧号校验仅决定是否接收，不再串入64位数据选择。
    wire template_context=shared_mode && state==LEARN_WAIT;
    wire template_word=template_context && source_valid && !source_bad;
    wire template_ready,template_done,template_fault,worker_template_valid;
    wire worker_word_ready;
    wire [31:0] worker_template_version,wtemplate;
    // 固定槽先精确比较，再选1位，避免rd经32位片选/减法/比较反馈自身CE。
    wire [3:0] expired_slots;
    genvar expiry_slot;
    generate for(expiry_slot=0;expiry_slot<TRACK_CAPACITY;expiry_slot=expiry_slot+1)begin: queue_expiry_lanes
        assign expired_slots[expiry_slot]=(clock_count-qtime[expiry_slot])>=QUEUE_TIMEOUT;
    end endgenerate
    wire expired=queue_depth!=0 && (PARALLEL_EXPIRE?expired_slots[rd]:((clock_count-qtime[rd])>=QUEUE_TIMEOUT));
    wire foreground_port=state==WORD_READ || state==WORD_WAIT || state==WORD_USE || state==WORD_QUEUE;
    wire queue_word=load_state==2 && !foreground_port && !expired;
    wire owner_conflict=template_context && queue_word;
    wire launch=load_state==3 && queue_depth!=0 && !busy && (!backend_pause || template_draining) && !reset_worker && state!=OUTPUT && !(state==CAPTURE_ACK && learn) && !expired;
    wire worker_result_ready=state==DRAIN || state==IDLE || template_draining;
    wire take_result=wv && worker_result_ready;
    generate if(RAM_WORKER)begin: memory_worker
    // 队列读返回直接流入worker；不再另存1856位并行装载副本。
    inspection_axial_compare_ram #(.QUEUED_SCENE(1),.SHARED_TEMPLATE(INPUT_STREAM && SHARED_TEMPLATE),.STREAM_WORDS(INPUT_STREAM && SHARED_TEMPLATE && STREAM_WORDS)) worker(.clk(clk),.rst_n(shared_mode?rst_n:(rst_n&&!reset_worker)),.start_valid(launch),.start_ready(worker_ready),.frame_id(qfid[rd]),.track_id(qtid[rd]),
        .scene_descriptor(1838'd0),.template_descriptor(shared_mode?1838'd0:reference),.template_valid(template_valid),.data_invalid(load_bad),
        .word_valid(!owner_conflict && (template_word || queue_word)),.word_ready(worker_word_ready),.word_index(template_context?word_i:load_i),.word_data(template_context?source_data:descriptor_q[63:0]),.word_frame(template_context?result_frame_id:qfid[rd]),.word_track(template_context?16'd0:qtid[rd]),
        .word_is_template(template_context),.abort_job(reset_worker),.template_start(shared_mode && state==LEARN_BEGIN),.template_ready(template_ready),
        .template_frame_id(result_frame_id),.template_version_in(template_version),.task_template_version(qtemplate[rd]),
        .template_done(template_done),.template_fault(template_fault),.shared_template_valid(worker_template_valid),.shared_template_version(worker_template_version),.result_template_version(wtemplate),
        .result_valid(wv),.result_ready(worker_result_ready),.result_frame_id(wfid),.result_track_id(wtid),.status(wstatus),.reasons(wreasons),.cycles(wcycles),.count_difference(),.width_difference());
    end else begin: parallel_worker
    inspection_axial_compare worker(.clk(clk),.rst_n(rst_n&&!reset_worker),.start_valid(launch),.start_ready(worker_ready),.frame_id(qfid[rd]),.track_id(qtid[rd]),
        .scene_descriptor(load_descriptor[1837:0]),.template_descriptor(reference),.template_valid(template_valid),.data_invalid(load_bad),
        .result_valid(wv),.result_ready(worker_result_ready),.result_frame_id(wfid),.result_track_id(wtid),.status(wstatus),.reasons(wreasons),.cycles(wcycles),.count_difference(),.width_difference());
    assign template_ready=1'b0;assign template_done=1'b0;assign template_fault=1'b0;assign worker_template_valid=1'b0;assign worker_template_version=0;assign wtemplate=0;
    assign worker_word_ready=1'b1;
    end endgenerate
    // 空闲可预告ready；valid到达后先背压装载，ACK拍才真正握手。
    assign in_ready=INPUT_STREAM?((state==IDLE && !in_valid)||(state==OUTPUT && stream_hold)):
                    ((state==IDLE && !in_valid) || state==CAPTURE_ACK);
    assign source_read=INPUT_STREAM && (state==WORD_READ || (state==LEARN_READ && (!shared_mode || worker_word_ready)));
    assign source_read_frame=result_frame_id;
    assign source_read_object=(state==LEARN_READ || state==LEARN_WAIT)?2'd0:index[1:0];
    assign source_read_word=word_i;
    assign result_valid=state==OUTPUT;
    integer k,slot,free_slot;
    reg push,pop,changed,invalid;
    reg [31:0] next_gen;
    reg [7:0] next_stable;
    reg [15:0] current_track;
    // 输入只接窄字选择器，不再额外锁存7352位并行快照。
    wire [63:0] input_words[0:127];
    genvar a,w;
    generate for(a=0;a<4;a=a+1)begin: input_objects
        for(w=0;w<32;w=w+1)begin: input_chunks
            if(w<28)assign input_words[a*32+w]=descriptors[a*1838+w*64+:64];
            else if(w==28)assign input_words[a*32+w]={18'd0,descriptors[a*1838+1792+:46]};
            else assign input_words[a*32+w]=64'd0;
        end
    end endgenerate
    wire capture_write=!INPUT_STREAM && in_valid && (state==IDLE || state==CAPTURE);
    wire [6:0] capture_address=state==IDLE?7'd0:{capture_object,capture_word};
    wire [63:0] capture_data=input_words[capture_address];
    wire [63:0] current_word=INPUT_STREAM?stream_data:snapshot_q[63:0];
    wire snapshot_bad=!INPUT_STREAM && ((^snapshot_q)!==1'b0);
    // 独立同步读写口；未完整装载不交给前台处理，复位不清RAM数组。
    always @(posedge clk)begin
        if(rst_n && capture_write)snapshot_ram[capture_address]<={^capture_data,capture_data};
        snapshot_q<=snapshot_ram[{index[1:0],word_i}];
    end
    wire [7:0] descriptor_address=TRACK_CAPACITY==1?(foreground_port?{3'd0,word_i}:{3'd1,load_i}):(foreground_port?{1'b0,selected_slot,word_i}:{1'b1,rd,load_i});
    wire descriptor_bad=(^descriptor_q)!==1'b0;
    wire anchor_write=state==WORD_USE && !selected_invalid && !selected_bad;
    wire queue_write=state==WORD_QUEUE && !selected_invalid && !selected_bad && reserved;
    wire [7:0] write_address=TRACK_CAPACITY==1?(anchor_write?{3'd0,word_i}:{3'd1,word_i}):(anchor_write?{1'b0,selected_slot,word_i}:{1'b1,reserved_slot,word_i});
    // 一个同步读口、一个同步写口；前台比较与后台取队列按阶段仲裁，不复制宽RAM。
    always @(posedge clk)begin
        if(rst_n && (anchor_write || queue_write))descriptor_ram[write_address]<={^current_word,current_word};
        descriptor_q<=descriptor_ram[descriptor_address];
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;index<=0;n<=0;capture_object<=0;capture_word<=0;stream_hold<=0;stream_data<=0;source_wait<=0;reference<=0;observations<=0;active<=0;seen<=0;pending<=0;good<=0;
            anchor_valid<=0;word_i<=0;load_i<=0;selected_slot<=0;reserved_slot<=0;selected_track<=0;
            selected_invalid<=0;selected_changed<=0;selected_bad<=0;selected_has_slot<=0;reserved<=0;load_state<=0;load_descriptor<=0;load_bad<=0;
            track_ids<=0;risks<=0;wr<=0;rd<=0;busy<=0;reset_worker<=0;reset_tracker<=0;clock_count<=0;work_start<=0;work_generation<=0;work_frame<=0;work_track<=0;work_slot<=0;drain_cycles<=0;
            result_frame_id<=0;result_count<=0;result_track_ids<=0;result_status<=0;detection_frame_ids<=0;cached_results<=0;result_reasons<=0;
            template_valid<=0;learned<=0;fault<=0;submitted<=0;completed<=0;stale_results<=0;overflows<=0;timeouts<=0;frame_cycles<=0;max_job_cycles<=0;max_queue_wait<=0;queue_depth<=0;queue_high_water<=0;
            template_version<=0;work_template_version<=0;
            for(k=0;k<TRACK_CAPACITY;k=k+1)begin ids[k]<=0;generation[k]<=0;detect_fid[k]<=0;stable[k]<=0;status[k]<=0;qtemplate[k]<=0;end
        end else begin
            clock_count<=clock_count+1'b1;reset_worker<=0;reset_tracker<=0;learned<=0;push=0;pop=0;
            if(INPUT_STREAM && in_ready && in_valid)stream_hold<=0;
            if(state!=IDLE && state!=OUTPUT)frame_cycles<=frame_cycles+1'b1;
            if(launch && worker_ready)begin
                pop=1;rd<=TRACK_CAPACITY==1?0:rd+1'b1;busy<=1;work_start<=clock_count;work_generation<=qgen[rd];work_frame<=qfid[rd];work_track<=qtid[rd];work_slot<=qslot[rd];
                load_state<=0;work_template_version<=qtemplate[rd];
                if(clock_count-qtime[rd]>max_queue_wait)max_queue_wait<=clock_count-qtime[rd];
            end
            // 前台抢占读口会使读返回失效；后台恢复时先重新发起同一地址。
            if(foreground_port)begin if(load_state==2)load_state<=1;end
            else begin
                case(load_state)
                    0:if(queue_depth!=0 && !busy && (!backend_pause || template_draining) && !expired && !reset_worker && state!=OUTPUT)begin
                        load_i<=0;load_bad<=0;load_state<=1;
                    end
                    1:load_state<=2;
                    2:if(!RAM_WORKER || worker_word_ready)begin
                        if(!RAM_WORKER)load_descriptor<={descriptor_q[63:0],load_descriptor[1855:64]};
                        if(descriptor_bad)begin load_bad<=1;fault<=1;end
                        if(load_i==28)load_state<=3;else begin load_i<=load_i+1'b1;load_state<=1;end
                    end
                    default:begin end
                endcase
            end
            if(expired && !busy && state!=SCAN && !foreground_port && state!=COMMIT && state!=EXPIRE && state!=OUTPUT)begin
                pop=1;rd<=TRACK_CAPACITY==1?0:rd+1'b1;timeouts<=timeouts+1'b1;fault<=1;
                load_state<=0;
                if(active[qslot[rd]] && generation[qslot[rd]]==qgen[rd])begin pending[qslot[rd]]<=0;good[qslot[rd]]<=0;stable[qslot[rd]]<=0;end
            end
            if(take_result)begin
                busy<=0;completed<=completed+1'b1;
                if(shared_mode && wstatus==0 && wreasons[7])fault<=1;
                if(wcycles>max_job_cycles)max_job_cycles<=wcycles;
                if(!busy || wfid!=work_frame || wtid!=work_track || (shared_mode && (wtemplate!=work_template_version || wtemplate!=template_version || !worker_template_valid || template_fault)))begin
                    fault<=1;stale_results<=stale_results+1'b1;
                    if(shared_mode && active[work_slot] && ids[work_slot]==work_track && generation[work_slot]==work_generation)begin pending[work_slot]<=0;good[work_slot]<=0;stable[work_slot]<=0;end
                end
                else if(active[work_slot] && ids[work_slot]==work_track && generation[work_slot]==work_generation)begin
                    pending[work_slot]<=0;good[work_slot]<=wstatus==1 || wstatus==2;status[work_slot]<=wstatus;detect_fid[work_slot]<=wfid;
                    if(state==DRAIN)for(k=0;k<4;k=k+1)if(k<n && result_track_ids[k*16 +:16]==work_track)begin
                        result_status[k*2 +:2]<=wstatus;result_reasons[k*8 +:8]<=wreasons;detection_frame_ids[k*32 +:32]<=wfid;cached_results[k]<=wfid!=result_frame_id;
                    end
                end else stale_results<=stale_results+1'b1;
            end
            if(busy && clock_count-work_start>=JOB_TIMEOUT && !take_result)begin
                reset_worker<=1;busy<=0;fault<=1;timeouts<=timeouts+1'b1;
                if(active[work_slot] && generation[work_slot]==work_generation)begin pending[work_slot]<=0;good[work_slot]<=0;stable[work_slot]<=0;end
            end
            case(state)
                IDLE:if(in_valid)begin
                    capture_object<=0;capture_word<=1;frame_cycles<=0;
                    if(INPUT_STREAM)begin stream_hold<=1;state<=CAPTURE_ACK;end else state<=CAPTURE;
                end
                CAPTURE:begin
                    if(!in_valid)begin fault<=1;state<=IDLE;end
                    else if(capture_word==28)begin
                        capture_word<=0;
                        if(capture_object==3)state<=CAPTURE_ACK;
                        else capture_object<=capture_object+1'b1;
                    end else capture_word<=capture_word+1'b1;
                end
                CAPTURE_ACK:if(!in_valid)begin fault<=1;state<=IDLE;end
                else begin
                    n<=object_count>TRACK_CAPACITY?0:object_count;result_count<=object_count>TRACK_CAPACITY?0:object_count;
                    result_frame_id<=frame_id;result_status<=0;result_track_ids<=0;detection_frame_ids<=0;cached_results<=0;result_reasons<=0;drain_cycles<=0;seen<=0;index<=0;
                    observations<={frame_id,config_frame_id,{4{frame_id}},object_count,centers_x,centers_y,boxes_x0,boxes_x1,boxes_y0,boxes_y1,areas,angles_q8,128'd0,
                        (invalid_objects | {4{frame_error!=0}}),12'd32,22'd4096,17'd5120,32'hffffffff,32'd1,11'd8};
                    if(learn)begin
                        if(object_count==1 && invalid_objects==0 && frame_error==0 && config_frame_id==frame_id)begin
                            if(shared_mode)begin drain_cycles<=0;end
                            else if(!INPUT_STREAM)begin reference<=descriptors[1837:0];template_valid<=1;learned<=1;end
                            else begin template_valid<=0;word_i<=0;end
                            if(!shared_mode)begin active<=0;good<=0;pending<=0;busy<=0;reset_worker<=1;reset_tracker<=1;wr<=0;rd<=0;queue_depth<=0;load_state<=0;anchor_valid<=0;end
                        end else begin fault<=1;result_reasons<=32'h40404040;end
                        if(shared_mode && object_count==1 && invalid_objects==0 && frame_error==0 && config_frame_id==frame_id)state<=LEARN_DRAIN;
                        else if(INPUT_STREAM && object_count==1 && invalid_objects==0 && frame_error==0 && config_frame_id==frame_id)state<=LEARN_READ;
                        else state<=OUTPUT;
                    end else state<=TRACK;
                end
                TRACK:if(tr)state<=TRACK_WAIT;
                TRACK_WAIT:if(tv)begin
                    track_ids<=tids;result_track_ids<=tids;risks<=trisks;
                    if(tfid!=result_frame_id || tn!=n)begin fault<=1;risks<=32'h80808080;end
                    state<=SCAN;
                end
                SCAN:begin
                    if(index>=n || index==TRACK_CAPACITY)begin index<=0;state<=EXPIRE;end
                    else if(queue_depth==TRACK_CAPACITY && !busy && !backend_pause && !expired)begin end
                    else begin
                        current_track=track_ids[index[1:0]*16 +:16];slot=-1;free_slot=-1;
                        for(k=0;k<TRACK_CAPACITY;k=k+1)begin if(active[k] && ids[k]==current_track)slot=k;if(!active[k] && free_slot<0)free_slot=k;end
                        if(slot<0)slot=free_slot;
                        invalid=current_track==0 || (risks[index[1:0]*8 +:8]&8'hf7)!=0 || !template_valid;
                        selected_slot<=slot<0?2'd0:slot[1:0];selected_track<=current_track;
                        selected_has_slot<=slot>=0;
                        selected_invalid<=slot<0 || invalid;
                        selected_changed<=slot<0 || !active[slot[1:0]] || ids[slot[1:0]]!=current_track || !anchor_valid[slot[1:0]];
                        selected_bad<=0;reserved<=queue_depth<TRACK_CAPACITY;reserved_slot<=wr;word_i<=0;state<=WORD_READ;
                    end
                end
                WORD_READ:begin source_wait<=0;state<=INPUT_STREAM?WORD_WAIT:WORD_USE;end
                WORD_WAIT:begin
                    source_wait<=source_wait+1'b1;
                    if(source_valid)begin
                        stream_data<=source_bad?64'd0:source_data;
                        if(source_bad)begin selected_bad<=1;fault<=1;end
                        state<=WORD_USE;
                    end else if(source_wait>=READ_TIMEOUT)begin
                        stream_data<=0;selected_bad<=1;fault<=1;state<=WORD_USE;
                    end
                end
                LEARN_READ:begin
                    if(!shared_mode || worker_word_ready)begin source_wait<=0;state<=LEARN_WAIT;end
                    else begin
                        source_wait<=source_wait+1'b1;
                        if(source_wait>=READ_TIMEOUT)begin reset_worker<=1;fault<=1;template_valid<=0;result_reasons<=32'h80808080;state<=OUTPUT;end
                    end
                end
                LEARN_DRAIN:begin
                    drain_cycles<=drain_cycles+1'b1;
                    if(queue_depth==0 && !busy && !wv && load_state==0)begin
                        active<=0;good<=0;pending<=0;reset_worker<=1;reset_tracker<=1;wr<=0;rd<=0;anchor_valid<=0;
                        template_valid<=0;word_i<=0;source_wait<=0;
                        if(template_version==32'hffffffff)begin fault<=1;result_reasons<=32'h80808080;state<=OUTPUT;end
                        else begin template_version<=template_version+1'b1;state<=LEARN_BEGIN;end
                    end else if(drain_cycles>=TEMPLATE_DRAIN_LIMIT)begin
                        fault<=1;template_valid<=0;good<=0;pending<=0;result_reasons<=32'h80808080;state<=OUTPUT;
                    end
                end
                LEARN_BEGIN:if(template_ready)begin source_wait<=0;state<=LEARN_READ;end
                LEARN_COMMIT:begin
                    source_wait<=source_wait+1'b1;
                    if(template_done)begin
                        if(template_fault || !worker_template_valid || worker_template_version!=template_version)begin fault<=1;template_valid<=0;result_reasons<=32'h80808080;end
                        else begin template_valid<=1;learned<=1;end
                        state<=OUTPUT;
                    end else if(source_wait>=TEMPLATE_LOAD_LIMIT)begin
                        reset_worker<=1;fault<=1;template_valid<=0;result_reasons<=32'h80808080;state<=OUTPUT;
                    end
                end
                LEARN_WAIT:begin
                    source_wait<=source_wait+1'b1;
                    if(source_valid)begin
                        if(source_bad || (shared_mode && !worker_word_ready))begin reset_worker<=shared_mode;fault<=1;template_valid<=0;result_reasons<=32'h80808080;state<=OUTPUT;end
                        else begin
                            if(!shared_mode)case(word_i)
                                0:reference[63:0]<=source_data;
                                1:reference[127:64]<=source_data;
                                2:reference[191:128]<=source_data;
                                3:reference[255:192]<=source_data;
                                4:reference[319:256]<=source_data;
                                5:reference[383:320]<=source_data;
                                6:reference[447:384]<=source_data;
                                7:reference[511:448]<=source_data;
                                8:reference[575:512]<=source_data;
                                9:reference[639:576]<=source_data;
                                10:reference[703:640]<=source_data;
                                11:reference[767:704]<=source_data;
                                12:reference[831:768]<=source_data;
                                13:reference[895:832]<=source_data;
                                14:reference[959:896]<=source_data;
                                15:reference[1023:960]<=source_data;
                                16:reference[1087:1024]<=source_data;
                                17:reference[1151:1088]<=source_data;
                                18:reference[1215:1152]<=source_data;
                                19:reference[1279:1216]<=source_data;
                                20:reference[1343:1280]<=source_data;
                                21:reference[1407:1344]<=source_data;
                                22:reference[1471:1408]<=source_data;
                                23:reference[1535:1472]<=source_data;
                                24:reference[1599:1536]<=source_data;
                                25:reference[1663:1600]<=source_data;
                                26:reference[1727:1664]<=source_data;
                                27:reference[1791:1728]<=source_data;
                                default:reference[1837:1792]<=source_data[45:0];
                            endcase
                            if(word_i==28)begin
                                if(shared_mode)begin source_wait<=0;state<=LEARN_COMMIT;end
                                else begin template_valid<=1;learned<=1;state<=OUTPUT;end
                            end
                            else begin word_i<=word_i+1'b1;state<=LEARN_READ;end
                        end
                    end else if(source_wait>=READ_TIMEOUT)begin reset_worker<=shared_mode;fault<=1;template_valid<=0;result_reasons<=32'h80808080;state<=OUTPUT;end
                end
                WORD_USE:begin
                    if(snapshot_bad)begin selected_bad<=1;fault<=1;end
                    if(!selected_invalid && active[selected_slot] && ids[selected_slot]==selected_track && anchor_valid[selected_slot])begin
                        if(descriptor_bad)begin selected_bad<=1;fault<=1;end
                        if(descriptor_q[63:0]!==current_word)selected_changed<=1;
                    end
                    state<=WORD_QUEUE;
                end
                WORD_QUEUE:begin
                    if(word_i==28)state<=COMMIT;else begin word_i<=word_i+1'b1;state<=WORD_READ;end
                end
                COMMIT:begin
                        slot=selected_has_slot?selected_slot:-1;current_track=selected_track;invalid=selected_invalid || selected_bad;
                        if(slot<0 || invalid)begin
                            result_reasons[index[1:0]*8 +:8]<=8'h80;
                            if(slot>=0)begin seen[slot[1:0]]<=1;good[slot[1:0]]<=0;pending[slot[1:0]]<=0;stable[slot[1:0]]<=0;generation[slot[1:0]]<=generation[slot[1:0]]+1'b1;anchor_valid[slot[1:0]]<=0;end
                        end else begin
                            seen[slot[1:0]]<=1;
                            changed=selected_changed;
                            next_gen=generation[slot[1:0]]+(changed?1'b1:1'b0);
                            next_stable=(!active[slot[1:0]] || ids[slot[1:0]]!=current_track)?1:(stable[slot[1:0]]==255?255:stable[slot[1:0]]+1'b1);
                            active[slot[1:0]]<=1;ids[slot[1:0]]<=current_track;stable[slot[1:0]]<=next_stable;generation[slot[1:0]]<=next_gen;
                            anchor_valid[slot[1:0]]<=1;
                            if(changed)begin good[slot[1:0]]<=0;pending[slot[1:0]]<=0;end
                            if(next_gen==0)begin fault<=1;result_reasons[index[1:0]*8 +:8]<=8'h80;end
                            else if(!changed && good[slot[1:0]])begin
                                result_status[index[1:0]*2 +:2]<=status[slot[1:0]];detection_frame_ids[index[1:0]*32 +:32]<=detect_fid[slot[1:0]];cached_results[index[1:0]]<=detect_fid[slot[1:0]]!=result_frame_id;
                            end else if(next_stable>=3 && (changed || !pending[slot[1:0]]))begin
                                if(!reserved || queue_depth==TRACK_CAPACITY)begin overflows<=overflows+1'b1;fault<=1;result_reasons[index[1:0]*8 +:8]<=8'h80;end
                                else begin
                                    qfid[wr]<=result_frame_id;qtid[wr]<=current_track;qslot[wr]<=slot;qgen[wr]<=next_gen;qtime[wr]<=clock_count;qtemplate[wr]<=template_version;
                                    wr<=TRACK_CAPACITY==1?0:wr+1'b1;push=1;submitted<=submitted+1'b1;pending[slot[1:0]]<=1;
                                end
                            end
                        end
                        index<=index+1'b1;state<=SCAN;
                end
                EXPIRE:begin
                    if(!seen[index[1:0]])begin active[index[1:0]]<=0;good[index[1:0]]<=0;pending[index[1:0]]<=0;stable[index[1:0]]<=0;end
                    if(index==TRACK_CAPACITY-1)state<=DRAIN;else index<=index+1'b1;
                end
                DRAIN:begin
                    drain_cycles<=drain_cycles+1'b1;
                    if((queue_depth==0 && !busy && !wv) || drain_cycles>=DRAIN_LIMIT)state<=OUTPUT;
                end
                OUTPUT:if(result_ready)state<=IDLE;
                default:state<=IDLE;
            endcase
            if(INPUT_STREAM && stream_hold && !in_valid)begin
                fault<=1;stream_hold<=0;good<=0;pending<=0;result_status<=0;result_reasons<=32'h80808080;
                if(learn)template_valid<=0;
                state<=OUTPUT;
            end
            if(shared_mode && template_valid && !worker_template_valid)begin template_valid<=0;good<=0;pending<=0;result_status<=0;result_reasons<=32'h80808080;fault<=1;end
            if(!(state==CAPTURE_ACK && in_valid && learn && object_count==1 && invalid_objects==0 && frame_error==0 && config_frame_id==frame_id && !shared_mode))begin
                case({push,pop})
                    2'b10:begin queue_depth<=queue_depth+1'b1;if(queue_depth+1>queue_high_water)queue_high_water<=queue_depth+1'b1;end
                    2'b01:queue_depth<=queue_depth-1'b1;
                    default:queue_depth<=queue_depth;
                endcase
            end
            // 模板和队列不应同时占用装载口；异常冲突撤销结果，禁止沿用旧PASS。
            if(owner_conflict)begin
                fault<=1;reset_worker<=1;template_valid<=0;good<=0;pending<=0;
                result_status<=0;result_reasons<=32'h80808080;detection_frame_ids<=0;cached_results<=0;
                busy<=0;load_state<=0;queue_depth<=0;wr<=0;rd<=0;state<=OUTPUT;
            end
            // LIVE会话结束时只取消检测任务和身份缓存，标准模板继续保留。
            if(SESSION_CONTROL && session_clear===1'b1)begin
                state<=IDLE;stream_hold<=0;active<=0;good<=0;pending<=0;anchor_valid<=0;seen<=0;
                busy<=0;load_state<=0;queue_depth<=0;wr<=0;rd<=0;reset_worker<=1;reset_tracker<=1;
                result_count<=0;result_status<=0;result_track_ids<=0;detection_frame_ids<=0;cached_results<=0;
            end
        end
    end
endmodule
