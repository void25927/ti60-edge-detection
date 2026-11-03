`timescale 1ns / 1ps

// Canny高斯平滑，卷积核为[1 2 1; 2 4 2; 1 2 1]/16，共两级流水。
module gaussian_3x3 #(
    parameter integer PIXEL_WIDTH = 8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire [PIXEL_WIDTH-1:0] in_p11, in_p12, in_p13,
    input  wire [PIXEL_WIDTH-1:0] in_p21, in_p22, in_p23,
    input  wire [PIXEL_WIDTH-1:0] in_p31, in_p32, in_p33,
    input  wire in_valid,
    input  wire in_window_valid,
    input  wire in_hsync,
    input  wire in_vsync,
    output reg  [PIXEL_WIDTH-1:0] out_pixel,
    output reg  out_valid,
    output reg  out_window_valid,
    output reg  out_hsync,
    output reg  out_vsync
);
    localparam integer SUM_WIDTH = PIXEL_WIDTH + 4;
    reg [SUM_WIDTH-1:0] weighted_sum;
    reg [3:0] control1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weighted_sum <= 0;
            control1 <= 0;
            out_pixel <= 0;
            out_valid <= 0;
            out_window_valid <= 0;
            out_hsync <= 0;
            out_vsync <= 0;
        end else begin
            control1 <= {in_vsync, in_hsync, in_valid && in_window_valid, in_valid};
            if (in_valid && in_window_valid) begin
                weighted_sum <=
                    {{4{1'b0}}, in_p11} + ({{4{1'b0}}, in_p12} << 1) + {{4{1'b0}}, in_p13} +
                    ({{4{1'b0}}, in_p21} << 1) + ({{4{1'b0}}, in_p22} << 2) +
                    ({{4{1'b0}}, in_p23} << 1) + {{4{1'b0}}, in_p31} +
                    ({{4{1'b0}}, in_p32} << 1) + {{4{1'b0}}, in_p33};
            end else begin
                weighted_sum <= 0;
            end

            {out_vsync, out_hsync, out_window_valid, out_valid} <= control1;
            out_pixel <= (control1[1] && control1[0]) ? weighted_sum[PIXEL_WIDTH+3:4] : 0;
        end
    end
endmodule
