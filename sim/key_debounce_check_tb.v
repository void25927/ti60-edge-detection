`timescale 1ns/1ps
module key_debounce_check_tb;
    reg clk=0,rst_n=0;always #5 clk=~clk;
    reg [1:0] pins=3;
    wire flag;wire [1:0] value,press;
    integer errors=0,up=0,down=0,i;
    key_debounce #(.CLK_FREQ_HZ(5000),.DELAY_MS(20)) dut(clk,rst_n,pins,flag,value,press);
    task tick;input integer n;integer j;begin for(j=0;j<n;j=j+1)@(negedge clk);end endtask
    task check;input condition;input [255:0] message;begin
        if(condition!==1'b1)begin errors=errors+1;$display("FAIL: %0s",message);end
    end endtask
    always @(negedge clk)if(rst_n)begin if(press[1])up=up+1;if(press[0])down=down+1;end
    initial begin
        tick(4);rst_n=1;tick(120);
        check(value==0,"idle");
        pins=2;tick(90);check(value==0,"no early debounce");tick(20);
        check(value==1 && down==1,"100 cycle debounce");
        tick(300);check(down==1,"hold single event");
        pins=3;tick(110);check(value==0 && down==1,"release not press");
        for(i=0;i<8;i=i+1)begin pins=2;tick(3);pins=3;tick(3);end
        check(down==1,"bounce rejected");
        // 上键稳定按下期间，下键反复抖动不应阻止上键响应。
        pins=1;
        for(i=0;i<40;i=i+1)begin pins[0]=~pins[0];tick(3);end
        check(value[1] && up==1,"independent counters");
        pins=0;tick(110);check(value==3 && up==1 && down==2,"both keys");
        pins=1;tick(110);check(up==1 && down==2,"release other key");
        rst_n=0;tick(4);check(value==0 && press==0,"reset");
        pins=3;rst_n=1;tick(110);pins=1;tick(110);check(up==2,"reset recovery");
        if(errors==0)$display("TEST PASSED: key_debounce_check");
        else $display("TEST FAILED: key_debounce_check errors=%0d",errors);
        $finish;
    end
endmodule
