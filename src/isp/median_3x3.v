`timescale 1ns / 1ps

// 3×3中值滤波，采用三行排序和候选值归并，共三级流水。
module median_3x3 #(
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
    function [PIXEL_WIDTH-1:0] min2;
        input [PIXEL_WIDTH-1:0] a;
        input [PIXEL_WIDTH-1:0] b;
        begin min2 = (a < b) ? a : b; end
    endfunction

    function [PIXEL_WIDTH-1:0] max2;
        input [PIXEL_WIDTH-1:0] a;
        input [PIXEL_WIDTH-1:0] b;
        begin max2 = (a > b) ? a : b; end
    endfunction

    function [PIXEL_WIDTH-1:0] mid3;
        input [PIXEL_WIDTH-1:0] a;
        input [PIXEL_WIDTH-1:0] b;
        input [PIXEL_WIDTH-1:0] c;
        begin mid3 = max2(min2(a, b), min2(max2(a, b), c)); end
    endfunction

    reg [PIXEL_WIDTH-1:0] row1_max, row1_mid, row1_min;
    reg [PIXEL_WIDTH-1:0] row2_max, row2_mid, row2_min;
    reg [PIXEL_WIDTH-1:0] row3_max, row3_mid, row3_min;
    reg [PIXEL_WIDTH-1:0] min_of_max;
    reg [PIXEL_WIDTH-1:0] mid_of_mid;
    reg [PIXEL_WIDTH-1:0] max_of_min;
    reg [3:0] control1, control2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row1_max <= 0; row1_mid <= 0; row1_min <= 0;
            row2_max <= 0; row2_mid <= 0; row2_min <= 0;
            row3_max <= 0; row3_mid <= 0; row3_min <= 0;
            control1 <= 0;
        end else begin
            control1 <= {in_vsync, in_hsync, in_valid && in_window_valid, in_valid};
            if (in_valid && in_window_valid) begin
                row1_max <= max2(max2(in_p11, in_p12), in_p13);
                row1_mid <= mid3(in_p11, in_p12, in_p13);
                row1_min <= min2(min2(in_p11, in_p12), in_p13);
                row2_max <= max2(max2(in_p21, in_p22), in_p23);
                row2_mid <= mid3(in_p21, in_p22, in_p23);
                row2_min <= min2(min2(in_p21, in_p22), in_p23);
                row3_max <= max2(max2(in_p31, in_p32), in_p33);
                row3_mid <= mid3(in_p31, in_p32, in_p33);
                row3_min <= min2(min2(in_p31, in_p32), in_p33);
            end else begin
                row1_max <= 0; row1_mid <= 0; row1_min <= 0;
                row2_max <= 0; row2_mid <= 0; row2_min <= 0;
                row3_max <= 0; row3_mid <= 0; row3_min <= 0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            min_of_max <= 0;
            mid_of_mid <= 0;
            max_of_min <= 0;
            control2 <= 0;
        end else begin
            control2 <= control1;
            min_of_max <= min2(min2(row1_max, row2_max), row3_max);
            mid_of_mid <= mid3(row1_mid, row2_mid, row3_mid);
            max_of_min <= max2(max2(row1_min, row2_min), row3_min);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_pixel <= 0;
            out_valid <= 0;
            out_window_valid <= 0;
            out_hsync <= 0;
            out_vsync <= 0;
        end else begin
            {out_vsync, out_hsync, out_window_valid, out_valid} <= control2;
            if (control2[1] && control2[0])
                out_pixel <= mid3(min_of_max, mid_of_mid, max_of_min);
            else
                out_pixel <= 0;
        end
    end
endmodule
