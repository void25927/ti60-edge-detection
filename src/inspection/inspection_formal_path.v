`timescale 1ns/1ps
// 正式RGB旁路与帧结果桥；不改变摄像头、Canny、DDR、HDMI数据路径。
module inspection_formal_path(
    input wire clk,rst_n,
    input wire [23:0] rgb,
    input wire valid,vsync,
    input wire [31:0] source_frame_id,
    input wire source_frame_valid,live_mode,
    input wire learn_request,start_request,
    input wire display_de,display_vsync,
    output wire background_ready,template_valid,learn_pending,detect_enabled,
    output wire fault,
    output wire result_matched,
    output wire [31:0] selected_frame_id,
    output wire [2:0] selected_count,
    output reg [1:0] selected_status,
    output wire [63:0] selected_track_ids,
    output wire [127:0] selected_detection_ids,
    output wire [43:0] selected_centers_x,selected_centers_y,
    output wire [31:0] accepted_frames,busy_frames,
    output wire [31:0] processing_cycles,manager_cycles,submitted,completed,
    output wire [2:0] queue_depth,queue_high_water
);
    wire av,astart,alearn,ready,rv,learned,afault,efault,calibrating;
    wire [10:0] ax,ay;wire [23:0] argb,bg;wire [7:0] threshold;
    wire [31:0] aid,repeated,pixels;
    wire retime_valid,retime_vsync,retime_frame_valid,retime_live,retime_fault;
    reg live_previous;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)live_previous<=0;else live_previous<=live_mode;
    end
    wire session_clear=live_previous!=live_mode;
    wire [23:0] retime_rgb;wire [31:0] retime_id;wire [12:0] fifo_high,fifo_low;
    inspection_video_retime retime(.clk(clk),.rst_n(rst_n),.in_valid(valid),.in_vsync(vsync),.in_rgb(rgb),
        .in_frame_id(source_frame_id),.in_frame_valid(source_frame_valid),.in_live(live_mode),.display_de(display_de),.display_vsync(display_vsync),
        .out_valid(retime_valid),.out_vsync(retime_vsync),.out_rgb(retime_rgb),.out_frame_id(retime_id),.out_frame_valid(retime_frame_valid),.out_live(retime_live),
        .fault(retime_fault),.high_water(fifo_high),.low_water(fifo_low));
    wire learn_pulse,rejected,invalidate;wire [31:0] learn_frame_id;
    wire [31:0] rid,reasons;wire [2:0] n;wire [63:0] tids;wire [7:0] status,ferr;wire [127:0] dids;
    wire [3:0] cached;wire [43:0] cx,cy,x0,x1,y0,y1;wire [87:0] areas;wire [67:0] angles;
    // 前景亮度差80用于受控明暗底板，不是Canny阈值或尺寸/缺陷容差。
    inspection_rgb_adapter #(.FOREGROUND_THRESHOLD(80),.SESSION_CONTROL(1)) adapter(.clk(clk),.rst_n(rst_n),.in_valid(retime_valid && live_mode),.in_vsync(retime_vsync),.in_rgb(retime_rgb),.session_clear(session_clear),
        .source_frame_id(retime_id),.source_frame_valid(retime_frame_valid),.live_mode(retime_live),.engine_ready(ready),
        .calibrate_request(1'b0),.learn_request(1'b0),.out_valid(av),.out_start(astart),.out_learn(alearn),.out_x(ax),.out_y(ay),.out_rgb(argb),.out_frame_id(aid),
        .background(bg),.background_ready(background_ready),.calibrating(calibrating),.fault(afault),.accepted_frames(accepted_frames),.repeated_frames(repeated),.busy_frames(busy_frames),.pixel_count(pixels),.threshold(threshold));
    // RGB仍原样旁路；仅检测分支采用亮度差，避免单个Bayer通道放大轮廓锯齿。
    inspection_axial_system #(.LUMA_DISTANCE(1),.SINGLE_TARGET(1),.SINGLE_FRAME_LEARN(1)) engine(.clk(clk),.rst_n(rst_n),.in_valid(av && live_mode),.in_frame_start(astart && live_mode),.in_x(ax),.in_y(ay),.in_frame_id(aid),.in_config_frame_id(aid),.in_rgb(argb),.session_clear(session_clear),
        .learn_command_valid(learn_pending),.learn_command_frame(learn_frame_id),
        .cfg_background(bg),.cfg_threshold(threshold),.cfg_ready(background_ready),.learn(alearn),.backend_pause(!live_mode),
        .video_valid(),.video_rgb(),.video_x(),.video_y(),.video_frame_id(),
        .ready_for_frame(ready),.result_valid(rv),.result_ready(1'b1),.result_frame_id(rid),.result_count(n),.result_track_ids(tids),.result_status(status),.detection_frame_ids(dids),
        .cached_results(cached),.result_reasons(reasons),.result_centers_x(cx),.result_centers_y(cy),.result_boxes_x0(x0),.result_boxes_x1(x1),.result_boxes_y0(y0),.result_boxes_y1(y1),
        .result_areas(areas),.result_angles_q8(angles),.template_valid(template_valid),.template_learned(learned),.fault(efault),.frame_error(ferr),
        .processing_cycles(processing_cycles),.post_cycles(),.profile_cycles(),.ram_accesses(),.max_ram_wait(),
        .manager_cycles(manager_cycles),.submitted(submitted),.completed(completed),.stale_results(),.overflows(),.timeouts(),.max_job_cycles(),.max_queue_wait(),.queue_depth(queue_depth),.queue_high_water(queue_high_water));
    inspection_user_control #(.SESSION_CONTROL(1)) control(.clk(clk),.rst_n(rst_n),.learn_request(learn_request && live_mode),.start_request(start_request && live_mode),.request_frame_id(source_frame_id),.session_clear(session_clear),
        .request_frame_valid(source_frame_valid),.learn_frame_id(learn_frame_id),
        .observation_valid(rv && live_mode),.observation_frame_id(rid),.object_count(n),.frame_error(ferr),.center_x(cx[10:0]),.center_y(cy[10:0]),.area(areas[21:0]),
        .template_valid(template_valid),.template_learned(learned),.background_ready(background_ready),.learn_pulse(learn_pulse),.learn_pending(learn_pending),
        .detect_enabled(detect_enabled),.command_rejected(rejected),.invalidate_results(invalidate));
    // 错误帧和未启动检测的帧只写UNKNOWN；完整ID与定位/检测来源一同保存。
    localparam PW=3+8+64+128+44*6+88+68+32;
    wire [PW-1:0] selected;
    wire [7:0] saved_status=(ferr!=0 || !detect_enabled)?8'd0:status;
    reg display_active,display_de_d;
    wire select_frame=display_de && !display_de_d && !display_active;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin display_active<=0;display_de_d<=0;end
        else begin
            display_de_d<=display_de;
            if(!display_vsync)display_active<=0;
            else if(select_frame)display_active<=1;
        end
    end
    wire [7:0] selected_statuses;wire [43:0] unused_x0,unused_x1,unused_y0,unused_y1;wire [87:0] unused_areas;wire [67:0] unused_angles;wire [31:0] unused_reasons;
    assign {selected_count,selected_statuses,selected_track_ids,selected_detection_ids,selected_centers_x,selected_centers_y,
        unused_x0,unused_x1,unused_y0,unused_y1,unused_areas,unused_angles,unused_reasons}=selected;
    wire history_matched;
    assign result_matched=history_matched && live_mode;
    inspection_result_history #(.PAYLOAD_WIDTH(PW)) history(.clk(clk),.rst_n(rst_n),.invalidate(invalidate || session_clear),
        .commit_valid(rv && live_mode && !session_clear),.commit_frame_id(rid),.commit_payload({n,saved_status,tids,dids,cx,cy,x0,x1,y0,y1,areas,angles,reasons}),
        .select_frame(select_frame),.display_frame_id(source_frame_id),.display_valid(source_frame_valid),
        .matched(history_matched),.selected_frame_id(selected_frame_id),.selected_payload(selected));
    integer k;
    always @(*)begin
        selected_status=0;
        if(result_matched && selected_count>0 && detect_enabled)begin
            selected_status=1;
            for(k=0;k<4;k=k+1)if(k<selected_count)begin
                if(selected_statuses[k*2+:2]==0)selected_status=0;
                else if(selected_statuses[k*2+:2]==2 && selected_status!=0)selected_status=2;
            end
        end
    end
    assign fault=afault || efault || rejected || retime_fault;
endmodule
