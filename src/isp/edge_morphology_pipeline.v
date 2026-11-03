`timescale 1ns / 1ps

// 边缘二值图形态学后处理。
// MODE=0旁路，1膨胀，2腐蚀，3闭运算(先膨胀后腐蚀)，4开运算(先腐蚀后膨胀)。
// Canny单像素边缘默认推荐MODE=3，用于连接小断裂并尽量恢复原始线宽；
// MODE=4会清除小噪点，但完整3x3结构元也可能删除细边缘，需按场景启用。
module edge_morphology_pipeline #(
    parameter integer IMAGE_WIDTH = 1920,
    parameter integer ADDR_WIDTH = 11,
    parameter integer MODE = 3,
    parameter integer KERNEL_SHAPE = 1,
    parameter VSYNC_ACTIVE_LEVEL = 1'b0
)(
    input  wire clk,
    input  wire rst_n,
    input  wire in_edge,
    input  wire [7:0] in_red,
    input  wire [7:0] in_green,
    input  wire [7:0] in_blue,
    input  wire [7:0] in_gray,
    input  wire in_valid,
    input  wire in_window_valid,
    input  wire in_hsync,
    input  wire in_vsync,
    output wire out_edge,
    output wire [7:0] out_red,
    output wire [7:0] out_green,
    output wire [7:0] out_blue,
    output wire [7:0] out_gray,
    output wire out_valid,
    output wire out_window_valid,
    output wire out_hsync,
    output wire out_vsync
);
    generate
        if (MODE == 0) begin : g_bypass
            assign out_edge = in_valid && in_window_valid && in_edge;
            assign out_red = in_valid ? in_red : 8'd0;
            assign out_green = in_valid ? in_green : 8'd0;
            assign out_blue = in_valid ? in_blue : 8'd0;
            assign out_gray = in_valid ? in_gray : 8'd0;
            assign out_valid = in_valid;
            assign out_window_valid = in_valid && in_window_valid;
            assign out_hsync = in_hsync;
            assign out_vsync = in_vsync;
        end else if (MODE == 1 || MODE == 2) begin : g_single
            binary_morphology_3x3 #(
                .IMAGE_WIDTH(IMAGE_WIDTH),.ADDR_WIDTH(ADDR_WIDTH),
                .OPERATION(MODE == 2),.KERNEL_SHAPE(KERNEL_SHAPE),
                .VSYNC_ACTIVE_LEVEL(VSYNC_ACTIVE_LEVEL)
            ) u_single (
                .clk(clk),.rst_n(rst_n),.in_edge(in_edge),
                .in_red(in_red),.in_green(in_green),.in_blue(in_blue),.in_gray(in_gray),
                .in_valid(in_valid),.in_window_valid(in_window_valid),
                .in_hsync(in_hsync),.in_vsync(in_vsync),
                .out_edge(out_edge),.out_red(out_red),.out_green(out_green),
                .out_blue(out_blue),.out_gray(out_gray),.out_valid(out_valid),
                .out_window_valid(out_window_valid),.out_hsync(out_hsync),.out_vsync(out_vsync)
            );
        end else begin : g_double
            wire stage_edge;
            wire [7:0] stage_red,stage_green,stage_blue,stage_gray;
            wire stage_valid,stage_window_valid,stage_hsync,stage_vsync;

            binary_morphology_3x3 #(
                .IMAGE_WIDTH(IMAGE_WIDTH),.ADDR_WIDTH(ADDR_WIDTH),
                .OPERATION(MODE == 4),.KERNEL_SHAPE(KERNEL_SHAPE),
                .VSYNC_ACTIVE_LEVEL(VSYNC_ACTIVE_LEVEL)
            ) u_first (
                .clk(clk),.rst_n(rst_n),.in_edge(in_edge),
                .in_red(in_red),.in_green(in_green),.in_blue(in_blue),.in_gray(in_gray),
                .in_valid(in_valid),.in_window_valid(in_window_valid),
                .in_hsync(in_hsync),.in_vsync(in_vsync),
                .out_edge(stage_edge),.out_red(stage_red),.out_green(stage_green),
                .out_blue(stage_blue),.out_gray(stage_gray),.out_valid(stage_valid),
                .out_window_valid(stage_window_valid),.out_hsync(stage_hsync),.out_vsync(stage_vsync)
            );

            binary_morphology_3x3 #(
                .IMAGE_WIDTH(IMAGE_WIDTH),.ADDR_WIDTH(ADDR_WIDTH),
                .OPERATION(MODE != 4),.KERNEL_SHAPE(KERNEL_SHAPE),
                .VSYNC_ACTIVE_LEVEL(VSYNC_ACTIVE_LEVEL)
            ) u_second (
                .clk(clk),.rst_n(rst_n),.in_edge(stage_edge),
                .in_red(stage_red),.in_green(stage_green),.in_blue(stage_blue),.in_gray(stage_gray),
                .in_valid(stage_valid),.in_window_valid(stage_window_valid),
                .in_hsync(stage_hsync),.in_vsync(stage_vsync),
                .out_edge(out_edge),.out_red(out_red),.out_green(out_green),
                .out_blue(out_blue),.out_gray(out_gray),.out_valid(out_valid),
                .out_window_valid(out_window_valid),.out_hsync(out_hsync),.out_vsync(out_vsync)
            );
        end
    endgenerate
endmodule
