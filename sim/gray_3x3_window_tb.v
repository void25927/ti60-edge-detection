`timescale 1ns / 1ps

module gray_3x3_window_tb;

    localparam PIXEL_WIDTH = 8;
    localparam IMAGE_WIDTH = 8;
    localparam IMAGE_HEIGHT = 6;

    reg                    clk;
    reg                    rst_n;
    reg  [PIXEL_WIDTH-1:0] in_pixel;
    reg                    in_valid;
    reg                    in_hsync;
    reg                    in_vsync;

    wire [PIXEL_WIDTH-1:0] out_p11;
    wire [PIXEL_WIDTH-1:0] out_p12;
    wire [PIXEL_WIDTH-1:0] out_p13;
    wire [PIXEL_WIDTH-1:0] out_p21;
    wire [PIXEL_WIDTH-1:0] out_p22;
    wire [PIXEL_WIDTH-1:0] out_p23;
    wire [PIXEL_WIDTH-1:0] out_p31;
    wire [PIXEL_WIDTH-1:0] out_p32;
    wire [PIXEL_WIDTH-1:0] out_p33;

    wire                   out_valid;
    wire                   out_window_valid;
    wire                   out_hsync;
    wire                   out_vsync;

    integer errors;
    integer output_row;
    integer output_column;
    integer expected_base;

    // 三级参考延迟，用于检查控制信号
    reg [2:0] expected_valid_delay;
    reg [2:0] expected_hsync_delay;
    reg [2:0] expected_vsync_delay;

    gray_3x3_window
    #(
        .PIXEL_WIDTH        (PIXEL_WIDTH),
        .IMAGE_WIDTH        (IMAGE_WIDTH),
        .ADDR_WIDTH         (4),
        .VSYNC_ACTIVE_LEVEL (1'b0)
    )
    dut
    (
        .clk              (clk),
        .rst_n            (rst_n),
        .in_pixel         (in_pixel),
        .in_valid         (in_valid),
        .in_hsync         (in_hsync),
        .in_vsync         (in_vsync),

        .out_p11          (out_p11),
        .out_p12          (out_p12),
        .out_p13          (out_p13),
        .out_p21          (out_p21),
        .out_p22          (out_p22),
        .out_p23          (out_p23),
        .out_p31          (out_p31),
        .out_p32          (out_p32),
        .out_p33          (out_p33),

        .out_valid        (out_valid),
        .out_window_valid (out_window_valid),
        .out_hsync        (out_hsync),
        .out_vsync        (out_vsync)
    );

    always #5 clk = ~clk;

    // 生成递增测试图像
    function [7:0] make_pixel;
        input integer base_value;
        input integer row_index;
        input integer column_index;
        begin
            make_pixel = base_value +
                         row_index * IMAGE_WIDTH +
                         column_index;
        end
    endfunction

    task check_pixel;
        input [7:0] actual;
        input [7:0] expected;
        input integer pixel_number;
        begin
            if (actual !== expected) begin
                $display(
                    "ERROR: p%0d actual=%0d expected=%0d time=%0t",
                    pixel_number, actual, expected, $time
                );
                errors = errors + 1;
            end
        end
    endtask

    // 建立独立的三级控制信号参考模型
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            expected_valid_delay <= 3'b000;
            expected_hsync_delay <= 3'b000;
            expected_vsync_delay <= 3'b000;
        end
        else begin
            expected_valid_delay <= {expected_valid_delay[1:0], in_valid};
            expected_hsync_delay <= {expected_hsync_delay[1:0], in_hsync};
            expected_vsync_delay <= {expected_vsync_delay[1:0], in_vsync};
        end
    end

    // 在下降沿检查，避开时序逻辑的非阻塞赋值更新区
    always @(negedge clk) begin
        if (rst_n) begin
            if (out_valid !== expected_valid_delay[2]) begin
                $display("ERROR: out_valid delay time=%0t", $time);
                errors = errors + 1;
            end

            if (out_hsync !== expected_hsync_delay[2]) begin
                $display("ERROR: out_hsync delay time=%0t", $time);
                errors = errors + 1;
            end

            if (out_vsync !== expected_vsync_delay[2]) begin
                $display("ERROR: out_vsync delay time=%0t", $time);
                errors = errors + 1;
            end

            // 场同步到来时重新统计输出图像坐标
            if (out_vsync == 1'b0) begin
                output_row    = 0;
                output_column = 0;
            end
            else if (out_valid) begin
                if (out_window_valid !==
                    ((output_row >= 2) && (output_column >= 2))) begin
                    $display(
                        "ERROR: window_valid row=%0d col=%0d time=%0t",
                        output_row, output_column, $time
                    );
                    errors = errors + 1;
                end

                if ((output_row >= 2) && (output_column >= 2)) begin
                    check_pixel(
                        out_p11,
                        make_pixel(expected_base,
                                   output_row-2, output_column-2),
                        11
                    );
                    check_pixel(
                        out_p12,
                        make_pixel(expected_base,
                                   output_row-2, output_column-1),
                        12
                    );
                    check_pixel(
                        out_p13,
                        make_pixel(expected_base,
                                   output_row-2, output_column),
                        13
                    );
                    check_pixel(
                        out_p21,
                        make_pixel(expected_base,
                                   output_row-1, output_column-2),
                        21
                    );
                    check_pixel(
                        out_p22,
                        make_pixel(expected_base,
                                   output_row-1, output_column-1),
                        22
                    );
                    check_pixel(
                        out_p23,
                        make_pixel(expected_base,
                                   output_row-1, output_column),
                        23
                    );
                    check_pixel(
                        out_p31,
                        make_pixel(expected_base,
                                   output_row, output_column-2),
                        31
                    );
                    check_pixel(
                        out_p32,
                        make_pixel(expected_base,
                                   output_row, output_column-1),
                        32
                    );
                    check_pixel(
                        out_p33,
                        make_pixel(expected_base,
                                   output_row, output_column),
                        33
                    );
                end

                if (output_column == IMAGE_WIDTH - 1) begin
                    output_column = 0;
                    output_row    = output_row + 1;
                end
                else begin
                    output_column = output_column + 1;
                end
            end
        end
    end

    task drive_blank;
        input hsync_value;
        input vsync_value;
        input integer cycle_count;
        integer cycle_index;
        begin
            for (cycle_index = 0;
                 cycle_index < cycle_count;
                 cycle_index = cycle_index + 1) begin
                @(negedge clk);
                in_pixel = 8'd0;
                in_valid = 1'b0;
                in_hsync = hsync_value;
                in_vsync = vsync_value;
            end
        end
    endtask

    task drive_frame;
        input integer base_value;
        integer row_index;
        integer column_index;
        begin
            expected_base = base_value;

            // 低电平场同步，然后进入场消隐
            drive_blank(1'b1, 1'b0, 4);
            drive_blank(1'b1, 1'b1, 4);

            for (row_index = 0;
                 row_index < IMAGE_HEIGHT;
                 row_index = row_index + 1) begin

                for (column_index = 0;
                     column_index < IMAGE_WIDTH;
                     column_index = column_index + 1) begin
                    @(negedge clk);
                    in_pixel = make_pixel(
                        base_value, row_index, column_index
                    );
                    in_valid = 1'b1;
                    in_hsync = 1'b1;
                    in_vsync = 1'b1;
                end

                // 行同步和行消隐
                drive_blank(1'b0, 1'b1, 2);
                drive_blank(1'b1, 1'b1, 2);
            end

            drive_blank(1'b1, 1'b1, 6);
        end
    endtask

    initial begin
        clk                  = 1'b0;
        rst_n                = 1'b0;
        in_pixel             = 8'd0;
        in_valid             = 1'b0;
        in_hsync             = 1'b0;
        in_vsync             = 1'b0;
        errors               = 0;
        output_row           = 0;
        output_column        = 0;
        expected_base        = 0;
        expected_valid_delay = 3'b000;
        expected_hsync_delay = 3'b000;
        expected_vsync_delay = 3'b000;

        repeat (4) @(posedge clk);

        @(negedge clk);
        rst_n = 1'b1;

        drive_frame(0);

        // 异步复位检查
        #2 rst_n = 1'b0;
        #1;
        if ((out_valid !== 1'b0) ||
            (out_window_valid !== 1'b0) ||
            (out_p33 !== 8'd0)) begin
            $display("ERROR: asynchronous reset");
            errors = errors + 1;
        end

        repeat (3) @(posedge clk);

        @(negedge clk);
        rst_n = 1'b1;

        drive_frame(100);
        drive_blank(1'b1, 1'b0, 5);

        if (errors == 0)
            $display("TEST PASSED: gray_3x3_window");
        else
            $display(
                "TEST FAILED: gray_3x3_window, %0d error(s)",
                errors
            );

        $finish;
    end

endmodule
