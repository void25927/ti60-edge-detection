`timescale 1ns/1ps
module snapshot_line_tb;
reg clk=0,rst=0,clear=0,lv=0,de=0,hs=0,vs=0;
reg[2:0]valid=7;reg[1:0]ls=0;reg[8:0]lx=0;reg[7:0]ly=0;
reg[15:0]lp=0;reg[10:0]x=0,y=0;reg[23:0]rgb=24'h123456;
wire[23:0]out;wire od,oh,ov,under,err;
integer errors=0,s,a,b,ix,iy;reg[23:0]expected;
always #5 clk=~clk;
snapshot_line_overlay #(.DISPLAY_WIDTH(12),.DISPLAY_HEIGHT(8),.THUMB_WIDTH(2),.THUMB_HEIGHT(2))dut(
 clk,rst,clear,valid,lv,ls,lx,ly,lp,x,y,rgb,de,hs,vs,out,od,oh,ov,under,err);
task tick;begin @(posedge clk);#1;end endtask
task ck;input c;begin if(c!==1'b1)errors=errors+1;end endtask
initial begin
 tick;@(negedge clk);rst=1;
 for(s=0;s<3;s=s+1)for(b=0;b<2;b=b+1)for(a=0;a<2;a=a+1)begin
   lv=1;ls=s;ly=b;lx=a;lp=(s==0)?16'hf800:(s==1)?16'h07e0:16'h001f;tick;@(negedge clk);
 end
 lv=0;de=1;
 for(iy=0;iy<8;iy=iy+1)for(ix=0;ix<12;ix=ix+1)begin
   x=ix;y=iy;hs=ix[0];vs=iy[0];expected=rgb;
   if(iy>=6 && ix>=6)expected=(ix<8)?24'hff0000:(ix<10)?24'h00ff00:24'h0000ff;
   tick;ck(out===expected&&od&&oh==hs&&ov==vs);@(negedge clk);
 end
 ck(!under&&!err);de=0;clear=1;tick;@(negedge clk);clear=0;de=1;x=6;y=6;tick;ck(under&&out==0);
 @(negedge clk);rst=0;tick;ck(!od&&!under&&!err);
 if(errors==0)$display("TEST PASSED: snapshot_line");else $display("TEST FAILED: snapshot_line errors=%0d",errors);
 $finish;
end
endmodule
