`timescale 1ns/1ps
// 独立器件检测通路。视频旁路不接受检测背压，结果在固定帧内时刻提交。
module inspection_axial_system #(
    parameter FRAME_OUTPUT_CYCLE=2465000,LUMA_DISTANCE=0,SINGLE_TARGET=0,SINGLE_FRAME_LEARN=0
)(
    input wire clk,rst_n,in_valid,in_frame_start,
    input wire [10:0] in_x,in_y,
    input wire [31:0] in_frame_id,in_config_frame_id,
    input wire [23:0] in_rgb,cfg_background,
    input wire [7:0] cfg_threshold,
    input wire cfg_ready,learn,backend_pause,
    output reg video_valid,
    output reg [23:0] video_rgb,
    output reg [10:0] video_x,video_y,
    output reg [31:0] video_frame_id,
    output wire ready_for_frame,result_valid,
    input wire result_ready,
    output wire [31:0] result_frame_id,
    output wire [2:0] result_count,
    output wire [63:0] result_track_ids,
    output wire [7:0] result_status,
    output wire [127:0] detection_frame_ids,
    output wire [3:0] cached_results,
    output wire [31:0] result_reasons,
    output wire [43:0] result_centers_x,result_centers_y,result_boxes_x0,result_boxes_x1,result_boxes_y0,result_boxes_y1,
    output wire [87:0] result_areas,
    output wire [67:0] result_angles_q8,
    output wire template_valid,fault,template_learned,
    output wire [7:0] frame_error,
    output wire [31:0] processing_cycles,post_cycles,profile_cycles,ram_accesses,max_ram_wait,
    output wire [31:0] manager_cycles,submitted,completed,stale_results,overflows,timeouts,max_job_cycles,max_queue_wait,
    output wire [2:0] queue_depth,queue_high_water,
    input wire session_clear,
    input wire learn_command_valid,
    input wire [31:0] learn_command_frame
);
    wire fv,fr,ffault,mv,learn_frame;
    wire [31:0] fid,frame_cycles;
    wire [2:0] n;wire [7351:0] descriptors;
    wire [43:0] cx,cy,x0,x1,y0,y1;wire [87:0] areas;wire [67:0] angles;wire [3:0] bad;
    reg [31:0] config_frame,frame_counter;
    reg pause_frame;
    wire descriptor_read,descriptor_valid,descriptor_error;
    // 指定帧描述符仍驻留前端RAM；帧尾只标记该帧录入，不重新拍摄后续帧。
    // 空台、多候选或无效轮廓只拒绝本次录入，不破坏已有模板或锁死用户操作。
    wire manager_learn=SINGLE_FRAME_LEARN ? (learn_command_valid && fid==learn_command_frame && n==1 && bad==0 && frame_error==0) : learn_frame;
    wire [31:0] descriptor_read_frame,descriptor_frame;
    wire [1:0] descriptor_read_object,descriptor_object;
    wire [4:0] descriptor_read_word,descriptor_word;
    wire [63:0] descriptor_data;
    inspection_axial_frontend #(.OUTPUT_CYCLE(2450000),.LUMA_DISTANCE(LUMA_DISTANCE),.STREAM_DESCRIPTORS(1),.SINGLE_TARGET(SINGLE_TARGET)) frontend(.clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_frame_start(in_frame_start),.in_x(in_x),.in_y(in_y),.in_frame_id(in_frame_id),.in_rgb(in_rgb),.session_clear(session_clear),
        .cfg_background(cfg_background),.cfg_threshold(cfg_threshold),.cfg_ready(cfg_ready),.in_learn(learn),.ready_for_frame(ready_for_frame),.result_valid(fv),.result_ready(fr),
        .result_frame_id(fid),.object_count(n),.descriptors(descriptors),.centers_x(cx),.centers_y(cy),.boxes_x0(x0),.boxes_x1(x1),.boxes_y0(y0),.boxes_y1(y1),.areas(areas),.angles_q8(angles),
        .descriptor_read(descriptor_read),.descriptor_read_frame(descriptor_read_frame),.descriptor_read_object(descriptor_read_object),.descriptor_read_word(descriptor_read_word),
        .descriptor_valid(descriptor_valid),.descriptor_error(descriptor_error),.descriptor_data(descriptor_data),.descriptor_frame(descriptor_frame),.descriptor_object(descriptor_object),.descriptor_word(descriptor_word),
        .invalid_objects(bad),.result_learn(learn_frame),.frame_error(frame_error),.fault(ffault),.frame_cycles(frame_cycles),.processing_cycles(processing_cycles),.post_cycles(post_cycles),.profile_cycles(profile_cycles),.ram_accesses(ram_accesses),.max_ram_wait(max_ram_wait));
    wire mfault;
    inspection_axial_manager #(.INPUT_STREAM(1),.RAM_WORKER(1),.SHARED_TEMPLATE(1),.TRACK_CAPACITY(SINGLE_TARGET?1:4),.SESSION_CONTROL(SINGLE_TARGET)) manager(.clk(clk),.rst_n(rst_n),.in_valid(fv),.in_ready(fr),.frame_id(fid),.config_frame_id(config_frame),.object_count(n),.descriptors(descriptors),.session_clear(session_clear),
        .source_read(descriptor_read),.source_read_frame(descriptor_read_frame),.source_read_object(descriptor_read_object),.source_read_word(descriptor_read_word),
        .source_valid(descriptor_valid),.source_error(descriptor_error),.source_data(descriptor_data),.source_frame(descriptor_frame),.source_object(descriptor_object),.source_word(descriptor_word),
        .centers_x(cx),.centers_y(cy),.boxes_x0(x0),.boxes_x1(x1),.boxes_y0(y0),.boxes_y1(y1),.areas(areas),.angles_q8(angles),.invalid_objects(bad),.frame_error(frame_error),.learn(manager_learn),.backend_pause(pause_frame),
        .result_valid(mv),.result_ready(result_ready && frame_counter>=FRAME_OUTPUT_CYCLE),.result_frame_id(result_frame_id),.result_count(result_count),.result_track_ids(result_track_ids),.result_status(result_status),
        .detection_frame_ids(detection_frame_ids),.cached_results(cached_results),.result_reasons(result_reasons),.template_valid(template_valid),.learned(template_learned),.fault(mfault),
        .submitted(submitted),.completed(completed),.stale_results(stale_results),.overflows(overflows),.timeouts(timeouts),.frame_cycles(manager_cycles),.max_job_cycles(max_job_cycles),.max_queue_wait(max_queue_wait),.queue_depth(queue_depth),.queue_high_water(queue_high_water));
    assign result_valid=mv && frame_counter>=FRAME_OUTPUT_CYCLE;
    // 与result_valid同拍采样；冻结/回放接口需按result_frame_id另存这些定位结果。
    assign result_centers_x=cx;assign result_centers_y=cy;
    assign result_boxes_x0=x0;assign result_boxes_x1=x1;assign result_boxes_y0=y0;assign result_boxes_y1=y1;
    assign result_areas=areas;assign result_angles_q8=angles;
    assign fault=ffault || mfault;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin video_valid<=0;video_rgb<=0;video_x<=0;video_y<=0;video_frame_id<=0;config_frame<=0;frame_counter<=0;pause_frame<=0;end
        else begin
            video_valid<=in_valid;video_rgb<=in_valid?in_rgb:24'd0;video_x<=in_x;video_y<=in_y;video_frame_id<=in_frame_id;
            if(in_frame_start)begin config_frame<=in_config_frame_id;pause_frame<=backend_pause;frame_counter<=0;end
            else if(frame_counter<32'hffffffff)frame_counter<=frame_counter+1'b1;
        end
    end
endmodule
