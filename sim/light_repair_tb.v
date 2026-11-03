`timescale 1ns/1ps
// 穷举3^9种分类窗口，以循环扫描相对邻点作为参考。
module light_repair_tb;
reg clk=0,rst_n=0,v=0,w=0,h=0,f=0;
reg [1:0] p[0:8];
wire [1:0] c; wire e,ov,ow,oh,of;
integer n,j,k,t,errors=0,checks=0;
reg strong,pair_hit,ee; reg [1:0] cc; reg [3:0] ctrl;
always #5 clk=~clk;
canny_hysteresis #(.REPAIR_SHORT_GAP(1)) dut(clk,rst_n,p[0],p[1],p[2],p[3],p[4],p[5],p[6],p[7],p[8],v,w,h,f,c,e,ov,ow,oh,of);
always @(posedge clk) begin
  strong=0;pair_hit=0;
  for(k=0;k<9;k=k+1) if(k!=4 && p[k]==2) strong=1;
  for(k=0;k<4;k=k+1) if(p[k]==2 && p[8-k]==2) pair_hit=1;
  ee=0;cc=0;ctrl=0;
  if(rst_n) begin
    ctrl={f,h,v&&w,v};
    if(v&&w) begin
      ee=(p[4]==2)||(p[4]==1&&strong)||(p[4]==0&&pair_hit);
      cc=ee?2:p[4];
    end
  end
  #1;checks=checks+1;
  if({c,e,of,oh,ow,ov}!=={cc,ee,ctrl}) errors=errors+1;
end
initial begin
 for(j=0;j<9;j=j+1)p[j]=0;
 repeat(4)@(negedge clk);rst_n=1;v=1;w=1;
 for(n=0;n<19683;n=n+1) begin
   @(negedge clk);t=n;for(j=0;j<9;j=j+1)begin p[j]=t%3;t=t/3;end
   h=n[0];f=n[1];
 end
 @(negedge clk);v=0;repeat(3)@(negedge clk);
 v=1;w=0;repeat(3)@(negedge clk);
 rst_n=0;repeat(3)@(negedge clk);rst_n=1;w=1;repeat(3)@(negedge clk);
 if(errors==0)$display("TEST PASSED: light_repair checks=%0d",checks);
 else $display("TEST FAILED: light_repair errors=%0d",errors);
 $finish;
end
endmodule
