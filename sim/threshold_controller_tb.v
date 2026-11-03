`timescale 1ns/1ps
module threshold_controller_tb;
    reg clk=0,rst_n=0,en=0,add=0,sub=0,frame=0;
    wire[10:0]hi,lo,pending;integer errors=0,i;
    always #5 clk=~clk;
    threshold_controller #(.WIDTH(11),.DEFAULT_HIGH(80),.MIN_HIGH(16),.MAX_HIGH(96),.STEP(8)) dut(.clk(clk),.rst_n(rst_n),.adjust_enable(en),.add_pulse(add),.sub_pulse(sub),.frame_start(frame),.high_threshold(hi),.low_threshold(lo),.pending_high_threshold(pending));
    task pulse_add;begin @(negedge clk);add=1;@(negedge clk);add=0;end endtask
    task pulse_sub;begin @(negedge clk);sub=1;@(negedge clk);sub=0;end endtask
    task commit;begin @(negedge clk);frame=1;@(negedge clk);frame=0;end endtask
    task check;input[10:0]eh,el,ep;begin #1;if(hi!==eh||lo!==el||pending!==ep)begin $display("ERROR threshold hi=%0d/%0d lo=%0d/%0d pending=%0d/%0d",hi,eh,lo,el,pending,ep);errors=errors+1;end end endtask
    initial begin repeat(4)@(negedge clk);rst_n=1;check(80,40,80);pulse_add();check(80,40,80);
        en=1;pulse_add();check(80,40,88);commit();check(88,44,88);pulse_add();pulse_add();check(88,44,96);commit();check(96,48,96);
        for(i=0;i<20;i=i+1)pulse_sub();check(96,48,16);commit();check(16,8,16);
        @(negedge clk);add=1;sub=1;@(negedge clk);add=0;sub=0;check(16,8,16);
        rst_n=0;#1;check(80,40,80);
        if(errors==0)$display("TEST PASSED: threshold_controller");else $display("TEST FAILED: threshold_controller, %0d error(s)",errors);$finish;end
endmodule
