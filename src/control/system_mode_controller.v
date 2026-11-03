`timescale 1ns / 1ps

// 统一解释板载按键，并在帧边界推进4帧回放位置。
module system_mode_controller #(
    parameter integer REPLAY_HOLD_FRAMES = 15 // 每个历史帧保持的HDMI帧数
)(
    input  wire       clk,                  // HDMI像素时钟
    input  wire       rst_n,                // 低电平异步复位
    input  wire       frame_start,          // HDMI新帧单周期脉冲
    input  wire       function_short_press, // FUNCTION键短按：切换显示视图
    input  wire       function_long_press,  // FUNCTION键长按：进入或退出参数模式
    input  wire       action_short_press,   // 操作键短按脉冲
    input  wire       action_long_press,    // 操作键长按脉冲

    output reg  [1:0] system_mode,           // 0实时，1冻结，2回放，3参数
    output reg        display_mode,          // 0灰度/黑白边缘分屏，1彩色边缘叠加
    output wire [1:0] ddr_mode,              // DDR仅使用实时、冻结、回放三种模式
    output reg  [1:0] replay_offset,         // 0最新，3最旧
    output wire       threshold_adjust_enable,// 参数界面允许调节阈值
    output reg        threshold_add_pulse,   // 高阈值增加脉冲
    output reg        threshold_sub_pulse    // 高阈值降低脉冲
);

    localparam [1:0] MODE_LIVE   = 2'd0;
    localparam [1:0] MODE_FREEZE = 2'd1;
    localparam [1:0] MODE_REPLAY = 2'd2;
    localparam [1:0] MODE_PARAM  = 2'd3;

    localparam integer REPLAY_COUNT_WIDTH =
        (REPLAY_HOLD_FRAMES <= 1) ? 1 : $clog2(REPLAY_HOLD_FRAMES);
    reg [REPLAY_COUNT_WIDTH-1:0] replay_hold_count; // 当前回放帧保持计数

    assign threshold_adjust_enable = (system_mode == MODE_PARAM);
    assign ddr_mode = (system_mode == MODE_FREEZE) ? MODE_FREEZE :
                      (system_mode == MODE_REPLAY) ? MODE_REPLAY : MODE_LIVE;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            system_mode        <= MODE_LIVE;
            display_mode       <= 1'b0;
            replay_offset      <= 2'd3;
            replay_hold_count  <= {REPLAY_COUNT_WIDTH{1'b0}};
            threshold_add_pulse <= 1'b0;
            threshold_sub_pulse <= 1'b0;
        end else begin
            threshold_add_pulse <= 1'b0;
            threshold_sub_pulse <= 1'b0;

            // FUNCTION长按进入或退出参数模式。
            if (function_long_press) begin
                if (system_mode == MODE_PARAM)
                    system_mode <= MODE_LIVE;
                else
                    system_mode <= MODE_PARAM;
                replay_offset     <= 2'd3;
                replay_hold_count <= {REPLAY_COUNT_WIDTH{1'b0}};
            end else begin
                // FUNCTION短按循环切换两种显示视图，并取消冻结或回放。
                if (function_short_press) begin
                    display_mode <= ~display_mode;
                    if (system_mode == MODE_FREEZE || system_mode == MODE_REPLAY)
                        system_mode <= MODE_LIVE;
                    replay_offset     <= 2'd3;
                    replay_hold_count <= {REPLAY_COUNT_WIDTH{1'b0}};
                end

                case (system_mode)
                    MODE_LIVE: begin
                        if (action_short_press)
                            system_mode <= MODE_FREEZE;
                        else if (action_long_press) begin
                            system_mode   <= MODE_REPLAY;
                            replay_offset <= 2'd3;
                        end
                    end

                    MODE_FREEZE: begin
                        if (action_short_press)
                            system_mode <= MODE_LIVE;
                        else if (action_long_press) begin
                            system_mode   <= MODE_REPLAY;
                            replay_offset <= 2'd3;
                        end
                    end

                    MODE_REPLAY: begin
                        // 回放中短按冻结当前历史帧，长按返回实时画面。
                        if (action_short_press)
                            system_mode <= MODE_FREEZE;
                        else if (action_long_press)
                            system_mode <= MODE_LIVE;
                    end

                    MODE_PARAM: begin
                        if (action_short_press)
                            threshold_add_pulse <= 1'b1;
                        else if (action_long_press)
                            threshold_sub_pulse <= 1'b1;
                    end

                    default: system_mode <= MODE_LIVE;
                endcase

                // 回放顺序为最旧到最新：3、2、1、0。
                if (!function_short_press && system_mode == MODE_REPLAY && frame_start) begin
                    if (REPLAY_HOLD_FRAMES <= 1 ||
                        replay_hold_count == REPLAY_HOLD_FRAMES - 1) begin
                        replay_hold_count <= {REPLAY_COUNT_WIDTH{1'b0}};
                        replay_offset <= (replay_offset == 2'd0) ? 2'd3 :
                                         replay_offset - 1'b1;
                    end else begin
                        replay_hold_count <= replay_hold_count + 1'b1;
                    end
                end else if (system_mode != MODE_REPLAY) begin
                    replay_hold_count <= {REPLAY_COUNT_WIDTH{1'b0}};
                end
            end
        end
    end

endmodule
