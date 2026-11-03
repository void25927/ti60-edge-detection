`timescale 1ns / 1ps

// 1920×1080中央裁剪自检，验证多帧、边界、字节顺序和复位恢复。
module mipi_center_crop_32_tb;
    localparam integer INPUT_WIDTH = 1920;
    localparam integer OUTPUT_WIDTH = 960;
    localparam integer HEIGHT = 1080;
    localparam integer INPUT_GROUPS = INPUT_WIDTH / 4;
    localparam integer OUTPUT_GROUPS = OUTPUT_WIDTH / 4;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [31:0] in_data = 32'd0;
    reg in_valid = 1'b0;
    reg in_hsync = 1'b0;
    reg in_vsync = 1'b0;
    wire [31:0] out_data;
    wire out_valid, out_hsync, out_vsync;

    integer errors = 0;
    integer checked_groups = 0;
    integer frame, row, group_id;
    integer out_group_in_line;

    always #5 clk = ~clk;

    mipi_center_crop_32 dut (
        .clk(clk), .rst_n(rst_n), .in_data(in_data),
        .in_valid(in_valid), .in_hsync(in_hsync), .in_vsync(in_vsync),
        .out_data(out_data), .out_valid(out_valid),
        .out_hsync(out_hsync), .out_vsync(out_vsync)
    );

    // 每个字节对应连续像素，便于发现组内字节被交换。
    function [31:0] make_word;
        input integer frame_id;
        input integer y;
        input integer group_number;
        integer x0;
        reg [7:0] p0, p1, p2, p3;
        begin
            x0 = group_number * 4;
            p0 = (frame_id * 17 + y * 3 + x0) & 8'hff;
            p1 = (frame_id * 17 + y * 3 + x0 + 1) & 8'hff;
            p2 = (frame_id * 17 + y * 3 + x0 + 2) & 8'hff;
            p3 = (frame_id * 17 + y * 3 + x0 + 3) & 8'hff;
            make_word = {p3, p2, p1, p0};
        end
    endfunction

    task check_current_group;
        input integer expected_group;
        reg expected_valid;
        begin
            expected_valid = (expected_group >= 120) && (expected_group <= 359);
            #1;
            if (out_valid !== expected_valid || out_hsync !== expected_valid ||
                out_vsync !== 1'b1) begin
                errors = errors + 1;
                if (errors < 12)
                    $display("ERROR ctrl frame=%0d row=%0d group=%0d", frame, row, expected_group);
            end
            if (expected_valid) begin
                if (out_data !== make_word(frame, row, expected_group)) begin
                    errors = errors + 1;
                    if (errors < 12)
                        $display("ERROR data frame=%0d row=%0d group=%0d got=%h exp=%h",
                                 frame, row, expected_group, out_data,
                                 make_word(frame, row, expected_group));
                end
                if (expected_group == 120 && out_group_in_line != 0)
                    errors = errors + 1;
                if (expected_group == 359 && out_group_in_line != OUTPUT_GROUPS-1)
                    errors = errors + 1;
                out_group_in_line = out_group_in_line + 1;
                checked_groups = checked_groups + 1;
            end
        end
    endtask

    task send_full_frame;
        input integer frame_id;
        integer local_row, local_group;
        begin
            frame = frame_id;
            @(negedge clk); in_vsync = 1'b1;
            for (local_row=0; local_row<HEIGHT; local_row=local_row+1) begin
                row = local_row;
                out_group_in_line = 0;
                for (local_group=0; local_group<INPUT_GROUPS; local_group=local_group+1) begin
                    group_id = local_group;
                    @(negedge clk);
                    in_hsync = 1'b1;
                    in_valid = 1'b1;
                    in_data = make_word(frame_id, local_row, local_group);
                    check_current_group(local_group);
                    @(posedge clk);
                end
                @(negedge clk); in_hsync=1'b0; in_valid=1'b0; in_data=0;
                #1;
                if (out_valid || out_hsync || out_group_in_line != OUTPUT_GROUPS) begin
                    errors=errors+1;
                    if(errors<12) $display("ERROR line count frame=%0d row=%0d count=%0d",
                                           frame_id,local_row,out_group_in_line);
                end
                repeat(2) @(posedge clk);
            end
            @(negedge clk); in_vsync=1'b0; in_hsync=1'b0; in_valid=1'b0;
            #1;
            if(out_vsync!==1'b0 || out_valid!==1'b0) errors=errors+1;
            repeat(4) @(posedge clk);
        end
    endtask

    initial begin
        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        send_full_frame(1);
        send_full_frame(2);

        // 行中复位后，下一完整帧必须重新从第0组计数。
        @(negedge clk); in_vsync=1'b1; in_hsync=1'b1; in_valid=1'b1;
        repeat(200) begin
            in_data=32'h12345678;
            @(posedge clk); @(negedge clk);
        end
        rst_n=1'b0; #1;
        if(out_valid!==1'b0 || dut.group_count!==0) errors=errors+1;
        repeat(3) @(posedge clk);
        @(negedge clk); rst_n=1'b1; in_vsync=1'b0; in_hsync=1'b0; in_valid=1'b0;
        repeat(3) @(posedge clk);
        send_full_frame(3);

        if (checked_groups != 3*HEIGHT*OUTPUT_GROUPS) begin
            errors=errors+1;
            $display("ERROR checked groups=%0d expected=%0d",
                     checked_groups,3*HEIGHT*OUTPUT_GROUPS);
        end

        if(errors==0)
            $display("TEST PASSED: mipi_center_crop_32, checked_groups=%0d",checked_groups);
        else
            $display("TEST FAILED: mipi_center_crop_32, %0d error(s)",errors);
        $finish;
    end

    initial begin
        #100000000;
        $display("TEST FAILED: mipi_center_crop_32 timeout");
        $finish;
    end
endmodule
