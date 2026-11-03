`timescale 1ns / 1ps

// 彩色边缘叠加模块自检。
module edge_overlay_tb;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg in_hsync = 1'b0;
    reg in_vsync = 1'b0;
    reg [7:0] in_red = 8'd0;
    reg [7:0] in_green = 8'd0;
    reg [7:0] in_blue = 8'd0;
    reg in_edge = 1'b0;

    wire out_valid;
    wire out_hsync;
    wire out_vsync;
    wire [7:0] out_red;
    wire [7:0] out_green;
    wire [7:0] out_blue;

    integer errors = 0;
    integer sample_count = 0;
    integer i;

    reg exp_valid = 1'b0;
    reg exp_hsync = 1'b0;
    reg exp_vsync = 1'b0;
    reg [7:0] exp_red = 8'd0;
    reg [7:0] exp_green = 8'd0;
    reg [7:0] exp_blue = 8'd0;
    reg [1:0] exp_edge_history = 2'b00;

    always #5 clk = ~clk;

    edge_overlay #(
        .EDGE_R(8'hFF), .EDGE_G(8'h00), .EDGE_B(8'hFF),
        .HORIZONTAL_EXPAND(1)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_hsync(in_hsync), .in_vsync(in_vsync),
        .in_red(in_red), .in_green(in_green), .in_blue(in_blue),
        .in_edge(in_edge),
        .out_valid(out_valid), .out_hsync(out_hsync), .out_vsync(out_vsync),
        .out_red(out_red), .out_green(out_green), .out_blue(out_blue)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            exp_valid <= 1'b0;
            exp_hsync <= 1'b0;
            exp_vsync <= 1'b0;
            exp_red   <= 8'd0;
            exp_green <= 8'd0;
            exp_blue  <= 8'd0;
            exp_edge_history <= 2'b00;
        end else begin
            exp_valid <= in_valid;
            exp_hsync <= in_hsync;
            exp_vsync <= in_vsync;
            if (!in_valid) begin
                exp_red   <= 8'd0;
                exp_green <= 8'd0;
                exp_blue  <= 8'd0;
                exp_edge_history <= 2'b00;
            end else if (in_edge || (|exp_edge_history)) begin
                exp_red   <= 8'hFF;
                exp_green <= 8'h00;
                exp_blue  <= 8'hFF;
                exp_edge_history <= {exp_edge_history[0],in_edge};
            end else begin
                exp_red   <= in_red;
                exp_green <= in_green;
                exp_blue  <= in_blue;
                exp_edge_history <= {exp_edge_history[0],in_edge};
            end
        end

        #1;
        if ({out_valid,out_hsync,out_vsync,out_red,out_green,out_blue} !==
            {exp_valid,exp_hsync,exp_vsync,exp_red,exp_green,exp_blue}) begin
            if (errors < 8)
                $display("ERROR: sample=%0d output=%h expected=%h", sample_count,
                    {out_valid,out_hsync,out_vsync,out_red,out_green,out_blue},
                    {exp_valid,exp_hsync,exp_vsync,exp_red,exp_green,exp_blue});
            errors = errors + 1;
        end
        sample_count = sample_count + 1;
    end

    task drive;
        input valid_value;
        input hsync_value;
        input vsync_value;
        input [7:0] red_value;
        input [7:0] green_value;
        input [7:0] blue_value;
        input edge_value;
        begin
            @(negedge clk);
            in_valid = valid_value;
            in_hsync = hsync_value;
            in_vsync = vsync_value;
            in_red   = red_value;
            in_green = green_value;
            in_blue  = blue_value;
            in_edge  = edge_value;
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        drive(1,1,1,8'h12,8'h34,8'h56,0);
        drive(1,0,1,8'hAA,8'hBB,8'hCC,1);
        drive(1,0,1,8'h10,8'h20,8'h30,0);
        drive(1,0,1,8'h40,8'h50,8'h60,0);
        drive(1,0,1,8'h70,8'h80,8'h90,0);
        drive(0,1,0,8'h11,8'h22,8'h33,1);

        for (i = 0; i < 256; i = i + 1)
            drive((i % 5) != 0, i[0], i[1], i[7:0], (i*3), (255-i), i[2]);

        // 再次复位，检查异步清零和恢复。
        #2 rst_n = 1'b0;
        #1;
        if ({out_valid,out_hsync,out_vsync,out_red,out_green,out_blue} !== 27'd0) begin
            $display("ERROR: asynchronous reset did not clear outputs");
            errors = errors + 1;
        end
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        drive(1,1,0,8'h21,8'h43,8'h65,0);
        drive(1,0,0,8'h21,8'h43,8'h65,1);
        drive(0,0,0,0,0,0,0);
        repeat (3) @(posedge clk);

        if (errors == 0)
            $display("TEST PASSED: edge_overlay");
        else
            $display("TEST FAILED: edge_overlay, %0d error(s)", errors);
        $finish;
    end

    initial begin
        #100000;
        $display("TEST FAILED: edge_overlay timeout");
        $finish;
    end
endmodule
