`timescale 1ns / 1ps

// 图像边缘检测总流水线。
// EDGE_MODE=0为Sobel；EDGE_MODE=1为流式局部连接方案，不是完整帧连接。
module edge_video_pipeline #(
    parameter integer IMAGE_WIDTH = 960,
    parameter integer ADDR_WIDTH = 10,
    parameter [10:0] THRESHOLD = 11'd128,
    parameter integer EDGE_MODE = 1,
    parameter VSYNC_ACTIVE_LEVEL = 1'b0,
    parameter RUNTIME_MEDIAN = 0,
    parameter RUNTIME_CANNY = 0,
    parameter REPAIR_SHORT_GAP = 1,
    parameter MORPH_MODE = 0, MORPH_KERNEL_SHAPE = 1
)(
    input  wire clk,
    input  wire rst_n,
    input  wire in_median_enable,
    input  wire in_canny_enable,
    input  wire [7:0] in_red,
    input  wire [7:0] in_green,
    input  wire [7:0] in_blue,
    input  wire in_valid,
    input  wire in_hsync,
    input  wire in_vsync,
    input  wire [10:0] in_high_threshold,
    input  wire [10:0] in_low_threshold,
    output wire [7:0] out_red,
    output wire [7:0] out_green,
    output wire [7:0] out_blue,
    output wire [7:0] out_gray,
    output wire [7:0] out_edge,
    output wire out_valid,
    output wire out_window_valid,
    output wire out_hsync,
    output wire out_vsync
);
    wire [7:0] gray;
    wire gray_valid, gray_hsync, gray_vsync;
    reg [23:0] input_rgb_delay;

    rgb888_to_gray u_gray (
        .clk(clk),.rst_n(rst_n),
        .in_red(in_red),.in_green(in_green),.in_blue(in_blue),
        .in_valid(in_valid),.in_hsync(in_hsync),.in_vsync(in_vsync),
        .out_gray(gray),.out_valid(gray_valid),
        .out_hsync(gray_hsync),.out_vsync(gray_vsync)
    );

    // RGB与灰度转换结果对齐，随后随各级3×3窗口中心像素传递。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            input_rgb_delay <= 24'd0;
        else if (in_valid)
            input_rgb_delay <= {in_red,in_green,in_blue};
        else
            input_rgb_delay <= 24'd0;
    end

    generate
        if (EDGE_MODE == 0) begin : g_basic_sobel
            wire [31:0] p11,p12,p13,p21,p22,p23,p31,p32,p33;
            wire wv,ww,wh,wf;
            wire signed [10:0] gx,gy;
            wire [10:0] gradient;
            wire [1:0] direction_unused;
            wire sv,sw,sh,sf;
            wire [7:0] edge_pixel;
            wire ev,ew,eh,ef;
            reg [7:0] gray_delay [0:3];
            reg [23:0] rgb_delay [0:3];
            integer i;

            gray_3x3_window #(
                .PIXEL_WIDTH(32),.IMAGE_WIDTH(IMAGE_WIDTH),.ADDR_WIDTH(ADDR_WIDTH),
                .VSYNC_ACTIVE_LEVEL(VSYNC_ACTIVE_LEVEL)
            ) u_window (
                .clk(clk),.rst_n(rst_n),.in_pixel({input_rgb_delay,gray}),
                .in_valid(gray_valid),.in_hsync(gray_hsync),.in_vsync(gray_vsync),
                .out_p11(p11),.out_p12(p12),.out_p13(p13),
                .out_p21(p21),.out_p22(p22),.out_p23(p23),
                .out_p31(p31),.out_p32(p32),.out_p33(p33),
                .out_valid(wv),.out_window_valid(ww),.out_hsync(wh),.out_vsync(wf)
            );

            sobel_3x3 u_sobel (
                .clk(clk),.rst_n(rst_n),
                .in_p11(p11[7:0]),.in_p12(p12[7:0]),.in_p13(p13[7:0]),
                .in_p21(p21[7:0]),.in_p22(p22[7:0]),.in_p23(p23[7:0]),
                .in_p31(p31[7:0]),.in_p32(p32[7:0]),.in_p33(p33[7:0]),
                .in_valid(wv),.in_window_valid(ww),.in_hsync(wh),.in_vsync(wf),
                .out_gx(gx),.out_gy(gy),.out_gradient(gradient),
                .out_direction(direction_unused),.out_valid(sv),
                .out_window_valid(sw),.out_hsync(sh),.out_vsync(sf)
            );

            gradient_threshold #(
                .THRESHOLD(THRESHOLD),.USE_RUNTIME_THRESHOLD(1)
            ) u_threshold (
                .clk(clk),.rst_n(rst_n),.in_gradient(gradient),
                .in_threshold(in_high_threshold),.in_valid(sv),.in_window_valid(sw),
                .in_hsync(sh),.in_vsync(sf),.out_pixel(edge_pixel),
                .out_valid(ev),.out_window_valid(ew),.out_hsync(eh),.out_vsync(ef)
            );

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (i=0;i<4;i=i+1) begin
                        gray_delay[i] <= 0;
                        rgb_delay[i] <= 0;
                    end
                end else begin
                    gray_delay[0] <= (wv && ww) ? p22[7:0] : 0;
                    rgb_delay[0] <= (wv && ww) ? p22[31:8] : 0;
                    for (i=1;i<4;i=i+1) begin
                        gray_delay[i] <= gray_delay[i-1];
                        rgb_delay[i] <= rgb_delay[i-1];
                    end
                end
            end

            assign out_red = ev ? rgb_delay[3][23:16] : 0;
            assign out_green = ev ? rgb_delay[3][15:8] : 0;
            assign out_blue = ev ? rgb_delay[3][7:0] : 0;
            assign out_gray = ev ? gray_delay[3] : 0;
            assign out_edge = ev ? edge_pixel : 0;
            assign out_valid = ev;
            assign out_window_valid = ew;
            assign out_hsync = eh;
            assign out_vsync = ef;
        end else begin : g_canny
            canny_edge_pipeline #(
                .IMAGE_WIDTH(IMAGE_WIDTH),.ADDR_WIDTH(ADDR_WIDTH),
                .RUNTIME_MEDIAN(RUNTIME_MEDIAN),.REPAIR_SHORT_GAP(REPAIR_SHORT_GAP),
                .RUNTIME_CANNY(RUNTIME_CANNY),
                .MORPH_MODE(MORPH_MODE),.MORPH_KERNEL_SHAPE(MORPH_KERNEL_SHAPE),
                .VSYNC_ACTIVE_LEVEL(VSYNC_ACTIVE_LEVEL)
            ) u_canny (
                .clk(clk),.rst_n(rst_n),.in_gray(gray),.in_rgb(input_rgb_delay),
                .in_median_enable(in_median_enable),
                .in_canny_enable(in_canny_enable),
                .in_valid(gray_valid),.in_hsync(gray_hsync),.in_vsync(gray_vsync),
                .in_high_threshold(in_high_threshold),
                .in_low_threshold(in_low_threshold),
                .out_red(out_red),.out_green(out_green),.out_blue(out_blue),
                .out_gray(out_gray),.out_edge(out_edge),.out_valid(out_valid),
                .out_window_valid(out_window_valid),.out_hsync(out_hsync),
                .out_vsync(out_vsync)
            );
        end
    endgenerate
endmodule
