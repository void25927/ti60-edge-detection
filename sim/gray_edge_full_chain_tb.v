`timescale 1ns / 1ps

// 显示控制、去马赛克和边缘流水线联合诊断。
// 重点检查一行960个RAW8像素经过完整算法后，显示缓存能否按时就绪。
module gray_edge_full_chain_tb;
    localparam integer SOURCE_WIDTH  = 960;
    localparam integer DISPLAY_WIDTH = 1920;
    localparam integer TEST_HEIGHT   = 4;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg lcd_de = 1'b0;
    reg lcd_hsync = 1'b1;
    reg lcd_vsync = 1'b0;

    reg [7:0] ddr_data = 8'd0;
    reg ddr_available = 1'b1;
    wire [12:0] ddr_count = ddr_available ? 13'd4096 : 13'd0;
    wire ddr_valid = ddr_available;
    wire ddr_request;

    wire [7:0] source_raw;
    wire source_valid;
    wire source_hsync;
    wire source_vsync;
    wire [7:0] rgb_r;
    wire [7:0] rgb_g;
    wire [7:0] rgb_b;
    wire rgb_valid;
    wire rgb_hsync;
    wire rgb_vsync;
    wire [7:0] alg_gray;
    wire [7:0] alg_edge;
    wire [7:0] alg_red,alg_green,alg_blue;
    wire alg_valid;
    wire alg_window_valid;
    wire alg_hsync;
    wire alg_vsync;
    wire [7:0] display_pixel;
    wire [23:0] display_rgb;
    wire display_valid;
    wire display_window_valid;
    wire display_region_edge;
    wire display_mode_active;
    wire display_hsync;
    wire display_vsync;
    wire underflow_seen;
    wire frame_sync_error;
    wire [7:0] overlay_red,overlay_green,overlay_blue;
    wire overlay_valid,overlay_hsync,overlay_vsync;
    reg [7:0] alg_gray_d=0,alg_edge_d=0;
    reg alg_window_valid_d=0;

    integer errors = 0;
    integer source_x = 0;
    integer source_y = 0;
    integer output_count = 0;
    integer nonzero_count = 0;
    integer row;
    integer x;

    always #3.367 clk = ~clk;

    always @(posedge clk) begin
        if (!rst_n || !lcd_vsync) begin
            source_x <= 0;
            source_y <= 0;
            ddr_data <= 8'd1;
        end else if (ddr_request) begin
            ddr_data <= ((source_y * 13 + source_x * 7) & 8'hff) | 8'h01;
            if (source_x == SOURCE_WIDTH - 1) begin
                source_x <= 0;
                source_y <= source_y + 1;
            end else begin
                source_x <= source_x + 1;
            end
        end
    end

    VIP_RAW8_RGB888 #(
        .IMG_HDISP(SOURCE_WIDTH),
        .IMG_VDISP(TEST_HEIGHT)
    ) u_bayer2rgb (
        .clk(clk), .rst_n(rst_n), .mirror(2'b00),
        .per_frame_vsync(source_vsync),
        .per_frame_href(source_valid),
        .per_frame_hsync(source_hsync),
        .per_img_RAW(source_raw),
        .post_frame_vsync(rgb_vsync),
        .post_frame_href(rgb_valid),
        .post_frame_hsync(rgb_hsync),
        .post_img_red(rgb_r), .post_img_green(rgb_g), .post_img_blue(rgb_b)
    );

    edge_video_pipeline #(
        .IMAGE_WIDTH(SOURCE_WIDTH),
        .ADDR_WIDTH(10),
        .THRESHOLD(11'd128),
        .EDGE_MODE(0),
        .VSYNC_ACTIVE_LEVEL(1'b0)
    ) u_pipeline (
        .clk(clk), .rst_n(rst_n),
        .in_red(rgb_r), .in_green(rgb_g), .in_blue(rgb_b),
        .in_valid(rgb_valid), .in_hsync(rgb_hsync), .in_vsync(rgb_vsync),
        .in_high_threshold(11'd80),.in_low_threshold(11'd40),
        .in_median_enable(1'b1),.in_canny_enable(1'b1),
        .out_red(alg_red),.out_green(alg_green),.out_blue(alg_blue),
        .out_gray(alg_gray), .out_edge(alg_edge),
        .out_valid(alg_valid), .out_window_valid(alg_window_valid),
        .out_hsync(alg_hsync), .out_vsync(alg_vsync)
    );

    edge_overlay u_overlay (
        .clk(clk),.rst_n(rst_n),.in_valid(alg_valid),
        .in_hsync(alg_hsync),.in_vsync(alg_vsync),
        .in_red(alg_red),.in_green(alg_green),.in_blue(alg_blue),
        .in_edge(|alg_edge),.out_valid(overlay_valid),
        .out_hsync(overlay_hsync),.out_vsync(overlay_vsync),
        .out_red(overlay_red),.out_green(overlay_green),.out_blue(overlay_blue)
    );

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            alg_gray_d<=0;alg_edge_d<=0;alg_window_valid_d<=0;
        end else begin
            alg_gray_d<=alg_gray;alg_edge_d<=alg_edge;
            alg_window_valid_d<=alg_window_valid;
        end
    end

    gray_edge_display #(
        .SOURCE_WIDTH(SOURCE_WIDTH),
        .DISPLAY_WIDTH(DISPLAY_WIDTH),
        .DISPLAY_HEIGHT(TEST_HEIGHT),
        .FIFO_START_LEVEL(SOURCE_WIDTH),
        .VSYNC_ACTIVE_LEVEL(1'b0)
    ) u_display (
        .clk(clk), .rst_n(rst_n),
        .in_lcd_de(lcd_de), .in_lcd_hsync(lcd_hsync), .in_lcd_vsync(lcd_vsync),
        .in_display_mode(1'b0),
        .in_ddr_data(ddr_data), .in_ddr_valid(ddr_valid), .in_ddr_count(ddr_count),
        .out_ddr_request(ddr_request),
        .out_source_raw(source_raw), .out_source_valid(source_valid),
        .out_source_hsync(source_hsync), .out_source_vsync(source_vsync),
        .in_gray(alg_gray_d), .in_edge(alg_edge_d),
        .in_overlay_rgb({overlay_red,overlay_green,overlay_blue}),
        .in_alg_valid(overlay_valid), .in_window_valid(alg_window_valid_d),
        .out_pixel(display_pixel), .out_rgb(display_rgb), .out_valid(display_valid),
        .out_window_valid(display_window_valid), .out_region_edge(display_region_edge),
        .out_display_mode(display_mode_active),
        .out_hsync(display_hsync), .out_vsync(display_vsync),
        .underflow_seen(underflow_seen), .frame_sync_error(frame_sync_error)
    );

    always @(negedge clk) begin
        if (display_valid) begin
            output_count = output_count + 1;
            if (display_rgb != 24'd0)
                nonzero_count = nonzero_count + 1;
        end
    end

    initial begin
        repeat (8) @(posedge clk);
        rst_n = 1'b1;

        // 低有效场同步结束后留出完整后沿时间预取第0行。
        repeat (16) @(posedge clk);
        lcd_vsync = 1'b1;
        // 模拟axi4_ctrl在新帧开始后清空读FIFO，再装入新帧数据。
        repeat (4) @(posedge clk);
        ddr_available = 1'b0;
        repeat (4) @(posedge clk);
        ddr_available = 1'b1;
        repeat (2200 * 6) @(posedge clk);

        for (row = 0; row < TEST_HEIGHT; row = row + 1) begin
            lcd_de = 1'b1;
            for (x = 0; x < DISPLAY_WIDTH; x = x + 1)
                @(posedge clk);
            lcd_de = 1'b0;
            repeat (280) @(posedge clk);
        end

        repeat (32) @(posedge clk);
        if (output_count != DISPLAY_WIDTH * TEST_HEIGHT) begin
            errors = errors + 1;
            $display("ERROR: display count=%0d", output_count);
        end
        if (nonzero_count == 0) begin
            errors = errors + 1;
            $display("ERROR: full chain produced only black pixels");
        end
        if (underflow_seen || frame_sync_error) begin
            errors = errors + 1;
            $display("ERROR: underflow=%b frame_error=%b", underflow_seen, frame_sync_error);
        end

        if (errors == 0)
            $display("TEST PASSED: gray_edge_full_chain, nonzero=%0d", nonzero_count);
        else
            $display("TEST FAILED: gray_edge_full_chain, %0d error(s)", errors);
        $finish;
    end

    initial begin
        #2000000;
        $display("TEST FAILED: gray_edge_full_chain timeout");
        $finish;
    end
endmodule
