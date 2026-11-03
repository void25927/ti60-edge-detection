`timescale 1ns/1ps
module canny_nms_tb;
    reg clk=0,rst_n=0;reg[10:0]mag=0,n=0,s=0,w=0,e=0,nw=0,ne=0,sw=0,se=0;reg[1:0]dir=0;reg v=0,wv=0,hs=0,vs=0;
    wire[10:0]o;wire ov,ow,oh,of;integer i,seed,errors=0;reg[10:0]exp;reg[3:0]ec;reg[10:0]a,b;
    always #5 clk=~clk;
    canny_nms dut(.clk(clk),.rst_n(rst_n),.in_g_mag(mag),.in_direction(dir),.in_g_n(n),.in_g_s(s),.in_g_w(w),.in_g_e(e),.in_g_nw(nw),.in_g_ne(ne),.in_g_sw(sw),.in_g_se(se),.in_valid(v),.in_window_valid(wv),.in_hsync(hs),.in_vsync(vs),.out_nms(o),.out_valid(ov),.out_window_valid(ow),.out_hsync(oh),.out_vsync(of));
    always @(posedge clk)begin
        case(dir)0:begin a=w;b=e;end 1:begin a=ne;b=sw;end 2:begin a=n;b=s;end default:begin a=nw;b=se;end endcase
        exp=(rst_n&&v&&wv&&mag>=a&&mag>=b)?mag:0;ec=rst_n?{vs,hs,v&&wv,v}:0;#1;
        if(o!==exp||{of,oh,ow,ov}!==ec)begin if(errors<8)$display("ERROR nms");errors=errors+1;end
    end
    initial begin seed=71;repeat(4)@(negedge clk);rst_n=1;
        for(i=0;i<2048;i=i+1)begin @(negedge clk);mag=$random(seed);n=$random(seed);s=$random(seed);w=$random(seed);e=$random(seed);nw=$random(seed);ne=$random(seed);sw=$random(seed);se=$random(seed);dir=i%4;v=(i%5)!=0;wv=(i%7)!=0;hs=i[0];vs=i[1];end
        @(negedge clk);v=0;wv=0;repeat(3)@(negedge clk);if(errors==0)$display("TEST PASSED: canny_nms");else $display("TEST FAILED: canny_nms, %0d error(s)",errors);$finish;end
endmodule
