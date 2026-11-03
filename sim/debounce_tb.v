`timescale 1ns/1ps
module debounce_tb;
    reg clk=0,rst_n=0,key=1;wire pressed,down,up;integer errors=0,down_count=0,up_count=0;
    always #5 clk=~clk;
    debounce #(.CLK_FREQ_HZ(5000),.DEBOUNCE_MS(1),.PRESSED_LEVEL(1'b0)) dut(.clk(clk),.rst_n(rst_n),.key_in(key),.key_pressed(pressed),.key_pressed_pulse(down),.key_released_pulse(up));
    always @(posedge clk)begin #1;if(down)down_count=down_count+1;if(up)up_count=up_count+1;end
    initial begin repeat(4)@(negedge clk);rst_n=1;
        repeat(4)begin @(negedge clk);key=0;@(negedge clk);key=1;end repeat(8)@(negedge clk);if(down_count!=0)errors=errors+1;
        key=0;repeat(12)@(negedge clk);if(!pressed||down_count!=1)errors=errors+1;
        repeat(10)@(negedge clk);if(down_count!=1)errors=errors+1;
        key=1;repeat(12)@(negedge clk);if(pressed||up_count!=1)errors=errors+1;
        rst_n=0;#1;if({pressed,down,up}!==0)errors=errors+1;repeat(3)@(negedge clk);rst_n=1;repeat(3)@(negedge clk);
        if(errors==0)$display("TEST PASSED: debounce");else $display("TEST FAILED: debounce, %0d error(s)",errors);$finish;end
endmodule
