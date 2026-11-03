`timescale 1ns / 1ps

// 二值图像3x3形态学基本单元。
// OPERATION=0：膨胀；OPERATION=1：腐蚀。
// KERNEL_SHAPE=0：十字结构元；KERNEL_SHAPE=1：完整3x3方形结构元。
//
// 为节省Ti60片上RAM，边缘窗口只缓存边缘及有效标志共2 bit；RGB、灰度和上游窗口有效标志
// 通过一个IMAGE_WIDTH+1像素的环形延迟缓存与窗口中心p22对齐。相比把33 bit
// 负载复制到两条窗口行缓存，本实现约减少一半的负载缓存位数。
module binary_morphology_3x3 #(
    parameter integer IMAGE_WIDTH = 1920,
    parameter integer ADDR_WIDTH = 11,
    parameter integer OPERATION = 0,
    parameter integer KERNEL_SHAPE = 1,
    parameter VSYNC_ACTIVE_LEVEL = 1'b0
)(
    input  wire clk,
    input  wire rst_n,
    input  wire in_edge,
    input  wire [7:0] in_red,
    input  wire [7:0] in_green,
    input  wire [7:0] in_blue,
    input  wire [7:0] in_gray,
    input  wire in_valid,
    input  wire in_window_valid,
    input  wire in_hsync,
    input  wire in_vsync,
    output wire out_edge,
    output wire [7:0] out_red,
    output wire [7:0] out_green,
    output wire [7:0] out_blue,
    output wire [7:0] out_gray,
    output wire out_valid,
    output wire out_window_valid,
    output wire out_hsync,
    output wire out_vsync
);
    localparam integer PAYLOAD_WIDTH = 33;
    localparam integer CENTER_DELAY = IMAGE_WIDTH + 1;
    localparam integer DELAY_ADDR_WIDTH = ADDR_WIDTH + 1;

    wire [1:0] w11,w12,w13,w21,w22,w23,w31,w32,w33;
    wire window_valid;
    wire window_ready;
    wire window_hsync;
    wire window_vsync;

    // 上游无效边界按背景处理，避免旧行缓存中的边缘污染形态学窗口。
    gray_3x3_window #(
        .PIXEL_WIDTH(2),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .VSYNC_ACTIVE_LEVEL(VSYNC_ACTIVE_LEVEL)
    ) u_edge_window (
        .clk(clk),.rst_n(rst_n),
        .in_pixel({in_window_valid,in_edge && in_window_valid}),
        .in_valid(in_valid),.in_hsync(in_hsync),.in_vsync(in_vsync),
        .out_p11(w11),.out_p12(w12),.out_p13(w13),
        .out_p21(w21),.out_p22(w22),.out_p23(w23),
        .out_p31(w31),.out_p32(w32),.out_p33(w33),
        .out_valid(window_valid),.out_window_valid(window_ready),
        .out_hsync(window_hsync),.out_vsync(window_vsync)
    );

    wire dilate_cross = w12[0] || w21[0] || w22[0] || w23[0] || w32[0];
    wire erode_cross  = w12[0] && w21[0] && w22[0] && w23[0] && w32[0];
    wire dilate_square = w11[0] || w12[0] || w13[0] || w21[0] || w22[0] ||
                         w23[0] || w31[0] || w32[0] || w33[0];
    wire erode_square  = w11[0] && w12[0] && w13[0] && w21[0] && w22[0] &&
                         w23[0] && w31[0] && w32[0] && w33[0];
    wire all_input_window_valid =
        w11[1] && w12[1] && w13[1] && w21[1] && w22[1] &&
        w23[1] && w31[1] && w32[1] && w33[1];
    wire morphology_edge = (OPERATION == 0) ?
        (KERNEL_SHAPE == 0 ? dilate_cross : dilate_square) :
        (KERNEL_SHAPE == 0 ? erode_cross : erode_square);

    // 环形缓存产生IMAGE_WIDTH+1个有效像素的空间延迟，即窗口中心相对
    // 当前右下角的一行一列延迟。read_ready阻止跨帧旧数据成为有效负载。
    reg [PAYLOAD_WIDTH-1:0] payload_memory [0:CENTER_DELAY-1];
    reg [DELAY_ADDR_WIDTH-1:0] payload_address;
    reg [DELAY_ADDR_WIDTH:0] payload_fill_count;
    reg [PAYLOAD_WIDTH-1:0] payload_read;
    reg [PAYLOAD_WIDTH-1:0] payload_delay;
    reg [PAYLOAD_WIDTH-1:0] payload_center;
    reg payload_read_ready;
    reg payload_delay_ready;
    reg payload_center_ready;

    wire [PAYLOAD_WIDTH-1:0] input_payload =
        {in_window_valid,in_red,in_green,in_blue,in_gray};

    // RAM读写端口不带复位，使Efinity推断同步读、read-first的片上RAM。
    // 复位及帧切换后的旧数据由下方ready流水线屏蔽。
    always @(posedge clk) begin
        if (rst_n && in_vsync != VSYNC_ACTIVE_LEVEL && in_valid) begin
            payload_read <= payload_memory[payload_address];
            payload_memory[payload_address] <= input_payload;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            payload_address <= {DELAY_ADDR_WIDTH{1'b0}};
            payload_fill_count <= {(DELAY_ADDR_WIDTH+1){1'b0}};
            payload_delay <= {PAYLOAD_WIDTH{1'b0}};
            payload_center <= {PAYLOAD_WIDTH{1'b0}};
            payload_read_ready <= 1'b0;
            payload_delay_ready <= 1'b0;
            payload_center_ready <= 1'b0;
        end else if (in_vsync == VSYNC_ACTIVE_LEVEL) begin
            payload_address <= {DELAY_ADDR_WIDTH{1'b0}};
            payload_fill_count <= {(DELAY_ADDR_WIDTH+1){1'b0}};
            payload_delay <= {PAYLOAD_WIDTH{1'b0}};
            payload_center <= {PAYLOAD_WIDTH{1'b0}};
            payload_read_ready <= 1'b0;
            payload_delay_ready <= 1'b0;
            payload_center_ready <= 1'b0;
        end else begin
            payload_delay <= payload_read;
            payload_center <= payload_delay;
            payload_delay_ready <= payload_read_ready;
            payload_center_ready <= payload_delay_ready;

            payload_read_ready <= 1'b0;
            if (in_valid) begin
                payload_read_ready <= (payload_fill_count >= CENTER_DELAY);

                if (payload_fill_count < CENTER_DELAY)
                    payload_fill_count <= payload_fill_count + 1'b1;

                if (payload_address == CENTER_DELAY - 1)
                    payload_address <= {DELAY_ADDR_WIDTH{1'b0}};
                else
                    payload_address <= payload_address + 1'b1;
            end
        end
    end

    wire center_window_valid = payload_center[32];
    wire output_window_valid = window_valid && window_ready &&
                               payload_center_ready && center_window_valid &&
                               all_input_window_valid;

    assign out_edge = output_window_valid ? morphology_edge : 1'b0;
    assign out_red = (window_valid && payload_center_ready) ? payload_center[31:24] : 8'd0;
    assign out_green = (window_valid && payload_center_ready) ? payload_center[23:16] : 8'd0;
    assign out_blue = (window_valid && payload_center_ready) ? payload_center[15:8] : 8'd0;
    assign out_gray = (window_valid && payload_center_ready) ? payload_center[7:0] : 8'd0;
    assign out_valid = window_valid;
    assign out_window_valid = output_window_valid;
    assign out_hsync = window_hsync;
    assign out_vsync = window_vsync;
endmodule
