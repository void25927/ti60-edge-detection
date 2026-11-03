`timescale 1ns/1ps
// 纯色底板前景分离；两拍流水，不改变原视频，参数仅在帧首更新。
module inspection_foreground #(
    parameter IMAGE_WIDTH=1920,
    parameter IMAGE_HEIGHT=1080,
    parameter ROI_LEFT=0, ROI_TOP=0,
    parameter ROI_RIGHT=IMAGE_WIDTH-1, ROI_BOTTOM=IMAGE_HEIGHT-1,
    parameter LUMA_DISTANCE=0
)(
    input wire clk, rst_n,
    input wire in_valid, in_frame_start, in_hsync, in_vsync,
    input wire [10:0] in_x, in_y, // 有效像素的源坐标，停顿时不递增
    input wire [31:0] in_frame_id,
    input wire [23:0] in_rgb,
    input wire [23:0] cfg_background,
    input wire [7:0] cfg_threshold,
    input wire cfg_ready, // 完成空台标定后才允许产生前景
    output reg out_valid, out_mask, out_frame_start,
    output reg out_hsync, out_vsync,
    output reg [10:0] out_x, out_y,
    output reg [31:0] out_frame_id,
    output reg fault_seen // 坐标越界后锁存，由系统复位清除
);
    reg active, ready_frame;
    reg [23:0] background_frame;
    reg [7:0] threshold_frame;
    reg [31:0] frame_id;
    wire [23:0] bg=in_frame_start ? cfg_background : background_frame;
    wire [7:0] threshold=in_frame_start ? cfg_threshold : threshold_frame;
    wire ready=in_frame_start ? cfg_ready : ready_frame;
    wire valid=in_valid && (active || in_frame_start);
    wire coordinate_ok=(in_x<IMAGE_WIDTH && in_y<IMAGE_HEIGHT);
    wire in_roi=(in_x>=ROI_LEFT && in_x<=ROI_RIGHT &&
                 in_y>=ROI_TOP && in_y<=ROI_BOTTOM);

    function [7:0] abs_diff;
        input [7:0] a,b;
        begin abs_diff=(a>=b) ? a-b : b-a; end
    endfunction

    reg [7:0] dr,dg,db,threshold_d;
    function [15:0] luminance;
        input [23:0] rgb;
        reg [15:0] r,g,b;
        begin
            r={8'd0,rgb[23:16]};g={8'd0,rgb[15:8]};b={8'd0,rgb[7:0]};
            // 保留8位小数，不先截断，避免边界舍入改变32级阈值。
            luminance=(r<<6)+(r<<3)+(r<<2)+r+(g<<7)+(g<<4)+(g<<2)+(g<<1)+(b<<4)+(b<<3)+(b<<2)+b;
        end
    endfunction
    wire [15:0] input_luma=luminance(in_rgb),background_luma=luminance(bg);
    reg [15:0] luma_difference;
    reg valid_d,roi_d,ready_d,start_d,hs_d,vs_d;
    reg [10:0] x_d,y_d;
    reg [31:0] id_d;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            active<=0;ready_frame<=0;background_frame<=0;
            threshold_frame<=0;frame_id<=0;fault_seen<=0;
            dr<=0;dg<=0;db<=0;threshold_d<=0;luma_difference<=0;
            valid_d<=0;roi_d<=0;ready_d<=0;start_d<=0;hs_d<=0;vs_d<=0;
            x_d<=0;y_d<=0;id_d<=0;
            out_valid<=0;out_mask<=0;out_frame_start<=0;
            out_hsync<=0;out_vsync<=0;out_x<=0;out_y<=0;out_frame_id<=0;
        end else begin
            if(in_frame_start) begin
                active<=1;ready_frame<=cfg_ready;
                background_frame<=cfg_background;threshold_frame<=cfg_threshold;
                frame_id<=in_frame_id;
            end
            if(valid && !coordinate_ok) fault_seen<=1;
            // 第一级求三个通道绝对差，坐标及控制信号同拍寄存。
            dr<=abs_diff(in_rgb[23:16],bg[23:16]);
            dg<=abs_diff(in_rgb[15:8],bg[15:8]);
            db<=abs_diff(in_rgb[7:0],bg[7:0]);
            luma_difference<=input_luma>background_luma?input_luma-background_luma:background_luma-input_luma;
            threshold_d<=threshold;
            valid_d<=valid && coordinate_ok;roi_d<=in_roi;ready_d<=ready;
            start_d<=in_frame_start;hs_d<=in_hsync;vs_d<=in_vsync;
            x_d<=in_x;y_d<=in_y;
            id_d<=in_frame_start ? in_frame_id : frame_id;
            // 第二级输出二值掩膜，等于阈值的像素仍视为背景。
            out_valid<=valid_d;
            out_mask<=valid_d && roi_d && ready_d &&
                      (LUMA_DISTANCE ? luma_difference>{threshold_d,8'd0} :
                       ((dr>threshold_d)||(dg>threshold_d)||(db>threshold_d)));
            out_frame_start<=start_d;out_hsync<=hs_d;out_vsync<=vs_d;
            out_x<=x_d;out_y<=y_d;out_frame_id<=id_d;
        end
    end
endmodule
