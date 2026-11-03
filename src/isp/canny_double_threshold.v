`timescale 1ns / 1ps

// Canny双阈值分类：0=非边缘，1=弱边缘，2=强边缘，延迟一拍。
module canny_double_threshold #(
    parameter integer GRADIENT_WIDTH = 11
)(
    input  wire clk,
    input  wire rst_n,
    input  wire [GRADIENT_WIDTH-1:0] in_nms,
    input  wire [GRADIENT_WIDTH-1:0] in_high_threshold,
    input  wire [GRADIENT_WIDTH-1:0] in_low_threshold,
    input  wire in_valid,
    input  wire in_window_valid,
    input  wire in_hsync,
    input  wire in_vsync,
    output reg  [1:0] out_class,
    output reg  out_valid,
    output reg  out_window_valid,
    output reg  out_hsync,
    output reg  out_vsync
);
    wire [GRADIENT_WIDTH-1:0] safe_low_threshold;
    assign safe_low_threshold = (in_low_threshold <= in_high_threshold) ?
                                in_low_threshold : in_high_threshold;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_class <= 0;
            out_valid <= 0;
            out_window_valid <= 0;
            out_hsync <= 0;
            out_vsync <= 0;
        end else begin
            out_valid <= in_valid;
            out_window_valid <= in_valid && in_window_valid;
            out_hsync <= in_hsync;
            out_vsync <= in_vsync;
            if (in_valid && in_window_valid) begin
                if (in_nms >= in_high_threshold)
                    out_class <= 2'd2;
                else if (in_nms >= safe_low_threshold)
                    out_class <= 2'd1;
                else
                    out_class <= 2'd0;
            end else begin
                out_class <= 2'd0;
            end
        end
    end
endmodule
