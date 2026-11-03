`timescale 1ns / 1ps

// 基础Sobel固定/运行时阈值模块，延迟一拍。
module gradient_threshold #(
    parameter integer GRADIENT_WIDTH = 11,
    parameter [GRADIENT_WIDTH-1:0] THRESHOLD = 11'd128,
    parameter integer USE_RUNTIME_THRESHOLD = 0
)(
    input  wire clk,
    input  wire rst_n,
    input  wire [GRADIENT_WIDTH-1:0] in_gradient,
    input  wire [GRADIENT_WIDTH-1:0] in_threshold,
    input  wire in_valid,
    input  wire in_window_valid,
    input  wire in_hsync,
    input  wire in_vsync,
    output reg [7:0] out_pixel,
    output reg out_valid,
    output reg out_window_valid,
    output reg out_hsync,
    output reg out_vsync
);
    wire [GRADIENT_WIDTH-1:0] selected_threshold;
    assign selected_threshold = USE_RUNTIME_THRESHOLD ? in_threshold : THRESHOLD;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_pixel <= 0;
            out_valid <= 0;
            out_window_valid <= 0;
            out_hsync <= 0;
            out_vsync <= 0;
        end else begin
            out_valid <= in_valid;
            out_window_valid <= in_valid && in_window_valid;
            out_hsync <= in_hsync;
            out_vsync <= in_vsync;
            out_pixel <= (in_valid && in_window_valid &&
                          in_gradient >= selected_threshold) ? 8'd255 : 8'd0;
        end
    end
endmodule
