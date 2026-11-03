`timescale 1ns/1ps
module canny_hysteresis_tb;
    reg clk=0,rst_n=0;reg[1:0]p[0:8];reg v=0,w=0,h=0,f=0;
    wire[1:0]c;wire edge_o,ov,ow,oh,of;integer i,j,errors=0;reg strong;reg[1:0]exp_c;reg exp_e;reg[3:0]ec;
    always #5 clk=~clk;
    canny_hysteresis dut(.clk(clk),.rst_n(rst_n),.in_c11(p[0]),.in_c12(p[1]),.in_c13(p[2]),.in_c21(p[3]),.in_c22(p[4]),.in_c23(p[5]),.in_c31(p[6]),.in_c32(p[7]),.in_c33(p[8]),.in_valid(v),.in_window_valid(w),.in_hsync(h),.in_vsync(f),.out_class(c),.out_edge(edge_o),.out_valid(ov),.out_window_valid(ow),.out_hsync(oh),.out_vsync(of));
    always @(posedge clk)begin strong=0;for(j=0;j<9;j=j+1)if(j!=4&&p[j]==2)strong=1;exp_c=0;exp_e=0;if(rst_n&&v&&w)begin if(p[4]==2||(p[4]==1&&strong))begin exp_c=2;exp_e=1;end else exp_c=p[4];end ec=rst_n?{f,h,v&&w,v}:0;#1;if(c!==exp_c||edge_o!==exp_e||{of,oh,ow,ov}!==ec)begin if(errors<8)$display("ERROR hysteresis");errors=errors+1;end end
    initial begin for(i=0;i<9;i=i+1)p[i]=0;repeat(4)@(negedge clk);rst_n=1;v=1;w=1;
        for(i=0;i<512;i=i+1)begin @(negedge clk);p[4]=(i/256)%3;for(j=0;j<9;j=j+1)if(j!=4)p[j]=(i>>j)&1?2:0;h=i[0];f=i[1];end
        @(negedge clk);v=0;w=0;repeat(3)@(negedge clk);if(errors==0)$display("TEST PASSED: canny_hysteresis");else $display("TEST FAILED: canny_hysteresis, %0d error(s)",errors);$finish;end
endmodule
