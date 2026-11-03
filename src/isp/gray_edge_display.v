`timescale 1ns / 1ps

// 整幅源图按原坐标显示：模式0左灰度右边缘，模式1全屏彩色叠加。
// SOURCE_WIDTH为半屏宽时兼容旧版双图映射；正式工程使用1920列完整源图。
// 模块在场消隐期预取第0行，显示当前行时预取下一行。
module gray_edge_display #(
    parameter integer SOURCE_WIDTH   = 960,  // 单幅源图宽度
    parameter integer DISPLAY_WIDTH  = 1920, // HDMI有效区宽度
    parameter integer DISPLAY_HEIGHT = 1080, // HDMI有效区高度
    parameter integer FIFO_START_LEVEL = 960,// 启动整行读取所需FIFO像素数
    parameter VSYNC_ACTIVE_LEVEL = 1'b0      // HDMI场同步低有效
)(
    input  wire        clk,             // HDMI像素时钟
    input  wire        rst_n,           // 低电平异步复位

    input  wire        in_lcd_de,       // HDMI有效区，高电平有效
    input  wire        in_lcd_hsync,    // HDMI行同步
    input  wire        in_lcd_vsync,    // HDMI场同步
    input  wire        in_display_mode, // 0分屏，1彩色边缘叠加

    input  wire [7:0]  in_ddr_data,     // DDR读FIFO当前队首RAW8像素
    input  wire        in_ddr_valid,    // FIFO非空，当前数据有效
    input  wire [12:0] in_ddr_count,    // FIFO内可读像素数量
    output wire        out_ddr_request, // 接受一个RAW8像素时弹出FIFO

    output wire [7:0]  out_source_raw,  // 送往去马赛克模块的RAW8像素
    output wire        out_source_valid,// 源像素有效
    output wire        out_source_hsync,// 源行有效
    output wire        out_source_vsync,// 源帧有效，高电平有效

    input  wire [7:0]  in_gray,         // 算法输出灰度像素
    input  wire [7:0]  in_edge,         // 算法输出黑白边缘像素
    input  wire [23:0] in_overlay_rgb,  // 算法输出彩色边缘叠加像素
    input  wire        in_alg_valid,    // 算法输出像素有效
    input  wire        in_window_valid, // 3×3窗口有效

    output wire [7:0]  out_pixel,       // HDMI灰度输出像素
    output wire [23:0] out_rgb,         // HDMI彩色输出像素
    output wire        out_valid,       // HDMI数据有效
    output wire        out_window_valid,// 当前显示像素的窗口有效标志
    output wire        out_region_edge, // 1表示右侧边缘图
    output wire        out_display_mode,// 当前帧实际使用的显示模式
    output wire        out_hsync,       // 与输出像素对齐的行同步
    output wire        out_vsync,       // 与输出像素对齐的场同步
    output reg         underflow_seen,  // FIFO欠数或显示行未就绪时锁存
    output reg         frame_sync_error // 行预取未按时完成时锁存
);

    localparam integer SOURCE_ADDR_WIDTH = $clog2(SOURCE_WIDTH); // 行缓存地址宽度
    localparam [10:0] SOURCE_WIDTH_VALUE = SOURCE_WIDTH;
    localparam [10:0] SPLIT_X = (SOURCE_WIDTH == DISPLAY_WIDTH) ? DISPLAY_WIDTH/2 : SOURCE_WIDTH;

    reg lcd_de_d;
    reg lcd_vsync_d;
    wire lcd_de_rise = in_lcd_de && !lcd_de_d;
    wire lcd_de_fall = !in_lcd_de && lcd_de_d;
    wire lcd_vsync_rise = (in_lcd_vsync != VSYNC_ACTIVE_LEVEL) &&
                          (lcd_vsync_d == VSYNC_ACTIVE_LEVEL);

    reg [10:0] display_x; // HDMI有效区横坐标0～1919
    reg [10:0] display_y; // HDMI有效区纵坐标0～1079
    reg display_mode_frame; // 仅在帧边界更新，避免半帧切换

    // 每个缓存地址保存：窗口有效、灰度、黑白边缘、彩色叠加像素。
    reg [40:0] line_bank0 [0:SOURCE_WIDTH-1];
    reg [40:0] line_bank1 [0:SOURCE_WIDTH-1];
    reg        bank0_ready;
    reg        bank1_ready;
    reg [10:0] bank0_row;
    reg [10:0] bank1_row;

    // DDR逐行预取控制。
    reg        fetch_pending;
    reg        fetch_active;
    reg        fifo_empty_seen; // 新帧开始后已确认读FIFO完成清空
    reg [10:0] fetch_row;
    reg [SOURCE_ADDR_WIDTH-1:0] fetch_count;
    reg        frame_bad;

    wire source_accept = fetch_active && in_ddr_valid && !frame_bad;
    assign out_ddr_request = source_accept;
    assign out_source_raw   = in_ddr_data;
    assign out_source_valid = source_accept;
    assign out_source_hsync = fetch_active && !frame_bad;
    assign out_source_vsync = (in_lcd_vsync != VSYNC_ACTIVE_LEVEL) && !frame_bad;

    // 场消隐开始后预取第0行；每个显示行开始时安排下一行。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lcd_de_d         <= 1'b0;
            lcd_vsync_d      <= VSYNC_ACTIVE_LEVEL;
            fetch_pending    <= 1'b0;
            fetch_active     <= 1'b0;
            fifo_empty_seen  <= 1'b0;
            fetch_row        <= 11'd0;
            fetch_count      <= {SOURCE_ADDR_WIDTH{1'b0}};
            frame_bad        <= 1'b0;
            underflow_seen   <= 1'b0;
            frame_sync_error <= 1'b0;
        end else begin
            lcd_de_d    <= in_lcd_de;
            lcd_vsync_d <= in_lcd_vsync;

            if (in_lcd_vsync == VSYNC_ACTIVE_LEVEL) begin
                fetch_pending    <= 1'b0;
                fetch_active     <= 1'b0;
                fifo_empty_seen  <= 1'b0;
                fetch_row        <= 11'd0;
                fetch_count      <= {SOURCE_ADDR_WIDTH{1'b0}};
                frame_bad        <= 1'b0;
                underflow_seen   <= 1'b0;
                frame_sync_error <= 1'b0;
            end else begin
                if (lcd_vsync_rise) begin
                    fetch_pending <= 1'b1;
                    fetch_row     <= 11'd0;
                end

                // axi4_ctrl在场边界后才复位读FIFO。必须先看到FIFO为空，
                // 防止把上一帧残留计数误认为新一帧第0行已经准备好。
                if (fetch_pending && !in_ddr_valid)
                    fifo_empty_seen <= 1'b1;

                // 当前显示行开始时，上一行必须已经完整写入对应缓存。
                if (lcd_de_rise) begin
                    if ((display_y[0] == 1'b0 &&
                         (!bank0_ready || bank0_row != display_y)) ||
                        (display_y[0] == 1'b1 &&
                         (!bank1_ready || bank1_row != display_y))) begin
                        underflow_seen <= 1'b1;
                    end

                    if (display_y < DISPLAY_HEIGHT - 1) begin
                        if (fetch_pending || fetch_active) begin
                            frame_sync_error <= 1'b1;
                            frame_bad        <= 1'b1;
                        end else begin
                            fetch_pending <= 1'b1;
                            fetch_row     <= display_y + 1'b1;
                        end
                    end
                end

                // 只有FIFO已缓存完整一行时才启动，防止行内断流。
                if (fetch_pending && !fetch_active && fifo_empty_seen &&
                    in_ddr_count >= FIFO_START_LEVEL && !frame_bad) begin
                    fetch_active <= 1'b1;
                    fetch_count  <= {SOURCE_ADDR_WIDTH{1'b0}};
                end

                if (fetch_active) begin
                    if (!in_ddr_valid) begin
                        fetch_active     <= 1'b0;
                        fetch_pending    <= 1'b0;
                        frame_bad        <= 1'b1;
                        underflow_seen   <= 1'b1;
                        frame_sync_error <= 1'b1;
                    end else if (fetch_count == SOURCE_WIDTH - 1) begin
                        fetch_active  <= 1'b0;
                        fetch_pending <= 1'b0;
                        fetch_count   <= {SOURCE_ADDR_WIDTH{1'b0}};
                    end else begin
                        fetch_count <= fetch_count + 1'b1;
                    end
                end
            end
        end
    end

    // HDMI有效区坐标仅由DE统计，保持固定1920×1080节拍。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            display_x <= 11'd0;
            display_y <= 11'd0;
            display_mode_frame <= 1'b0;
        end else if (in_lcd_vsync == VSYNC_ACTIVE_LEVEL) begin
            display_x <= 11'd0;
            display_y <= 11'd0;
        end else begin
            if (lcd_vsync_rise)
                display_mode_frame <= in_display_mode;
            if (in_lcd_de) begin
                if (display_x == DISPLAY_WIDTH - 1)
                    display_x <= 11'd0;
                else
                    display_x <= display_x + 1'b1;
            end else begin
                display_x <= 11'd0;
            end

            if (lcd_de_fall) begin
                if (display_y == DISPLAY_HEIGHT - 1)
                    display_y <= 11'd0;
                else
                    display_y <= display_y + 1'b1;
            end
        end
    end

    // 算法每完成一行便标记对应奇偶缓存可用。
    reg [SOURCE_ADDR_WIDTH-1:0] alg_x;
    reg [10:0] alg_y;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alg_x       <= {SOURCE_ADDR_WIDTH{1'b0}};
            alg_y       <= 11'd0;
            bank0_ready <= 1'b0;
            bank1_ready <= 1'b0;
            bank0_row   <= 11'd0;
            bank1_row   <= 11'd0;
        end else if (in_lcd_vsync == VSYNC_ACTIVE_LEVEL || frame_bad) begin
            alg_x       <= {SOURCE_ADDR_WIDTH{1'b0}};
            alg_y       <= 11'd0;
            bank0_ready <= 1'b0;
            bank1_ready <= 1'b0;
            bank0_row   <= 11'd0;
            bank1_row   <= 11'd0;
        end else if (in_alg_valid) begin
            if (alg_x == SOURCE_WIDTH - 1) begin
                alg_x <= {SOURCE_ADDR_WIDTH{1'b0}};
                if (alg_y[0] == 1'b0) begin
                    bank0_ready <= 1'b1;
                    bank0_row   <= alg_y;
                end else begin
                    bank1_ready <= 1'b1;
                    bank1_row   <= alg_y;
                end

                if (alg_y == DISPLAY_HEIGHT - 1)
                    alg_y <= 11'd0;
                else
                    alg_y <= alg_y + 1'b1;
            end else begin
                alg_x <= alg_x + 1'b1;
            end
        end
    end

    // 两个独立同步读端口符合Efinity片上RAM推断模板。
    reg [40:0] bank0_rdata;
    reg [40:0] bank1_rdata;
    reg        read_ready_d;
    reg        read_bank_d;
    reg        panel_edge_d;
    reg        overlay_mode_d;
    reg        valid_d;
    reg        hsync_d;
    reg        vsync_d;
    localparam [10:0] OVERLAY_X_START = (DISPLAY_WIDTH - SOURCE_WIDTH) / 2;
    localparam [10:0] OVERLAY_X_END   = OVERLAY_X_START + SOURCE_WIDTH;
    wire split_right = !display_mode_frame && (display_x >= SPLIT_X);
    wire overlay_area = display_mode_frame &&
                        (display_x >= OVERLAY_X_START) &&
                        (display_x < OVERLAY_X_END);
    wire [10:0] split_offset = display_x - SOURCE_WIDTH_VALUE;
    wire [10:0] overlay_offset = display_x - OVERLAY_X_START;
    wire [SOURCE_ADDR_WIDTH-1:0] display_addr = (SOURCE_WIDTH == DISPLAY_WIDTH) ?
        display_x[SOURCE_ADDR_WIDTH-1:0] : display_mode_frame ?
        overlay_offset[SOURCE_ADDR_WIDTH-1:0] :
        (split_right ? split_offset[SOURCE_ADDR_WIDTH-1:0] :
                       display_x[SOURCE_ADDR_WIDTH-1:0]);
    wire selected_bank_ready = (display_y[0] == 1'b0) ?
                               (bank0_ready && bank0_row == display_y) :
                               (bank1_ready && bank1_row == display_y);

    always @(posedge clk) begin
        if (in_alg_valid && alg_y[0] == 1'b0)
            line_bank0[alg_x] <= {in_window_valid, in_gray, in_edge, in_overlay_rgb};
        bank0_rdata <= line_bank0[display_addr];
    end

    always @(posedge clk) begin
        if (in_alg_valid && alg_y[0] == 1'b1)
            line_bank1[alg_x] <= {in_window_valid, in_gray, in_edge, in_overlay_rgb};
        bank1_rdata <= line_bank1[display_addr];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_ready_d <= 1'b0;
            read_bank_d  <= 1'b0;
            panel_edge_d <= 1'b0;
            overlay_mode_d <= 1'b0;
            valid_d      <= 1'b0;
            hsync_d      <= 1'b0;
            vsync_d      <= VSYNC_ACTIVE_LEVEL;
        end else begin
            valid_d      <= in_lcd_de;
            hsync_d      <= in_lcd_hsync;
            vsync_d      <= in_lcd_vsync;
            panel_edge_d <= in_lcd_de && split_right;
            overlay_mode_d <= in_lcd_de && display_mode_frame;
            read_ready_d <= in_lcd_de && selected_bank_ready &&
                            (!display_mode_frame || overlay_area);
            read_bank_d  <= display_y[0];
        end
    end

    wire [40:0] read_word = read_bank_d ? bank1_rdata : bank0_rdata;
    assign out_pixel = (!valid_d || !read_ready_d) ? 8'd0 :
                       (panel_edge_d ? read_word[31:24] : read_word[39:32]);
    assign out_rgb = (!valid_d || !read_ready_d) ? 24'd0 :
                     (overlay_mode_d ? read_word[23:0] :
                      (panel_edge_d ? {read_word[31:24],read_word[31:24],read_word[31:24]} :
                                      {read_word[39:32],read_word[39:32],read_word[39:32]}));
    assign out_valid        = valid_d;
    assign out_window_valid = valid_d && read_ready_d && read_word[40];
    assign out_region_edge  = valid_d && panel_edge_d;
    assign out_display_mode = display_mode_frame;
    assign out_hsync        = hsync_d;
    assign out_vsync        = vsync_d;

endmodule
