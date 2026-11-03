`timescale 1ns / 1ps

// 将二值边缘以指定颜色叠加到原始RGB图像上。
// 可将边缘向右扩展两个像素，提高高分辨率画面中的辨识度。
module edge_overlay #(
    parameter [7:0] EDGE_R = 8'hFF, // 边缘颜色：红分量
    parameter [7:0] EDGE_G = 8'h00, // 边缘颜色：绿分量
    parameter [7:0] EDGE_B = 8'hFF, // 边缘颜色：蓝分量
    parameter integer HORIZONTAL_EXPAND = 1, // 1启用横向加粗
    parameter integer EXPAND_PIXELS = 2,     // 向右增加的像素数，正式实例设4
    parameter integer ADAPTIVE_COLOR = 0     // 1：亮背景红边，暗背景使用指定颜色
)(
    input  wire       clk,          // 像素时钟
    input  wire       rst_n,        // 低电平异步复位
    input  wire       in_valid,     // 输入像素有效，高电平有效
    input  wire       in_hsync,     // 输入行同步
    input  wire       in_vsync,     // 输入场同步
    input  wire [7:0] in_red,       // 原始红色分量
    input  wire [7:0] in_green,     // 原始绿色分量
    input  wire [7:0] in_blue,      // 原始蓝色分量
    input  wire       in_edge,      // 边缘标志，高电平表示边缘
    output reg        out_valid,    // 输出像素有效
    output reg        out_hsync,    // 输出行同步
    output reg        out_vsync,    // 输出场同步
    output reg  [7:0] out_red,      // 叠加后红色分量
    output reg  [7:0] out_green,    // 叠加后绿色分量
    output reg  [7:0] out_blue      // 叠加后蓝色分量
);

    localparam integer HISTORY_WIDTH = (EXPAND_PIXELS<2) ? 2 : EXPAND_PIXELS;
    localparam [HISTORY_WIDTH-1:0] HISTORY_MASK = (2**EXPAND_PIXELS)-1;
    reg [HISTORY_WIDTH-1:0] edge_history; // 当前行先前边缘，用于显示加粗
    wire [9:0] background_luma = {2'b0,in_red}+{1'b0,in_green,1'b0}+{2'b0,in_blue};
    wire bright_background = ADAPTIVE_COLOR && background_luma>=10'd640;
    wire edge_visible = in_edge |
                        (HORIZONTAL_EXPAND ? (|(edge_history & HISTORY_MASK)) : 1'b0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_hsync <= 1'b0;
            out_vsync <= 1'b0;
            out_red   <= 8'd0;
            out_green <= 8'd0;
            out_blue  <= 8'd0;
            edge_history <= 2'b00;
        end else begin
            out_valid <= in_valid;
            out_hsync <= in_hsync;
            out_vsync <= in_vsync;

            if (!in_valid) begin
                out_red   <= 8'd0;
                out_green <= 8'd0;
                out_blue  <= 8'd0;
                edge_history <= 2'b00;
            end else if (edge_visible) begin
                out_red   <= EDGE_R;
                out_green <= bright_background ? 8'd0 : EDGE_G;
                out_blue  <= bright_background ? 8'd0 : EDGE_B;
                edge_history <= {edge_history[HISTORY_WIDTH-2:0], in_edge};
            end else begin
                out_red   <= in_red;
                out_green <= in_green;
                out_blue  <= in_blue;
                edge_history <= {edge_history[HISTORY_WIDTH-2:0], in_edge};
            end
        end
    end

endmodule
