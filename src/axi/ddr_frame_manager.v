`timescale 1ns / 1ps

// 管理DDR中的4个帧区，支持实时显示、冻结和最近4帧回放。
module ddr_frame_manager (
    input  wire       clk,                    // DDR AXI时钟
    input  wire       rst,                    // 高电平同步复位
    input  wire [1:0] requested_mode_async,   // 其他时钟域的模式请求
    input  wire [1:0] replay_offset_async,    // 0最新，3最旧
    input  wire       source_frame_boundary,  // 摄像头一帧结束脉冲
    input  wire       write_frame_done,       // 当前写帧已完整写入DDR
    input  wire       read_frame_boundary,    // HDMI准备读取新帧

    output reg        capture_enable,         // 允许采集新帧
    output reg  [1:0] write_index,             // 当前DDR写帧区
    output reg  [1:0] read_index,              // 当前DDR读帧区
    output reg  [1:0] active_mode,             // DDR实际执行模式
    output reg  [2:0] history_valid_count      // 已保存历史帧数量0～4
);

    localparam [1:0] MODE_LIVE   = 2'd0;
    localparam [1:0] MODE_FREEZE = 2'd1;
    localparam [1:0] MODE_REPLAY = 2'd2;

    // 两级同步模式和回放位置，避免组合跨时钟控制。
    reg [1:0] mode_sync0, mode_sync1;
    reg [1:0] offset_sync0, offset_sync1;

    // history0为最新完整帧，history3为最旧完整帧。
    reg [1:0] history0, history1, history2, history3;
    reg [1:0] freeze_index;

    wire [1:0] next_write_p1 = write_index + 1'b1;
    wire [1:0] next_write_index =
        (next_write_p1 == read_index) ? write_index + 2'd2 : next_write_p1;

    reg [1:0] selected_history;
    always @(*) begin
        case (offset_sync1)
            2'd0: selected_history = history0;
            2'd1: selected_history = (history_valid_count >= 2) ? history1 : history0;
            2'd2: selected_history = (history_valid_count >= 3) ? history2 : history0;
            default: selected_history = (history_valid_count >= 4) ? history3 : history0;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            mode_sync0   <= MODE_LIVE;
            mode_sync1   <= MODE_LIVE;
            offset_sync0 <= 2'd0;
            offset_sync1 <= 2'd0;
        end else begin
            mode_sync0   <= requested_mode_async;
            mode_sync1   <= mode_sync0;
            offset_sync0 <= replay_offset_async;
            offset_sync1 <= offset_sync0;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            capture_enable    <= 1'b1;
            write_index       <= 2'd0;
            read_index        <= 2'd2;
            active_mode       <= MODE_LIVE;
            history_valid_count <= 3'd0;
            history0          <= 2'd0;
            history1          <= 2'd0;
            history2          <= 2'd0;
            history3          <= 2'd0;
            freeze_index      <= 2'd0;
        end else begin
            // 完整写入后才登记历史帧，避免回放半帧。
            if (write_frame_done) begin
                history3 <= history2;
                history2 <= history1;
                history1 <= history0;
                history0 <= write_index;
                if (history_valid_count < 4)
                    history_valid_count <= history_valid_count + 1'b1;

                write_index <= next_write_index;

                // 冻结或回放请求在完整帧边界生效，并停止后续写入。
                if (mode_sync1 != MODE_LIVE) begin
                    capture_enable <= 1'b0;
                    active_mode    <= mode_sync1;
                    freeze_index   <= write_index;
                end
            end

            // 停止采集期间，等到摄像头帧边界再恢复实时写入。
            if (!capture_enable && mode_sync1 == MODE_LIVE &&
                source_frame_boundary) begin
                capture_enable <= 1'b1;
                active_mode    <= MODE_LIVE;
            end

            // 冻结和回放之间可在显示帧边界直接切换。
            if (!capture_enable && read_frame_boundary) begin
                if (mode_sync1 == MODE_FREEZE && active_mode == MODE_REPLAY)
                    freeze_index <= read_index;
                if (mode_sync1 != MODE_LIVE)
                    active_mode <= mode_sync1;
            end

            // 读帧索引只在HDMI新帧边界改变，避免显示撕裂。
            if (read_frame_boundary) begin
                if (mode_sync1 == MODE_REPLAY) begin
                    read_index <= selected_history;
                end else if (mode_sync1 == MODE_FREEZE) begin
                    if (active_mode == MODE_REPLAY)
                        read_index <= read_index;
                    else if (write_frame_done)
                        read_index <= write_index;
                    else
                        read_index <= freeze_index;
                end else if (write_frame_done) begin
                    read_index <= write_index;
                end else if (history_valid_count != 0) begin
                    read_index <= history0;
                end
            end
        end
    end

endmodule
