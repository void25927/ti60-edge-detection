`timescale 1ns / 1ps

// 运行时双阈值控制。
// 按键先修改待提交值，帧起始时再更新活动值，避免同一帧内阈值突变。
module threshold_controller #(
    parameter integer WIDTH = 11,
    parameter [WIDTH-1:0] DEFAULT_HIGH = 11'd80,
    parameter [WIDTH-1:0] MIN_HIGH = 11'd16,
    parameter [WIDTH-1:0] MAX_HIGH = 11'd2040,
    parameter [WIDTH-1:0] STEP = 11'd8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire adjust_enable,
    input  wire add_pulse,
    input  wire sub_pulse,
    input  wire frame_start,
    output reg  [WIDTH-1:0] high_threshold,
    output reg  [WIDTH-1:0] low_threshold,
    output reg  [WIDTH-1:0] pending_high_threshold
);
    wire [WIDTH-1:0] pending_low_threshold;
    assign pending_low_threshold = pending_high_threshold >> 1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_high_threshold <= DEFAULT_HIGH;
            high_threshold <= DEFAULT_HIGH;
            low_threshold <= DEFAULT_HIGH >> 1;
        end else begin
            if (adjust_enable && add_pulse && !sub_pulse) begin
                if (pending_high_threshold <= MAX_HIGH - STEP)
                    pending_high_threshold <= pending_high_threshold + STEP;
                else
                    pending_high_threshold <= MAX_HIGH;
            end else if (adjust_enable && sub_pulse && !add_pulse) begin
                if (pending_high_threshold >= MIN_HIGH + STEP)
                    pending_high_threshold <= pending_high_threshold - STEP;
                else
                    pending_high_threshold <= MIN_HIGH;
            end

            if (frame_start) begin
                high_threshold <= pending_high_threshold;
                low_threshold <= pending_low_threshold;
            end
        end
    end
endmodule
