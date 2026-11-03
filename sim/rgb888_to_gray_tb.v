`timescale 1ns / 1ps

module rgb888_to_gray_tb;

    // 输入信号
    reg        clk;
    reg        rst_n;
    reg  [7:0] in_red;
    reg  [7:0] in_green;
    reg  [7:0] in_blue;
    reg        in_valid;
    reg        in_hsync;
    reg        in_vsync;

    // 输出信号
    wire [7:0] out_gray;
    wire       out_valid;
    wire       out_hsync;
    wire       out_vsync;

    // 自检统计
    integer error_count;
    integer check_count;
    integer test_index;
    integer random_seed;

    reg [7:0] random_red;
    reg [7:0] random_green;
    reg [7:0] random_blue;

    rgb888_to_gray dut
    (
        .clk       (clk),
        .rst_n     (rst_n),

        .in_red    (in_red),
        .in_green  (in_green),
        .in_blue   (in_blue),
        .in_valid  (in_valid),
        .in_hsync  (in_hsync),
        .in_vsync  (in_vsync),

        .out_gray  (out_gray),
        .out_valid (out_valid),
        .out_hsync (out_hsync),
        .out_vsync (out_vsync)
    );

    // 100MHz仿真时钟，周期10ns
    always #5 clk = ~clk;

    // 独立参考函数
    function [7:0] reference_gray;
        input [7:0] red_value;
        input [7:0] green_value;
        input [7:0] blue_value;

        integer sum_value;
        begin
            sum_value =
                red_value   * 77 +
                green_value * 150 +
                blue_value  * 29;

            reference_gray = sum_value >> 8;
        end
    endfunction

    // 检查一次输出
    task check_output;
        input [7:0] expected_gray;
        input       expected_valid;
        input       expected_hsync;
        input       expected_vsync;

        begin
            check_count = check_count + 1;

            if ((out_gray  !== expected_gray)  ||
                (out_valid !== expected_valid) ||
                (out_hsync !== expected_hsync) ||
                (out_vsync !== expected_vsync)) begin

                error_count = error_count + 1;

                $display(
                    "ERROR: time=%0t gray=%0d expected=%0d valid=%b expected=%b hsync=%b expected=%b vsync=%b expected=%b",
                    $time,
                    out_gray,
                    expected_gray,
                    out_valid,
                    expected_valid,
                    out_hsync,
                    expected_hsync,
                    out_vsync,
                    expected_vsync
                );
            end
        end
    endtask

    // 输入一组像素，并在下一上升沿检查输出
    task send_and_check;
        input [7:0] test_red;
        input [7:0] test_green;
        input [7:0] test_blue;
        input       test_valid;
        input       test_hsync;
        input       test_vsync;

        reg [7:0] expected_gray;

        begin
            @(negedge clk);

            in_red   = test_red;
            in_green = test_green;
            in_blue  = test_blue;
            in_valid = test_valid;
            in_hsync = test_hsync;
            in_vsync = test_vsync;

            if (test_valid)
                expected_gray = reference_gray(
                    test_red,
                    test_green,
                    test_blue
                );
            else
                expected_gray = 8'd0;

            @(posedge clk);
            #1;

            check_output(
                expected_gray,
                test_valid,
                test_hsync,
                test_vsync
            );
        end
    endtask

    initial begin
        clk          = 1'b0;
        rst_n        = 1'b1;
        in_red       = 8'd0;
        in_green     = 8'd0;
        in_blue      = 8'd0;
        in_valid     = 1'b0;
        in_hsync     = 1'b0;
        in_vsync     = 1'b0;

        error_count  = 0;
        check_count  = 0;
        random_seed  = 32'h1357_2468;

        // 第一次异步复位
        #2;
        rst_n = 1'b0;
        #1;

        check_output(8'd0, 1'b0, 1'b0, 1'b0);

        repeat (2) @(posedge clk);

        @(negedge clk);
        rst_n = 1'b1;

        // 基本颜色
        send_and_check(8'd0,   8'd0,   8'd0,   1'b1, 1'b0, 1'b0);
        send_and_check(8'd255, 8'd255, 8'd255, 1'b1, 1'b0, 1'b0);
        send_and_check(8'd255, 8'd0,   8'd0,   1'b1, 1'b1, 1'b0);
        send_and_check(8'd0,   8'd255, 8'd0,   1'b1, 1'b0, 1'b1);
        send_and_check(8'd0,   8'd0,   8'd255, 1'b1, 1'b1, 1'b1);

        // R、G、B相同时，灰度值应保持不变
        send_and_check(8'd64, 8'd64, 8'd64, 1'b1, 1'b0, 1'b0);

        // valid无效时，灰度输出必须为0
        send_and_check(8'd200, 8'd100, 8'd50, 1'b0, 1'b1, 1'b0);

        // 再次输出非零结果
        send_and_check(8'd255, 8'd255, 8'd255, 1'b1, 1'b1, 1'b1);

        // 在两个时钟边沿之间再次复位
        #2;
        rst_n = 1'b0;
        #1;

        check_output(8'd0, 1'b0, 1'b0, 1'b0);

        repeat (2) @(posedge clk);

        @(negedge clk);
        rst_n = 1'b1;

        // 检查复位后恢复
        send_and_check(8'd80, 8'd120, 8'd160, 1'b1, 1'b0, 1'b1);

        // 256组自动生成测试
        for (test_index = 0;
             test_index < 256;
             test_index = test_index + 1) begin

            random_red   = $random(random_seed);
            random_green = $random(random_seed);
            random_blue  = $random(random_seed);

            send_and_check(
                random_red,
                random_green,
                random_blue,
                (test_index % 11) != 0,
                (test_index % 16) == 0,
                (test_index % 64) == 0
            );
        end

        if (error_count == 0) begin
            $display(
                "TEST PASSED: rgb888_to_gray, %0d checks",
                check_count
            );
        end
        else begin
            $display(
                "TEST FAILED: rgb888_to_gray, %0d error(s)",
                error_count
            );
        end

        $finish;
    end

endmodule