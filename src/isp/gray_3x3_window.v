`timescale 1ns / 1ps

// 3x3灰度滑动窗口
// 两级同步读行缓存分别保存上一行和前两行像素。
module gray_3x3_window
#(
    parameter integer PIXEL_WIDTH = 8,        // 灰度像素位宽
    parameter integer IMAGE_WIDTH = 1920,     // 每行有效像素数
    parameter integer ADDR_WIDTH  = 11,       // 行缓存地址位宽
    parameter         VSYNC_ACTIVE_LEVEL = 1'b0
                                                 // 场同步有效电平
)
(
    input  wire                    clk,        // 像素时钟
    input  wire                    rst_n,      // 低电平异步复位

    input  wire [PIXEL_WIDTH-1:0]  in_pixel,   // 输入灰度像素
    input  wire                    in_valid,   // 输入像素有效
    input  wire                    in_hsync,   // 输入行同步
    input  wire                    in_vsync,   // 输入场同步

    output reg  [PIXEL_WIDTH-1:0]  out_p11,
    output reg  [PIXEL_WIDTH-1:0]  out_p12,
    output reg  [PIXEL_WIDTH-1:0]  out_p13,
    output reg  [PIXEL_WIDTH-1:0]  out_p21,
    output reg  [PIXEL_WIDTH-1:0]  out_p22,
    output reg  [PIXEL_WIDTH-1:0]  out_p23,
    output reg  [PIXEL_WIDTH-1:0]  out_p31,
    output reg  [PIXEL_WIDTH-1:0]  out_p32,
    output reg  [PIXEL_WIDTH-1:0]  out_p33,

    output reg                     out_valid,
    output reg                     out_window_valid,
    output reg                     out_hsync,
    output reg                     out_vsync
);

    // 输入有效区域的坐标
    reg [15:0] input_column;
    reg [15:0] input_row;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_column <= 16'd0;
            input_row    <= 16'd0;
        end
        else if (in_vsync == VSYNC_ACTIVE_LEVEL) begin
            input_column <= 16'd0;
            input_row    <= 16'd0;
        end
        else if (in_valid) begin
            if (input_column == IMAGE_WIDTH - 1) begin
                input_column <= 16'd0;
                if (input_row != 16'hffff)
                    input_row <= input_row + 1'b1;
            end
            else begin
                input_column <= input_column + 1'b1;
            end
        end
    end

    // 第一级流水保存当前输入及其坐标
    reg [PIXEL_WIDTH-1:0] stage1_pixel;
    reg [15:0]            stage1_column;
    reg [15:0]            stage1_row;
    reg                   stage1_valid;
    reg                   stage1_hsync;
    reg                   stage1_vsync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_pixel  <= {PIXEL_WIDTH{1'b0}};
            stage1_column <= 16'd0;
            stage1_row    <= 16'd0;
            stage1_valid  <= 1'b0;
            stage1_hsync  <= 1'b0;
            stage1_vsync  <= 1'b0;
        end
        else begin
            stage1_valid <= in_valid;
            stage1_hsync <= in_hsync;
            stage1_vsync <= in_vsync;

            if (in_valid) begin
                stage1_pixel  <= in_pixel;
                stage1_column <= input_column;
                stage1_row    <= input_row;
            end
        end
    end

    // 第一行缓存输出上一行同列像素
    wire [PIXEL_WIDTH-1:0] previous_row_pixel;

    gray_line_buffer_sync
    #(
        .DATA_WIDTH (PIXEL_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    )
    u_line_buffer_1
    (
        .clk      (clk),
        .rst_n    (rst_n),
        .clear    (in_vsync == VSYNC_ACTIVE_LEVEL),
        .enable   (in_valid),
        .data_in  (in_pixel),
        .data_out (previous_row_pixel)
    );

    // 第二行缓存输出前两行同列像素
    wire [PIXEL_WIDTH-1:0] two_rows_pixel;

    gray_line_buffer_sync
    #(
        .DATA_WIDTH (PIXEL_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    )
    u_line_buffer_2
    (
        .clk      (clk),
        .rst_n    (rst_n),
        .clear    (stage1_vsync == VSYNC_ACTIVE_LEVEL),
        .enable   (stage1_valid),
        .data_in  (previous_row_pixel),
        .data_out (two_rows_pixel)
    );

    // 第二级流水对齐当前行和上一行像素
    reg [PIXEL_WIDTH-1:0] stage2_current_pixel;
    reg [PIXEL_WIDTH-1:0] stage2_previous_pixel;
    reg [15:0]            stage2_column;
    reg [15:0]            stage2_row;
    reg                   stage2_valid;
    reg                   stage2_hsync;
    reg                   stage2_vsync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage2_current_pixel  <= {PIXEL_WIDTH{1'b0}};
            stage2_previous_pixel <= {PIXEL_WIDTH{1'b0}};
            stage2_column         <= 16'd0;
            stage2_row            <= 16'd0;
            stage2_valid          <= 1'b0;
            stage2_hsync          <= 1'b0;
            stage2_vsync          <= 1'b0;
        end
        else begin
            stage2_valid <= stage1_valid;
            stage2_hsync <= stage1_hsync;
            stage2_vsync <= stage1_vsync;

            if (stage1_valid) begin
                stage2_current_pixel  <= stage1_pixel;
                stage2_previous_pixel <= previous_row_pixel;
                stage2_column         <= stage1_column;
                stage2_row            <= stage1_row;
            end
        end
    end

    // 第三级流水形成三行三列窗口
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_p11 <= {PIXEL_WIDTH{1'b0}};
            out_p12 <= {PIXEL_WIDTH{1'b0}};
            out_p13 <= {PIXEL_WIDTH{1'b0}};
            out_p21 <= {PIXEL_WIDTH{1'b0}};
            out_p22 <= {PIXEL_WIDTH{1'b0}};
            out_p23 <= {PIXEL_WIDTH{1'b0}};
            out_p31 <= {PIXEL_WIDTH{1'b0}};
            out_p32 <= {PIXEL_WIDTH{1'b0}};
            out_p33 <= {PIXEL_WIDTH{1'b0}};

            out_valid        <= 1'b0;
            out_window_valid <= 1'b0;
            out_hsync        <= 1'b0;
            out_vsync        <= 1'b0;
        end
        else begin
            out_valid <= stage2_valid;
            out_hsync <= stage2_hsync;
            out_vsync <= stage2_vsync;

            out_window_valid <=
                stage2_valid &&
                (stage2_row >= 16'd2) &&
                (stage2_column >= 16'd2);

            if (stage2_valid) begin
                // 行首清空横向历史，防止上一行数据串入下一行。
                if (stage2_column == 16'd0) begin
                    out_p11 <= {PIXEL_WIDTH{1'b0}};
                    out_p12 <= {PIXEL_WIDTH{1'b0}};
                    out_p13 <= two_rows_pixel;

                    out_p21 <= {PIXEL_WIDTH{1'b0}};
                    out_p22 <= {PIXEL_WIDTH{1'b0}};
                    out_p23 <= stage2_previous_pixel;

                    out_p31 <= {PIXEL_WIDTH{1'b0}};
                    out_p32 <= {PIXEL_WIDTH{1'b0}};
                    out_p33 <= stage2_current_pixel;
                end
                else begin
                    out_p11 <= out_p12;
                    out_p12 <= out_p13;
                    out_p13 <= two_rows_pixel;

                    out_p21 <= out_p22;
                    out_p22 <= out_p23;
                    out_p23 <= stage2_previous_pixel;

                    out_p31 <= out_p32;
                    out_p32 <= out_p33;
                    out_p33 <= stage2_current_pixel;
                end
            end
            // 无效拍保持横向历史；下一行第0列会重新初始化窗口。
        end
    end

endmodule


// 单行同步读缓存
// 读写地址相同，读取旧数据的同时写入当前像素。
module gray_line_buffer_sync
#(
    parameter integer DATA_WIDTH  = 8,
    parameter integer IMAGE_WIDTH = 1920,
    parameter integer ADDR_WIDTH  = 11
)
(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  clear,  // 场同步时归零地址，不复位RAM内容
    input  wire                  enable,
    input  wire [DATA_WIDTH-1:0] data_in,
    output reg  [DATA_WIDTH-1:0] data_out
);

    localparam integer RAM_DEPTH = (1 << ADDR_WIDTH);

    reg [ADDR_WIDTH-1:0] address;
    reg [DATA_WIDTH-1:0] memory [0:RAM_DEPTH-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            address <= {ADDR_WIDTH{1'b0}};
        else if (clear)
            address <= {ADDR_WIDTH{1'b0}};
        else if (enable) begin
            if (address == IMAGE_WIDTH - 1)
                address <= {ADDR_WIDTH{1'b0}};
            else
                address <= address + 1'b1;
        end
    end

    // 同步写端口
    always @(posedge clk) begin
        if (enable && !clear)
            memory[address] <= data_in;
    end

    // 同步读端口；同地址读写时取得写入前的数据。
    always @(posedge clk) begin
        if (enable && !clear)
            data_out <= memory[address];
    end

endmodule
