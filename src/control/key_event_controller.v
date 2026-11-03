`timescale 1ns / 1ps

// 将消抖后的按键动作分成短按和长按事件。
// 长按达到设定时间时只触发一次，释放时不再产生短按。
module key_event_controller #(
    parameter integer CLK_FREQ_HZ = 148_800_000,
    parameter integer LONG_PRESS_MS = 800
)(
    input  wire clk,
    input  wire rst_n,
    input  wire key_pressed,
    input  wire key_pressed_pulse,
    input  wire key_released_pulse,
    output reg  short_press_pulse,
    output reg  long_press_pulse
);
    localparam integer COUNT_MAX_RAW = (CLK_FREQ_HZ / 1000) * LONG_PRESS_MS;
    localparam integer COUNT_MAX = (COUNT_MAX_RAW < 1) ? 1 : COUNT_MAX_RAW;
    localparam integer COUNT_WIDTH = (COUNT_MAX <= 1) ? 1 : $clog2(COUNT_MAX);

    reg [COUNT_WIDTH-1:0] hold_count;
    reg long_sent;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hold_count <= 0;
            long_sent <= 0;
            short_press_pulse <= 0;
            long_press_pulse <= 0;
        end else begin
            short_press_pulse <= 0;
            long_press_pulse <= 0;

            // 释放与计时到点同拍时优先处理释放，避免同时产生短按和长按。
            if (key_released_pulse) begin
                if (!long_sent)
                    short_press_pulse <= 1'b1;
                hold_count <= 0;
                long_sent <= 0;
            end else if (key_pressed_pulse) begin
                hold_count <= 0;
                long_sent <= 0;
            end else if (key_pressed && !long_sent) begin
                if (hold_count == COUNT_MAX - 1) begin
                    long_press_pulse <= 1'b1;
                    long_sent <= 1'b1;
                end else begin
                    hold_count <= hold_count + 1'b1;
                end
            end

        end
    end
endmodule
