`timescale 1ns/1ps
module snapshot_system_tb;
 parameter FOOTER_HEIGHT=0;
 reg pclk=0,aclk=0;always #3.36 pclk=~pclk;always #5.208333 aclk=~aclk;
 reg rst=0,req=0,cancel=0,freeze=1;
 reg [31:0] fid=1;reg [23:0] rgb=0;reg de=0,hs=1,vs=1;
 wire [23:0] out;wire od,oh,ov,busy,done,error;wire [2:0] saved;wire [31:0] frozen;
 wire [31:0] aa,ra;wire [7:0] al,rl;
 wire av,rv,wv,wl,br,rr;reg ar=0,rar=0,wr=0,bv=0,rdv=0,rdlast=0;
 wire [127:0] wd;wire [15:0] ws;reg [127:0] rd=0;
 reg [127:0] memory[0:32767];
 integer errors=0,cycles=0,wa=0,raddr=0,wleft=0,rleft=0,bdelay=0;
 integer x,y,f,j,checks=0,saved_checks=0,write_bytes=0,read_bytes=0;
 reg [2:0] expected_valid=0;
 reg [23:0] expected_picture[0:2];
 snapshot_system #(.UI_FOOTER_HEIGHT(FOOTER_HEIGHT)) dut(pclk,aclk,rst,req,cancel,freeze,fid,1'b1,2'd1,rgb,de,hs,vs,
 out,od,oh,ov,busy,done,error,saved,frozen,aa,ra,al,rl,av,rv,wv,wl,br,rr,
 ar,rar,wr,bv,rdv,rdlast,wd,ws,rd,2'b00,2'b00);
 task ck;input good;begin if(!good)begin errors=errors+1;if(errors<15)$display("FAIL t=%0t x=%0d y=%0d error=%b",$time,x,y,error);end end endtask
 function [23:0] image_rgb;input integer xx,yy;begin image_rgb={fid[4:0],3'b000,fid[5:0],2'b00,fid[4:0],3'b000};end endfunction
 function [23:0] expand;input [23:0] c;begin expand={c[23:19],c[23:21],c[15:10],c[15:14],c[7:3],c[7:5]};end endfunction
 always @(negedge aclk)begin ar=cycles%5==0;rar=cycles%7==0;wr=cycles%4!=0;end
 always @(posedge aclk)begin
  cycles=cycles+1;
  if(av&&ar)begin ck(wleft==0&&!bv);wa=(aa-32'h02000000)>>4;wleft=al+1;end
  if(wv&&wr)begin
   ck(wleft>0&&wa>=0&&wa<32768);ck(wl==(wleft==1));
   for(j=0;j<16;j=j+1)if(ws[j])begin memory[wa][j*8+:8]<=wd[j*8+:8];write_bytes=write_bytes+1;end
   wleft=wleft-1;wa=wa+1;if(wl)bdelay=12;
  end
  if(bdelay>0)begin bdelay=bdelay-1;if(bdelay==0)bv<=1;end
  if(bv&&br)bv<=0;
  if(rv&&rar)begin ck(rleft==0&&!rdv);raddr=(ra-32'h02000000)>>4;rleft=rl+1;end
  if(rleft>0&&!rdv&&cycles%3!=0)begin rd<=memory[raddr];rdv<=1;rdlast<=(rleft==1);end
  if(rdv&&rr)begin rdv<=0;rleft=rleft-1;raddr=raddr+1;read_bytes=read_bytes+16;end
 end
 task frame;begin
  @(negedge pclk);vs=0;de=0;repeat(12)@(negedge pclk);vs=1;
  repeat(20)@(negedge pclk);
  for(y=0;y<1080;y=y+1)begin
   for(x=0;x<1920;x=x+1)begin
    @(negedge pclk);de=1;rgb=image_rgb(x,y);
    @(posedge pclk);#0.1;ck(od&&oh==hs&&ov==vs);
    if(y>=900-FOOTER_HEIGHT&&y<1080-FOOTER_HEIGHT&&x>=960&&expected_valid[(x-960)/320])begin ck(out==expected_picture[(x-960)/320]);saved_checks=saved_checks+1;end
    else ck(out==rgb);
    checks=checks+1;
   end
   @(negedge pclk);de=0;repeat(280)@(negedge pclk);
  end
  repeat(200)@(negedge pclk);
 end endtask
 initial begin
  repeat(8)@(negedge pclk);rst=1;repeat(10)@(negedge pclk);
  for(f=0;f<4;f=f+1)begin
   fid=f+1;frame;
   @(negedge pclk);req=1;@(negedge pclk);req=0;
   frame;ck(saved==expected_valid);
   expected_valid[f%3]=1;expected_picture[f%3]=expand(image_rgb(0,0));
   frame;ck(saved==expected_valid);ck(!busy&&!error);ck(write_bytes==(f+1)*115200);
  end
  // 取消发生在已有部分像素写出后；旧三图必须保持不变且写服务能排空。
  @(negedge pclk);req=1;@(negedge pclk);req=0;
  fork
   frame;
   begin repeat(1000)@(negedge pclk);ck(dut.u_capture.sample_count>0&&dut.u_capture.state==2);
    @(negedge pclk);cancel=1;@(negedge pclk);cancel=0;
   end
  join
  ck(!busy&&!error);ck(saved==7);
  if(errors==0)$display("TEST PASSED: snapshot_system pixels=%0d thumbnail=%0d write_bytes=%0d read_bytes=%0d",checks,saved_checks,write_bytes,read_bytes);
  else $display("TEST FAILED: snapshot_system %0d error(s)",errors);
  $finish;
 end
 initial begin #500000000;errors=errors+1;$display("TEST FAILED: timeout");$finish;end
endmodule
