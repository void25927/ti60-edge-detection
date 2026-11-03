`timescale 1ns / 1ps

// 异步按键同步与消抖，输出稳定电平、按下脉冲和释放脉冲。
module debounce #(
    parameter integer CLK_FREQ_HZ = 148_800_000,
    parameter integer DEBOUNCE_MS = 20,
    parameter PRESSED_LEVEL = 1'b0
)(
    input  wire clk,
    input  wire rst_n,
    input  wire key_in,
    output reg  key_pressed,
    output reg  key_pressed_pulse,
    output reg  key_released_pulse
);
    localparam integer COUNT_MAX_RAW = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
    localparam integer COUNT_MAX = (COUNT_MAX_RAW < 1) ? 1 : COUNT_MAX_RAW;
    localparam integer COUNT_WIDTH = (COUNT_MAX <= 1) ? 1 : $clog2(COUNT_MAX);

    reg sync1;
    reg sync2;
    reg stable_level;
    reg [COUNT_WIDTH-1:0] count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync1 <= ~PRESSED_LEVEL;
            sync2 <= ~PRESSED_LEVEL;
        end else begin
            sync1 <= key_in;
            sync2 <= sync1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stable_level <= ~PRESSED_LEVEL;
            count <= 0;
            key_pressed <= 0;
            key_pressed_pulse <= 0;
            key_released_pulse <= 0;
        end else begin
            key_pressed_pulse <= 0;
            key_released_pulse <= 0;
            if (sync2 == stable_level) begin
                count <= 0;
            end else if (count == COUNT_MAX - 1) begin
                stable_level <= sync2;
                count <= 0;
                key_pressed_pulse <= (sync2 == PRESSED_LEVEL);
                key_released_pulse <= (sync2 != PRESSED_LEVEL);
            end else begin
                count <= count + 1'b1;
            end
            key_pressed <= (stable_level == PRESSED_LEVEL);
        end
    end
endmodule
