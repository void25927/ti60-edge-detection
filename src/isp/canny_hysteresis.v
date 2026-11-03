`timescale 1ns / 1ps

// Canny局部滞后连接，延迟一拍。
// 强边缘保留；与8邻域强边缘相连的弱边缘提升为强边缘。
// 未连接弱边缘继续保持弱分类，允许后续级继续传播。
module canny_hysteresis #(
    parameter REPAIR_SHORT_GAP = 0 // 末级可选：修补两个强边缘之间的单像素缺口
)(
    input  wire clk,
    input  wire rst_n,
    input  wire [1:0] in_c11, in_c12, in_c13,
    input  wire [1:0] in_c21, in_c22, in_c23,
    input  wire [1:0] in_c31, in_c32, in_c33,
    input  wire in_valid,
    input  wire in_window_valid,
    input  wire in_hsync,
    input  wire in_vsync,
    output reg  [1:0] out_class,
    output reg  out_edge,
    output reg  out_valid,
    output reg  out_window_valid,
    output reg  out_hsync,
    output reg  out_vsync
);
    wire neighbor_strong;
    // 仅限四个方向的相对端点；不是整帧八邻域追踪，也不保证轮廓闭合。
    wire opposite_strong =
        ((in_c21 == 2'd2) && (in_c23 == 2'd2)) ||
        ((in_c12 == 2'd2) && (in_c32 == 2'd2)) ||
        ((in_c11 == 2'd2) && (in_c33 == 2'd2)) ||
        ((in_c13 == 2'd2) && (in_c31 == 2'd2));
    assign neighbor_strong =
        (in_c11 == 2'd2) || (in_c12 == 2'd2) || (in_c13 == 2'd2) ||
        (in_c21 == 2'd2) ||                         (in_c23 == 2'd2) ||
        (in_c31 == 2'd2) || (in_c32 == 2'd2) || (in_c33 == 2'd2);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_class <= 0;
            out_edge <= 0;
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
                if (in_c22 == 2'd2 || (in_c22 == 2'd1 && neighbor_strong) ||
                    (REPAIR_SHORT_GAP && in_c22 == 2'd0 && opposite_strong)) begin
                    out_class <= 2'd2;
                    out_edge <= 1'b1;
                end else begin
                    out_class <= in_c22;
                    out_edge <= 1'b0;
                end
            end else begin
                out_class <= 0;
                out_edge <= 0;
            end
        end
    end
endmodule
