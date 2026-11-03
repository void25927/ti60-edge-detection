`timescale 1ns / 1ps

// 从32位RAW8视频流中截取每行中央区域。
// 每个有效时钟包含4个连续像素，模块不改变组内字节顺序。
module mipi_center_crop_32 #(
    parameter integer INPUT_WIDTH  = 1920, // 输入行宽，单位：像素
    parameter integer CROP_X       = 480,  // 裁剪区左边界，单位：像素
    parameter integer OUTPUT_WIDTH = 960   // 裁剪后行宽，单位：像素
)(
    input  wire        clk,        // MIPI接收时钟
    input  wire        rst_n,      // 低电平异步复位
    input  wire [31:0] in_data,    // 4个连续RAW8像素，顺序保持不变
    input  wire        in_valid,   // 输入数据组有效，高电平有效
    input  wire        in_hsync,   // 输入行有效，高电平有效
    input  wire        in_vsync,   // 输入帧有效，高电平有效
    output wire [31:0] out_data,   // 裁剪后的4像素数据组
    output wire        out_valid,  // 裁剪区数据组有效，高电平有效
    output wire        out_hsync,  // 裁剪后行有效，高电平有效
    output wire        out_vsync   // 帧有效，极性与输入一致
);

    localparam integer PIXELS_PER_BEAT = 4; // 32位RAW8每拍像素数
    localparam integer INPUT_GROUPS  = INPUT_WIDTH / PIXELS_PER_BEAT;
    localparam integer CROP_GROUP    = CROP_X / PIXELS_PER_BEAT;
    localparam integer OUTPUT_GROUPS = OUTPUT_WIDTH / PIXELS_PER_BEAT;

    reg [15:0] group_count; // 当前输入行的数据组编号

    wire input_accept = rst_n && in_valid && in_hsync;
    wire group_in_crop = (group_count >= CROP_GROUP) &&
                         (group_count < CROP_GROUP + OUTPUT_GROUPS);

    // 参数必须按4像素边界对齐，避免拆分MIPI数据组。
    initial begin
        if ((INPUT_WIDTH % PIXELS_PER_BEAT) != 0 ||
            (CROP_X % PIXELS_PER_BEAT) != 0 ||
            (OUTPUT_WIDTH % PIXELS_PER_BEAT) != 0 ||
            (CROP_X + OUTPUT_WIDTH > INPUT_WIDTH)) begin
            $display("ERROR: mipi_center_crop_32 parameter alignment error");
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            group_count <= 16'd0;
        end else if (!in_vsync || !in_hsync) begin
            group_count <= 16'd0;
        end else if (input_accept) begin
            if (group_count == INPUT_GROUPS - 1)
                group_count <= 16'd0;
            else
                group_count <= group_count + 1'b1;
        end
    end

    assign out_data  = in_data;
    assign out_valid = input_accept && group_in_crop;
    assign out_hsync = out_valid;
    assign out_vsync = in_vsync;

endmodule
