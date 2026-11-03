`timescale 1ns/1ps
// 第六菜单：长按只请求当前指定帧；短按切换校对启用/关闭，不再等待多帧稳定。
module inspection_user_control #(parameter SESSION_CONTROL=0)(
    input wire clk,rst_n,learn_request,start_request,
    input wire [31:0] request_frame_id,
    input wire observation_valid,
    input wire [31:0] observation_frame_id,
    input wire [2:0] object_count,
    input wire [7:0] frame_error,
    input wire [10:0] center_x,center_y,
    input wire [21:0] area,
    input wire template_valid,template_learned,background_ready,
    output reg learn_pulse,learn_pending,detect_enabled,command_rejected,
    output reg invalidate_results,
    input wire session_clear,
    input wire request_frame_valid,
    output reg [31:0] learn_frame_id
);
    // 几何输入保留接口兼容；录入安全性由该帧管理器的唯一目标/错误检查负责。
    // 不存历史几何，不进行5帧投票，也不向后续帧转移录入请求。
    reg learn_d,start_d;
    wire learn_event=learn_request && !learn_d;
    wire start_event=start_request && !start_d;
    wire [31:0] observation_age=observation_frame_id-learn_frame_id;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            learn_d<=0;start_d<=0;learn_frame_id<=0;
            learn_pulse<=0;learn_pending<=0;detect_enabled<=0;command_rejected<=0;invalidate_results<=0;
        end else begin
            learn_d<=learn_request;start_d<=start_request;
            learn_pulse<=0;invalidate_results<=0;
            if(learn_pending && template_learned)begin
                learn_pending<=0;command_rejected<=0;invalidate_results<=1;
            end else if(learn_pending && observation_valid && !observation_age[31])begin
                // 指定帧未成功录入或已错过：拒绝本次请求，不能偷换成下一帧。
                learn_pending<=0;command_rejected<=1;invalidate_results<=1;
            end
            if(learn_event)begin
                detect_enabled<=0;invalidate_results<=1;
                if(background_ready && request_frame_valid && !learn_pending &&
                   !(observation_valid && observation_frame_id==request_frame_id))begin
                    learn_frame_id<=request_frame_id;learn_pending<=1;learn_pulse<=1;command_rejected<=0;
                end else command_rejected<=1;
            end else if(start_event)begin
                invalidate_results<=1;
                if(detect_enabled)begin detect_enabled<=0;command_rejected<=0;end
                else if(template_valid && !learn_pending && background_ready)begin detect_enabled<=1;command_rejected<=0;end
                else begin detect_enabled<=0;command_rejected<=1;end
            end
            if(SESSION_CONTROL && session_clear===1'b1)begin
                learn_pulse<=0;learn_pending<=0;invalidate_results<=1;
            end
        end
    end
endmodule
