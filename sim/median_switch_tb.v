`timescale 1ns/1ps
module median_switch_tb;
reg clk=0,rst_n=0,v=0,h=0,f=1,en=1;
reg [7:0] pixel=0;
integer frame,y,x,j,k,errors=0,checks=0,tmp;
integer sort_pixels[0:8];
reg [7:0] expected[0:2];reg [2:0] valid_pipe;
reg frame_enable=1;
reg canny_request=1,canny_frame=1;
reg [10:0] bypass_expected_mag;
reg [1:0] bypass_expected_class;
reg bypass_expected_edge;
reg [3:0] controls[0:2];
always #5 clk=~clk;
canny_edge_pipeline #(.IMAGE_WIDTH(24),.ADDR_WIDTH(5),.RUNTIME_MEDIAN(1),.RUNTIME_CANNY(1)) dut(
 .clk(clk),.rst_n(rst_n),.in_median_enable(en),.in_canny_enable(canny_request),.in_gray(pixel),.in_rgb({pixel,pixel,pixel}),
 .in_valid(v),.in_hsync(h),.in_vsync(f),.in_high_threshold(11'd80),.in_low_threshold(11'd40),
 .out_red(),.out_green(),.out_blue(),.out_gray(),.out_edge(),
 .out_valid(),.out_window_valid(),.out_hsync(),.out_vsync());
always @(posedge clk)begin
 bypass_expected_class=(rst_n&&dut.nv&&dut.nw&&dut.sobel_bypass_magnitude>=80)?2:0;
 bypass_expected_mag=(rst_n&&dut.dv&&dut.d_all_valid)?dut.d22[10:0]:0;
 bypass_expected_edge=rst_n&&dut.fv&&dut.f_all_valid&&(dut.f22[1:0]==2);
 if(!rst_n)begin for(j=0;j<3;j=j+1)begin expected[j]=0;controls[j]=0;end valid_pipe=0;end
 else begin
  expected[2]=expected[1];expected[1]=expected[0];expected[0]=0;
  valid_pipe={valid_pipe[1:0],dut.av&&dut.aw};
  controls[2]=controls[1];controls[1]=controls[0];
  controls[0]={dut.af,dut.ah,dut.av&&dut.aw,dut.av};
  sort_pixels[0]=dut.a11[7:0];sort_pixels[1]=dut.a12[7:0];sort_pixels[2]=dut.a13[7:0];
  sort_pixels[3]=dut.a21[7:0];sort_pixels[4]=dut.a22[7:0];sort_pixels[5]=dut.a23[7:0];
  sort_pixels[6]=dut.a31[7:0];sort_pixels[7]=dut.a32[7:0];sort_pixels[8]=dut.a33[7:0];
  for(j=0;j<9;j=j+1)for(k=j+1;k<9;k=k+1)if(sort_pixels[j]>sort_pixels[k])begin tmp=sort_pixels[j];sort_pixels[j]=sort_pixels[k];sort_pixels[k]=tmp;end
  if(dut.av&&dut.aw)expected[0]=frame_enable?sort_pixels[4]:dut.a22[7:0];
 end
 #1;
 if(rst_n)begin
  if(dut.sobel_bypass_class!==bypass_expected_class || dut.sobel_bypass_magnitude!==bypass_expected_mag ||
     dut.sobel_bypass_edge!==bypass_expected_edge)errors=errors+1;
  if(dut.mv && dut.median_enable_frame!==frame_enable)errors=errors+1;
  if(dut.h2v && dut.canny_enable_frame!==canny_frame)errors=errors+1;
  if(!canny_frame && dut.out_valid && dut.out_edge!==((dut.h2w&&bypass_expected_edge)?8'd255:8'd0))errors=errors+1;
  checks=checks+1;
  if(dut.selected_median!==expected[2] || {dut.mf,dut.mh,dut.mw,dut.mv}!==controls[2])begin
   if(errors<5)$display("ERROR median switch expected=%0d actual=%0d",expected[2],dut.selected_median);
   errors=errors+1;
  end
 end
end
initial begin
 repeat(4)@(negedge clk);rst_n=1;
 for(frame=0;frame<4;frame=frame+1)begin
  @(negedge clk);en=frame[0];frame_enable=en;canny_request=frame[1];canny_frame=canny_request;f=0;
  repeat(12)@(negedge clk);f=1;
  for(y=0;y<24;y=y+1)begin
   for(x=0;x<24;x=x+1)begin
    @(negedge clk);v=1;h=1;pixel=(x*31+y*57+frame*13)%256;
    if(x==12&&y==10)en=~en; // 帧内请求不得立即切换
   end
   @(negedge clk);v=0;h=0;repeat(4)@(negedge clk);
  end
  repeat(20)@(negedge clk);
 end
 if(errors==0)$display("TEST PASSED: median_switch checks=%0d",checks);
 else $display("TEST FAILED: median_switch errors=%0d",errors);
 $finish;
end
endmodule
