`timescale 1ns/1ps
// 复用全幅Canny的正式接口候选；不改视频数据，结果缓存按完整帧号严格匹配。
module inspection_edge_formal_path #(parameter IMAGE_WIDTH=1920,IMAGE_HEIGHT=1080,CENTER_SELECT=1,PAIRED_DISPLAY=0,TEMPORAL_VOTE=0)(
    input wire clk,rst_n,
    input wire source_valid,source_vsync,
    input wire [31:0] source_frame_id,source_config,
    input wire source_frame_valid,live_mode,
    input wire edge_valid,edge_window_valid,edge_vsync,edge_pixel,
    input wire learn_request,start_request,
    input wire display_de,display_vsync,
    output wire background_ready,template_valid,learn_pending,detect_enabled,
    output wire fault,result_matched,
    output wire [31:0] selected_frame_id,
    output wire [2:0] selected_count,
    output wire [1:0] selected_status,
    output wire [63:0] selected_track_ids,
    output wire [127:0] selected_detection_ids,
    output wire [43:0] selected_centers_x,selected_centers_y,
    output wire [31:0] accepted_frames,busy_frames,processing_cycles,manager_cycles,submitted,completed,
    output wire [2:0] queue_depth,queue_high_water,
    output reg [7:0] diagnostic,
    input wire [31:0] visible_frame_id,
    input wire visible_frame_valid,learning_allowed,
    input wire external_learn_start,
    output wire external_learn_ready,
    input wire [1837:0] external_descriptor,
    input wire [31:0] external_frame_id,external_config,
    input wire external_bad,
    output wire external_done,external_failed,
    output wire feature_valid,feature_bad,
    output wire [1837:0] feature_descriptor,
    output wire [31:0] feature_frame_id,feature_config,
    output wire completed_result_valid,
    output wire [31:0] completed_result_id,
    output wire [1:0] completed_result_status,
    output wire [15:0] completed_result_track,
    output wire invalidate_display
);
    wire ov,os,od,oc,oa,oe,ou,ingress_fault;
    wire [10:0] ox,oy;wire [31:0] ofid,ocfg;wire [7:0] ferr;
    wire rv,raw_template_valid,learned,rejected,invalidate,learn_pulse,engine_fault;
    wire [31:0] rid,learnid,template_frame,template_config;
    wire [7:0] engine_fault_code;
    wire [15:0] tid;wire [1:0] status;wire [7:0] reasons;wire [10:0] cx,cy;wire [2:0] count;
    reg live_d,config_invalid,feed_frame,have_last,last_command_learn;
    reg [31:0] last_frame,last_config;
    reg [7:0] last_learn_error;
    function [7:0] learn_error_code;
        input [7:0] why;
        begin
            if(why[6])learn_error_code=8'h37;else if(why[5])learn_error_code=8'h36;
            else if(why[3])learn_error_code=8'h38;else if(why[4])learn_error_code=8'h39;
            else if(why[2])learn_error_code=8'h34;else if(why[1])learn_error_code=8'h32;
            else if(why[0])learn_error_code=8'h31;else if(why[7])learn_error_code=8'h35;
            else learn_error_code=8'h33;
        end
    endfunction
    wire session_clear=live_d!=live_mode;
    wire config_mismatch=raw_template_valid && source_config!=template_config;
    assign background_ready=1'b1; // 边缘录入不再依赖背景校准。
    assign template_valid=raw_template_valid && !config_invalid && !config_mismatch;
    wire fresh=os && ou && (!have_last || ofid!=last_frame || ocfg!=last_config);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin live_d<=0;config_invalid<=0;feed_frame<=0;have_last<=0;last_command_learn<=0;last_frame<=0;last_config<=0;last_learn_error<=0;end
        else begin
            live_d<=live_mode;
            if(learn_request)last_command_learn<=1;else if(start_request)last_command_learn<=0;
            if(rv && rid==learnid && last_command_learn && !raw_template_valid)last_learn_error<=learn_error_code(reasons);
            if(learn_request || learned)last_learn_error<=0;
            if(config_mismatch)config_invalid<=1;
            if(PAIRED_DISPLAY && learn_request)config_invalid<=1;
            if(learned)config_invalid<=0;
            if(os)begin feed_frame<=fresh;if(fresh)begin have_last<=1;last_frame<=ofid;last_config<=ocfg;end end
            if(session_clear)begin have_last<=0;feed_frame<=0;end
        end
    end
    inspection_edge_stream #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT)) ingress(.clk(clk),.rst_n(rst_n),.source_valid(source_valid),.source_vsync(source_vsync),.source_frame_id(source_frame_id),.source_frame_valid(source_frame_valid),.source_live(live_mode),.source_config(source_config),
        .edge_valid(edge_valid),.edge_window_valid(edge_window_valid),.edge_vsync(edge_vsync),.edge_pixel(edge_pixel),.live_now(live_mode),
        .out_valid(ov),.out_start(os),.out_done(od),.out_commit(oc),.out_abort(oa),.out_edge(oe),.out_usable(ou),.out_x(ox),.out_y(oy),.out_frame_id(ofid),.out_config(ocfg),
        .frame_error(ferr),.fault(ingress_fault),.metadata_high_water(),.complete_frames());
    wire engine_input=ov && ou && (os?fresh:feed_frame);
    inspection_edge_system #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),.CENTER_SELECT(CENTER_SELECT),.EXTERNAL_LEARN(PAIRED_DISPLAY),.TRACK_FAILED(TEMPORAL_VOTE)) engine(.clk(clk),.rst_n(rst_n),.in_valid(engine_input),.in_start(os && fresh),.in_edge(oe),.in_commit(oc),.in_abort(oa),.in_x(ox),.in_y(oy),.in_frame_id(ofid),.in_config(ocfg),.in_error(ferr),
        .live_mode(live_mode),.learn_pending(PAIRED_DISPLAY?1'b0:learn_pending),.detect_enabled(detect_enabled && template_valid),.learn_frame_id(learnid),.result_valid(rv),.result_ready(1'b1),.result_frame_id(rid),.result_track_id(tid),.result_status(status),
        .center_x(cx),.center_y(cy),.result_reasons(reasons),.result_count(count),.template_valid(raw_template_valid),.template_learned(learned),.template_source_frame(template_frame),.template_config(template_config),.fault(engine_fault),.fault_code(engine_fault_code),
        .post_cycles(processing_cycles),.max_post_cycles(),.compare_cycles(manager_cycles),.accepted_frames(accepted_frames),.completed_frames(completed),.busy_frames(busy_frames),.queue_depth(queue_depth),.queue_high(queue_high_water),
        .external_learn_start(external_learn_start),.external_learn_ready(external_learn_ready),.external_descriptor(external_descriptor),.external_frame_id(external_frame_id),.external_config(external_config),.external_bad(external_bad),
        .external_done(external_done),.external_failed(external_failed),.feature_valid(feature_valid),.feature_bad(feature_bad),.feature_descriptor(feature_descriptor),.feature_frame_id(feature_frame_id),.feature_config(feature_config));
    assign completed_result_valid=rv;
    assign completed_result_id=rid;
    wire [1:0] object_verdict;
    generate if(TEMPORAL_VOTE)begin: temporal
        inspection_object_verdict #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),.EXIT_MARGIN(IMAGE_WIDTH/60>0?IMAGE_WIDTH/60:1)) vote(
            .clk(clk),.rst_n(rst_n),.clear(invalidate || session_clear || config_invalid || config_mismatch || learned || learn_request),
            .enabled(detect_enabled && template_valid && live_mode),.observation_valid(rv),
            .identity_valid(count==1 && !engine_fault && !ingress_fault),
            .frame_id(rid),.track_id(tid),.center_x(cx),.center_y(cy),.raw_status(status),.verdict(object_verdict));
    end else begin: instant
        assign object_verdict=status;
    end endgenerate
    assign completed_result_status=detect_enabled && template_valid?object_verdict:2'd0;
    assign completed_result_track=tid;
    reg config_mismatch_d;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)config_mismatch_d<=0;else config_mismatch_d<=config_mismatch;
    end
    assign invalidate_display=invalidate || session_clear || (config_mismatch && !config_mismatch_d);
    assign submitted=accepted_frames; // 无后台排队；统计提交到边缘处理的有效源帧。
    inspection_user_control #(.SESSION_CONTROL(1)) control(.clk(clk),.rst_n(rst_n),.learn_request(learn_request && live_mode),.start_request(start_request && live_mode),.request_frame_id(PAIRED_DISPLAY?visible_frame_id:source_frame_id),.request_frame_valid(PAIRED_DISPLAY?(visible_frame_valid && learning_allowed):source_frame_valid),.learn_frame_id(learnid),
        .observation_valid(PAIRED_DISPLAY?external_done:rv),.observation_frame_id(PAIRED_DISPLAY?external_frame_id:rid),.object_count(count),.frame_error(reasons),.center_x(cx),.center_y(cy),.area(22'd0),
        .template_valid(template_valid),.template_learned(learned),.background_ready(1'b1),.learn_pulse(learn_pulse),.learn_pending(learn_pending),.detect_enabled(detect_enabled),.command_rejected(rejected),.invalidate_results(invalidate),.session_clear(session_clear));
    localparam PW=83;
    wire [PW-1:0] selected;
    wire history_matched;
    reg display_active,display_de_d;
    wire select_frame=display_de && !display_de_d && !display_active;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin display_active<=0;display_de_d<=0;end
        else begin display_de_d<=display_de;if(!display_vsync)display_active<=0;else if(select_frame)display_active<=1;end
    end
    wire [1:0] saved_status=(detect_enabled && template_valid)?object_verdict:2'd0;
    inspection_result_history #(.PAYLOAD_WIDTH(PW)) history(.clk(clk),.rst_n(rst_n),.invalidate(invalidate || session_clear || !live_mode || config_invalid || config_mismatch),
        .commit_valid(rv && live_mode),.commit_frame_id(rid),.commit_payload({count,saved_status,tid,rid,cx,cy,reasons}),
        .select_frame(select_frame),.display_frame_id(source_frame_id),.display_valid(source_frame_valid),.matched(history_matched),.selected_frame_id(selected_frame_id),.selected_payload(selected));
    wire [2:0] saved_count;wire [1:0] saved_result;wire [15:0] saved_track;wire [31:0] saved_detection;wire [10:0] saved_x,saved_y;wire [7:0] saved_reason;
    assign {saved_count,saved_result,saved_track,saved_detection,saved_x,saved_y,saved_reason}=selected;
    assign result_matched=history_matched && selected_frame_id==source_frame_id && source_frame_valid && live_mode && template_valid;
    assign selected_count=result_matched?saved_count:3'd0;
    assign selected_status=result_matched && detect_enabled?saved_result:2'd0;
    assign selected_track_ids=result_matched?{48'd0,saved_track}:64'd0;
    assign selected_detection_ids=result_matched?{96'd0,saved_detection}:128'd0;
    assign selected_centers_x=result_matched?{33'd0,saved_x}:44'd0;
    assign selected_centers_y=result_matched?{33'd0,saved_y}:44'd0;
    assign fault=ingress_fault || engine_fault || rejected;
    always @(*)begin
        diagnostic=0;
        if(ingress_fault)diagnostic=8'hf1;
        else if(engine_fault)diagnostic=engine_fault_code!=0?engine_fault_code:8'hf2;
        else if(rejected)begin
            if(last_learn_error!=0 && !template_valid)diagnostic=last_learn_error;
            else if(last_command_learn)diagnostic=learn_error_code(reasons);
            else diagnostic=8'h33;
        end else if(config_invalid || config_mismatch)diagnostic=8'h40;
    end
endmodule
