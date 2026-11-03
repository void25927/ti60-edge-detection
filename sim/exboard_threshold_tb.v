`timescale 1ns/1ps
module exboard_threshold_tb;
    reg clk=0,rst=0,up_n=1,down_n=1,fault=0,frame=0;
    always #5 clk=~clk;
    wire add,sub,run_led,alarm_led,alarm;
    wire [10:0] high,low,pending;
    integer errors=0,run_edges=0;reg last_run;
    exboard_control #(.CLK_FREQ_HZ(5000),.DEBOUNCE_MS(20),.RUN_HALF_PERIOD(20),.ALARM_HALF_PERIOD(10)) dut(
        clk,rst,up_n,down_n,fault,add,sub,run_led,alarm_led,alarm);
    threshold_controller threshold(clk,rst,1'b1,add,sub,frame,high,low,pending);
    task tick;input integer n;integer i;begin for(i=0;i<n;i=i+1)@(negedge clk);end endtask
    task check;input c;input [255:0] m;begin if(c!==1'b1)begin errors=errors+1;$display("FAIL %0s",m);end end endtask
    always @(negedge clk)begin if(run_led!==last_run && rst)run_edges=run_edges+1;last_run=run_led;end
    initial begin
        tick(4);rst=1;tick(120);up_n=0;tick(120);
        check(pending==88 && high==80,"up / frame boundary");
        frame=1;tick(1);frame=0;tick(1);check(high==88 && low==44,"atomic threshold commit");
        tick(140);check(pending==88,"hold single event");
        up_n=1;tick(110);down_n=0;tick(110);check(pending==80,"down");
        down_n=1;tick(110);up_n=0;down_n=0;tick(110);check(pending==80,"simultaneous cancel");
        up_n=1;down_n=1;tick(110);fault=1;tick(30);fault=0;tick(30);
        check(alarm && run_edges>5,"latched fault / heartbeat");
        up_n=0;tick(110);check(alarm,"threshold key cannot clear fault");
        rst=0;tick(8);check(!alarm && !alarm_led,"reset alarm");
        if(errors==0)$display("TEST PASSED: exboard_threshold");else $display("TEST FAILED: exboard_threshold %0d",errors);
        $finish;
    end
endmodule
