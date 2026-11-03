`timescale 1ns / 1ps

// RGB888转8位灰度
// 公式：Gray = (77×R + 150×G + 29×B) >> 8
module rgb888_to_gray
(
    input  wire       clk,        // 像素时钟
    input  wire       rst_n,      // 低电平异步复位

    input  wire [7:0] in_red,     // 红色分量
    input  wire [7:0] in_green,   // 绿色分量
    input  wire [7:0] in_blue,    // 蓝色分量
    input  wire       in_valid,   // 输入像素有效
    input  wire       in_hsync,   // 输入行同步
    input  wire       in_vsync,   // 输入场同步

    output reg  [7:0] out_gray,   // 灰度像素
    output reg        out_valid,  // 输出像素有效
    output reg        out_hsync,  // 延迟后的行同步
    output reg        out_vsync   // 延迟后的场同步
);

    // 扩展位宽，防止移位时丢失高位
    wire [15:0] red_ext;
    wire [15:0] green_ext;
    wire [15:0] blue_ext;

    // 各颜色分量的加权结果
    wire [15:0] red_weighted;
    wire [15:0] green_weighted;
    wire [15:0] blue_weighted;

    // 最大值为255×256=65280，16位可以完整保存
    wire [15:0] gray_sum;

    assign red_ext   = {8'd0, in_red};
    assign green_ext = {8'd0, in_green};
    assign blue_ext  = {8'd0, in_blue};

    // 77 = 64 + 8 + 4 + 1
    assign red_weighted =
        (red_ext << 6) +
        (red_ext << 3) +
        (red_ext << 2) +
         red_ext;

    // 150 = 128 + 16 + 4 + 2
    assign green_weighted =
        (green_ext << 7) +
        (green_ext << 4) +
        (green_ext << 2) +
        (green_ext << 1);

    // 29 = 16 + 8 + 4 + 1
    assign blue_weighted =
        (blue_ext << 4) +
        (blue_ext << 3) +
        (blue_ext << 2) +
         blue_ext;

    assign gray_sum =
        red_weighted +
        green_weighted +
        blue_weighted;

    // 一级寄存输出，数据和控制信号同时延迟一个时钟
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_gray  <= 8'd0;
            out_valid <= 1'b0;
            out_hsync <= 1'b0;
            out_vsync <= 1'b0;
        end
        else begin
            out_valid <= in_valid;
            out_hsync <= in_hsync;
            out_vsync <= in_vsync;

            if (in_valid)
                out_gray <= gray_sum[15:8];
            else
                out_gray <= 8'd0;
        end
    end

endmodule