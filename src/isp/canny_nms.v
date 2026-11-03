`timescale 1ns / 1ps

// Canny非极大值抑制：只保留梯度方向上的局部最大值，延迟一拍。
module canny_nms #(
    parameter integer GRADIENT_WIDTH = 11
)(
    input  wire clk,
    input  wire rst_n,
    input  wire [GRADIENT_WIDTH-1:0] in_g_mag,
    input  wire [1:0] in_direction,
    input  wire [GRADIENT_WIDTH-1:0] in_g_n,
    input  wire [GRADIENT_WIDTH-1:0] in_g_s,
    input  wire [GRADIENT_WIDTH-1:0] in_g_w,
    input  wire [GRADIENT_WIDTH-1:0] in_g_e,
    input  wire [GRADIENT_WIDTH-1:0] in_g_nw,
    input  wire [GRADIENT_WIDTH-1:0] in_g_ne,
    input  wire [GRADIENT_WIDTH-1:0] in_g_sw,
    input  wire [GRADIENT_WIDTH-1:0] in_g_se,
    input  wire in_valid,
    input  wire in_window_valid,
    input  wire in_hsync,
    input  wire in_vsync,
    output reg  [GRADIENT_WIDTH-1:0] out_nms,
    output reg  out_valid,
    output reg  out_window_valid,
    output reg  out_hsync,
    output reg  out_vsync
);
    reg [GRADIENT_WIDTH-1:0] compare_a;
    reg [GRADIENT_WIDTH-1:0] compare_b;

    always @(*) begin
        case (in_direction)
            2'd0: begin compare_a = in_g_w;  compare_b = in_g_e;  end
            2'd1: begin compare_a = in_g_ne; compare_b = in_g_sw; end
            2'd2: begin compare_a = in_g_n;  compare_b = in_g_s;  end
            default: begin compare_a = in_g_nw; compare_b = in_g_se; end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_nms <= 0;
            out_valid <= 0;
            out_window_valid <= 0;
            out_hsync <= 0;
            out_vsync <= 0;
        end else begin
            out_valid <= in_valid;
            out_window_valid <= in_valid && in_window_valid;
            out_hsync <= in_hsync;
            out_vsync <= in_vsync;
            if (in_valid && in_window_valid &&
                in_g_mag >= compare_a && in_g_mag >= compare_b)
                out_nms <= in_g_mag;
            else
                out_nms <= 0;
        end
    end
endmodule
