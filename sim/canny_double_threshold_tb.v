`timescale 1ns/1ps
module canny_double_threshold_tb;
    reg clk=0,rst_n=0;reg[10:0]g=0,hi=160,lo=64;reg v=0,w=0,h=0,f=0;
    wire[1:0]c;wire ov,ow,oh,of;integer i,errors=0;reg[1:0]exp;reg[3:0]ec;reg[10:0]safe_lo;
    always #5 clk=~clk;
    canny_double_threshold dut(.clk(clk),.rst_n(rst_n),.in_nms(g),.in_high_threshold(hi),.in_low_threshold(lo),.in_valid(v),.in_window_valid(w),.in_hsync(h),.in_vsync(f),.out_class(c),.out_valid(ov),.out_window_valid(ow),.out_hsync(oh),.out_vsync(of));
    always @(posedge clk)begin safe_lo=(lo<=hi)?lo:hi;exp=0;if(rst_n&&v&&w)begin if(g>=hi)exp=2;else if(g>=safe_lo)exp=1;end ec=rst_n?{f,h,v&&w,v}:0;#1;if(c!==exp||{of,oh,ow,ov}!==ec)begin if(errors<8)$display("ERROR threshold g=%0d class=%0d/%0d",g,c,exp);errors=errors+1;end end
    initial begin repeat(4)@(negedge clk);rst_n=1;for(i=0;i<2048;i=i+1)begin @(negedge clk);g=i;v=1;w=1;h=i[0];f=i[1];end
        @(negedge clk);lo=200;hi=100;g=150;repeat(2)@(negedge clk);v=0;w=0;repeat(2)@(negedge clk);
        if(errors==0)$display("TEST PASSED: canny_double_threshold");else $display("TEST FAILED: canny_double_threshold, %0d error(s)",errors);$finish;end
endmodule
