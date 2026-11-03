`timescale 1ns / 1ps

module system_mode_controller_tb;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg frame_start = 1'b0;
    reg function_short_press = 1'b0;
    reg function_long_press = 1'b0;
    reg action_short_press = 1'b0;
    reg action_long_press = 1'b0;
    wire [1:0] system_mode;
    wire display_mode;
    wire [1:0] ddr_mode;
    wire [1:0] replay_offset;
    wire adjust_enable;
    wire add_pulse;
    wire sub_pulse;
    integer errors = 0;

    always #5 clk = ~clk;

    system_mode_controller #(.REPLAY_HOLD_FRAMES(2)) dut (
        .clk(clk),.rst_n(rst_n),.frame_start(frame_start),
        .function_short_press(function_short_press),
        .function_long_press(function_long_press),
        .action_short_press(action_short_press),
        .action_long_press(action_long_press),
        .system_mode(system_mode),.display_mode(display_mode),.ddr_mode(ddr_mode),
        .replay_offset(replay_offset),
        .threshold_adjust_enable(adjust_enable),
        .threshold_add_pulse(add_pulse),.threshold_sub_pulse(sub_pulse)
    );

    task pulse_function_short;
        begin @(negedge clk); function_short_press=1; @(negedge clk); function_short_press=0; #1; end
    endtask
    task pulse_function_long;
        begin @(negedge clk); function_long_press=1; @(negedge clk); function_long_press=0; #1; end
    endtask
    task pulse_short;
        begin @(negedge clk); action_short_press=1; @(negedge clk); action_short_press=0; #1; end
    endtask
    task pulse_long;
        begin @(negedge clk); action_long_press=1; @(negedge clk); action_long_press=0; #1; end
    endtask
    task pulse_frame;
        begin @(negedge clk); frame_start=1; @(negedge clk); frame_start=0; #1; end
    endtask
    task expect_mode;
        input [1:0] value;
        input [127:0] name;
        begin
            if (system_mode !== value) begin
                $display("ERROR %s: mode=%0d expected=%0d",name,system_mode,value);
                errors=errors+1;
            end
        end
    endtask

    initial begin
        repeat(3) @(posedge clk); rst_n=1;
        @(negedge clk); #1;
        expect_mode(0,"reset live");

        pulse_short(); expect_mode(1,"short freeze");
        pulse_short(); expect_mode(0,"short resume");
        pulse_long();  expect_mode(2,"long replay");
        if (replay_offset !== 3) errors=errors+1;
        pulse_frame();
        if (replay_offset !== 3) begin $display("ERROR replay hold"); errors=errors+1; end
        pulse_frame();
        if (replay_offset !== 2) begin $display("ERROR replay advance"); errors=errors+1; end
        pulse_short(); expect_mode(1,"replay short freeze");
        pulse_long();  expect_mode(2,"freeze long replay");
        pulse_long();  expect_mode(0,"replay long live");

        pulse_function_short();
        if(display_mode!==1'b1 || system_mode!==0) begin
            $display("ERROR display mode switch"); errors=errors+1;
        end

        pulse_function_long(); expect_mode(3,"function long param");
        if (!adjust_enable || ddr_mode != 0) begin
            $display("ERROR param outputs"); errors=errors+1;
        end
        @(negedge clk); action_short_press=1; @(posedge clk); #1;
        if (!add_pulse) begin $display("ERROR add pulse"); errors=errors+1; end
        @(negedge clk); action_short_press=0;
        @(negedge clk); action_long_press=1; @(posedge clk); #1;
        if (!sub_pulse) begin $display("ERROR sub pulse"); errors=errors+1; end
        @(negedge clk); action_long_press=0;
        pulse_function_long(); expect_mode(0,"function long live");

        pulse_short(); expect_mode(1,"freeze before function");
        pulse_function_short(); expect_mode(0,"function short cancels freeze");
        if(display_mode!==1'b0) begin
            $display("ERROR display mode wrap"); errors=errors+1;
        end

        if (errors==0) $display("TEST PASSED: system_mode_controller");
        else $display("TEST FAILED: system_mode_controller, %0d error(s)",errors);
        $finish;
    end
endmodule
