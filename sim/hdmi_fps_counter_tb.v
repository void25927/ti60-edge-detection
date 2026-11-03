`timescale 1ns/1ps
module hdmi_fps_counter_tb;
 reg clk=0,rst=0,vs=1;always #5 clk=~clk;
 wire [11:0] bcd;wire valid,update;wire [7:0] a,b,c;
 integer errors=0,i,j;
 hdmi_fps_counter #(.CLK_HZ(100)) dut(clk,rst,vs,bcd,valid,update,a,b,c);
 initial begin
  repeat(3)@(negedge clk);if({a,b,c}!==24'h2d2d2d)errors=errors+1;rst=1;
  for(j=0;j<2;j=j+1)begin
   for(i=0;i<100;i=i+1)begin vs=(i%10!=5);@(negedge clk);end
   if(bcd!==12'h010 || !valid || !update || {a,b,c}!==24'h303130)errors=errors+1;
  end
  vs=1;repeat(100)@(negedge clk);if(bcd!==0)errors=errors+1;
  rst=0;@(negedge clk);if(valid || update)errors=errors+1;
  if(errors==0)$display("TEST PASSED: hdmi_fps_counter");else $display("TEST FAILED fps errors=%0d",errors);
  $finish;
 end
endmodule
