`timescale 1ns/1ps
// 检查五项菜单、算法状态、保存状态和有效区外的像素透传。
module feature_ui_tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,de=0,vs=1;reg [2:0] menu=0;
 reg median=0,canny=0,saving=0;reg [2:0] saved=0;
 wire [23:0] rgb;wire od,oh,ov;
 integer errors=0,checks=0,m,x,y,col;
 reg [71:0] expected_menu;
 reg [7:0] expected_char;
 video_ui_overlay #(.FEATURE_MENU(1)) dut(
 .clk(clk),.rst_n(rst),.in_rgb(24'h123456),.in_de(de),.in_hsync(1'b1),.in_vsync(vs),
 .in_mode(2'd0),.in_display_mode(1'b0),.in_high_threshold(11'd80),.in_low_threshold(11'd40),
 .in_replay_offset(2'd0),.in_ddr_error(1'b0),.in_video_error(1'b0),
 .in_menu(menu),.in_median_enable(median),.in_canny_enable(canny),.in_saving(saving),
 .in_saved_valid(saved),.out_rgb(rgb),.out_de(od),.out_hsync(oh),.out_vsync(ov));
 task ck;input ok;begin checks=checks+1;if(!ok)begin errors=errors+1;if(errors<10)$display("FAIL menu=%0d x=%0d y=%0d",m,x,y);end end endtask
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(m=0;m<5;m=m+1)begin
   menu=m;median=m%2;canny=(m!=3);saving=(m==2);saved=m;
   case(m)0:expected_menu="MEDIAN   ";1:expected_menu="THRESHOLD";
    2:expected_menu="REPLAY   ";3:expected_menu="CANNY    ";4:expected_menu="DISPLAY  ";endcase
   @(negedge clk);vs=0;repeat(4)@(negedge clk);vs=1;repeat(20)@(negedge clk);
   for(y=0;y<66;y=y+1)begin
    for(x=0;x<1920;x=x+1)begin
     @(negedge clk);de=1;#1;
     col=(x-16)/8;
     if(y==8&&x>=16&&((x-16)%8==0))begin
      if(col>=74&&col<=82)ck(dut.current_char===expected_menu[(82-col)*8+:8]);
      if(col==21)ck(dut.current_char===(canny?8'h43:8'h53));
      if(col==92)ck(dut.current_char===(median?8'h4e:8'h46));
     end
     if(y==36&&x>=16&&((x-16)%8==0))begin
      if(col==56)ck(dut.current_char===(saving?8'h42:8'h52));
      if(col==69)ck(dut.current_char===(saved[0]?8'h31:8'h2d));
      if(col==71)ck(dut.current_char===(saved[1]?8'h32:8'h2d));
      if(col==73)ck(dut.current_char===(saved[2]?8'h33:8'h2d));
     end
     @(posedge clk);#1;ck(od&&oh&&ov==vs);
     if(y>=64)ck(rgb===24'h123456);
    end
    @(negedge clk);de=0;repeat(3)@(negedge clk);
   end
  end
  if(errors==0)$display("TEST PASSED: feature_ui checks=%0d",checks);
  else $display("TEST FAILED: feature_ui %0d error(s)",errors);
  $finish;
 end
endmodule
