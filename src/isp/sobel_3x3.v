`timescale 1ns / 1ps

// 3×3 Sobel梯度计算，共三级流水。
// 方向量化：0=西/东，1=东北/西南，2=北/南，3=西北/东南。
module sobel_3x3 #(
    parameter integer PIXEL_WIDTH = 8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire [PIXEL_WIDTH-1:0] in_p11,
    input  wire [PIXEL_WIDTH-1:0] in_p12,
    input  wire [PIXEL_WIDTH-1:0] in_p13,
    input  wire [PIXEL_WIDTH-1:0] in_p21,
    input  wire [PIXEL_WIDTH-1:0] in_p22,
    input  wire [PIXEL_WIDTH-1:0] in_p23,
    input  wire [PIXEL_WIDTH-1:0] in_p31,
    input  wire [PIXEL_WIDTH-1:0] in_p32,
    input  wire [PIXEL_WIDTH-1:0] in_p33,
    input  wire in_valid,
    input  wire in_window_valid,
    input  wire in_hsync,
    input  wire in_vsync,
    output reg signed [PIXEL_WIDTH+2:0] out_gx,
    output reg signed [PIXEL_WIDTH+2:0] out_gy,
    output reg [PIXEL_WIDTH+2:0] out_gradient,
    output reg [1:0] out_direction,
    output reg out_valid,
    output reg out_window_valid,
    output reg out_hsync,
    output reg out_vsync
);
    localparam integer SUM_WIDTH  = PIXEL_WIDTH + 2;
    localparam integer GRAD_WIDTH = PIXEL_WIDTH + 3;
    localparam integer DIR_WIDTH = GRAD_WIDTH + 15; // 定点比较位宽，容纳绝对值乘32768

    reg [SUM_WIDTH-1:0] right_sum;
    reg [SUM_WIDTH-1:0] left_sum;
    reg [SUM_WIDTH-1:0] bottom_sum;
    reg [SUM_WIDTH-1:0] top_sum;
    reg signed [GRAD_WIDTH-1:0] gx_stage2;
    reg signed [GRAD_WIDTH-1:0] gy_stage2;
    reg [3:0] control1;
    reg [3:0] control2;

    wire [GRAD_WIDTH-1:0] abs_x;
    wire [GRAD_WIDTH-1:0] abs_y;
    wire [DIR_WIDTH-1:0] abs_x_ext; // 无符号扩展后再移位，防止高位丢失
    wire [DIR_WIDTH-1:0] abs_y_ext;
    wire [DIR_WIDTH-1:0] x_tan_limit; // |Gx|×13573
    wire [DIR_WIDTH-1:0] y_tan_limit; // |Gy|×13573
    reg  [1:0] direction_stage3;

    assign abs_x = gx_stage2[GRAD_WIDTH-1] ? (~gx_stage2 + 1'b1) : gx_stage2;
    assign abs_y = gy_stage2[GRAD_WIDTH-1] ? (~gy_stage2 + 1'b1) : gy_stage2;
    assign abs_x_ext = {{15{1'b0}}, abs_x};
    assign abs_y_ext = {{15{1'b0}}, abs_y};
    // 13573=8192+4096+1024+256+4+1；仅使用移位加法。
    assign x_tan_limit = (abs_x_ext << 13) + (abs_x_ext << 12) +
                         (abs_x_ext << 10) + (abs_x_ext << 8) +
                         (abs_x_ext << 2) + abs_x_ext;
    assign y_tan_limit = (abs_y_ext << 13) + (abs_y_ext << 12) +
                         (abs_y_ext << 10) + (abs_y_ext << 8) +
                         (abs_y_ext << 2) + abs_y_ext;

    // tan(22.5°)≈13573/32768，角度误差小于0.000075°。
    // 零梯度及等号优先归水平/垂直方向；符号决定两条对角线。
    always @(*) begin
        if ((abs_y_ext << 15) <= x_tan_limit)
            direction_stage3 = 2'd0;
        else if ((abs_x_ext << 15) <= y_tan_limit)
            direction_stage3 = 2'd2;
        else if (gx_stage2[GRAD_WIDTH-1] != gy_stage2[GRAD_WIDTH-1])
            direction_stage3 = 2'd1;
        else
            direction_stage3 = 2'd3;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            right_sum <= 0;
            left_sum <= 0;
            bottom_sum <= 0;
            top_sum <= 0;
            gx_stage2 <= 0;
            gy_stage2 <= 0;
            control1 <= 0;
            control2 <= 0;
            out_gx <= 0;
            out_gy <= 0;
            out_gradient <= 0;
            out_direction <= 0;
            out_valid <= 0;
            out_window_valid <= 0;
            out_hsync <= 0;
            out_vsync <= 0;
        end else begin
            control1 <= {in_vsync, in_hsync, in_valid && in_window_valid, in_valid};
            control2 <= control1;
            {out_vsync, out_hsync, out_window_valid, out_valid} <= control2;

            if (in_valid && in_window_valid) begin
                right_sum  <= {2'b0, in_p13} + ({2'b0, in_p23} << 1) + {2'b0, in_p33};
                left_sum   <= {2'b0, in_p11} + ({2'b0, in_p21} << 1) + {2'b0, in_p31};
                bottom_sum <= {2'b0, in_p31} + ({2'b0, in_p32} << 1) + {2'b0, in_p33};
                top_sum    <= {2'b0, in_p11} + ({2'b0, in_p12} << 1) + {2'b0, in_p13};
            end else begin
                right_sum <= 0;
                left_sum <= 0;
                bottom_sum <= 0;
                top_sum <= 0;
            end

            // 补符号位后相减，避免无符号减法回绕。
            gx_stage2 <= $signed({1'b0, right_sum}) - $signed({1'b0, left_sum});
            gy_stage2 <= $signed({1'b0, bottom_sum}) - $signed({1'b0, top_sum});
            out_gx <= gx_stage2;
            out_gy <= gy_stage2;
            out_gradient <= abs_x + abs_y;
            out_direction <= direction_stage3;
        end
    end
endmodule
