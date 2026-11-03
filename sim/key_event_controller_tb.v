`timescale 1ns/1ps
module key_event_controller_tb;
    reg clk=0,rst_n=0,pressed=0,down=0,up=0;wire short_p,long_p;integer errors=0,sc=0,lc=0;
    always #5 clk=~clk;
    key_event_controller #(.CLK_FREQ_HZ(5000),.LONG_PRESS_MS(1)) dut(.clk(clk),.rst_n(rst_n),.key_pressed(pressed),.key_pressed_pulse(down),.key_released_pulse(up),.short_press_pulse(short_p),.long_press_pulse(long_p));
    always @(posedge clk)begin #1;if(short_p)sc=sc+1;if(long_p)lc=lc+1;end
    task pulse_down;begin @(negedge clk);pressed=1;down=1;@(negedge clk);down=0;end endtask
    task pulse_up;begin @(negedge clk);pressed=0;up=1;@(negedge clk);up=0;end endtask
    initial begin repeat(4)@(negedge clk);rst_n=1;pulse_down();repeat(2)@(negedge clk);pulse_up();repeat(3)@(negedge clk);if(sc!=1||lc!=0)errors=errors+1;
        pulse_down();repeat(8)@(negedge clk);if(lc!=1)errors=errors+1;pulse_up();repeat(3)@(negedge clk);if(sc!=1||lc!=1)errors=errors+1;
        if(errors==0)$display("TEST PASSED: key_event_controller");else $display("TEST FAILED: key_event_controller, %0d error(s)",errors);$finish;end
endmodule
