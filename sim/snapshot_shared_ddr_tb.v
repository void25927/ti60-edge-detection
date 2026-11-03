`timescale 1ns/1ps
module snapshot_shared_ddr_tb;
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
 wire [3:0] qready;wire [1:0] wwready,bbvalid,rrvalid;
 wire [127:0] common_rdata;wire common_rlast;wire [1:0] bc,rc;
 wire mav,mat,mwv,mwl,mbr,mrr;
 wire [31:0] ma;wire [7:0] ml;wire [3:0] mid,mwid;
 wire [127:0] mwd;wire [15:0] mws;wire arb_fault;
 reg [3:0] bid=0,rid=0;
 integer vw_pending=0,vr_pending=0,vwleft=0,vrleft=0,max_backlog=0;
 integer request_wait[0:3];integer max_request_wait=0,max_video_wait=0,qi;
 reg vw_busy=0,vr_busy=0;
 wire [3:0] qvalid={rv,av,(vr_pending>0&&!vr_busy),(vw_pending>0&&!vw_busy)};
 video_snapshot_arbiter arb(
  .clk(aclk),.rst_n(rst),.request_valid(qvalid),.request_ready(qready),
  .request_address({ra,aa,32'h400000,32'h000000}),.request_length({rl,al,8'd127,8'd127}),
  .write_valid({wv,vw_busy&&vwleft>0}),.write_ready(wwready),
  .write_data({wd,128'h1234}),.write_strobe({ws,16'hffff}),.write_last({wl,vwleft==1}),
  .response_valid(bbvalid),.response_ready({br,1'b1}),.read_valid(rrvalid),.read_ready({rr,1'b1}),
  .read_data(common_rdata),.read_last(common_rlast),.response_code(bc),.read_code(rc),
  .avalid(mav),.aready(ar),.aaddr(ma),.alen(ml),.aid(mid),.atype(mat),
  .wvalid(mwv),.wready(wr),.wdata(mwd),.wstrb(mws),.wlast(mwl),.wid(mwid),
  .bvalid(bv),.bready(mbr),.bid(bid),.bresp(2'b00),
  .rvalid(rdv),.rready(mrr),.rdata(rd),.rid(rid),.rresp(2'b00),.rlast(rdlast),.fault(arb_fault));
 reg [2:0] expected_valid=0;
 reg [23:0] expected_picture[0:2];
 snapshot_system dut(pclk,aclk,rst,req,cancel,freeze,fid,1'b1,2'd1,rgb,de,hs,vs,
 out,od,oh,ov,busy,done,error,saved,frozen,aa,ra,al,rl,av,rv,wv,wl,br,rr,
 qready[2],qready[3],wwready[1],bbvalid[1],rrvalid[1],common_rlast,wd,ws,common_rdata,bc,rc);
 task ck;input good;begin if(!good)begin errors=errors+1;if(errors<15)$display("FAIL t=%0t x=%0d y=%0d error=%b",$time,x,y,error);end end endtask
 function [23:0] image_rgb;input integer xx,yy;begin image_rgb={fid[4:0],3'b000,fid[5:0],2'b00,fid[4:0],3'b000};end endfunction
 function [23:0] expand;input [23:0] c;begin expand={c[23:19],c[23:21],c[15:10],c[15:14],c[7:3],c[7:5]};end endfunction
 always @(negedge aclk)begin ar=cycles%5==0&&cycles%750>=64;wr=cycles%4!=0&&cycles%750>=64;end
 always @(posedge aclk)begin
  cycles=cycles+1;
  for(qi=0;qi<4;qi=qi+1)begin
   if(qvalid[qi]&&!qready[qi])request_wait[qi]=request_wait[qi]+1;
   else request_wait[qi]=0;
   if(request_wait[qi]>max_request_wait)max_request_wait=request_wait[qi];
   if(qi<2&&request_wait[qi]>max_video_wait)max_video_wait=request_wait[qi];
  end
  // 96MHz下每1150拍产生2048字节读写，各约171MB/s，不随时钟降低负载。
  if(rst&&cycles%1150==0)begin vw_pending=vw_pending+1;vr_pending=vr_pending+1;end
  if(vw_pending>max_backlog)max_backlog=vw_pending;
  if(vr_pending>max_backlog)max_backlog=vr_pending;
  if(qready[0]&&qvalid[0])begin vw_busy=1;vwleft=128;end
  if(qready[1]&&qvalid[1])begin vr_busy=1;vrleft=128;end
  if(wwready[0]&&vw_busy&&vwleft>0)vwleft=vwleft-1;
  if(bbvalid[0])begin vw_pending=vw_pending-1;vw_busy=0;end
  if(rrvalid[0])begin vrleft=vrleft-1;if(common_rlast)begin ck(vrleft==0);vr_busy=0;vr_pending=vr_pending-1;end end
  if(mav&&ar&&mat)begin ck(wleft==0&&!bv);wa=(ma-32'h02000000)>>4;wleft=ml+1;bid<=mid;end
  if(mwv&&wr)begin
   ck(wleft>0);ck(mwl==(wleft==1));
   if(bid==8)begin
    ck(wa>=0&&wa<32768);
    for(j=0;j<16;j=j+1)if(mws[j])begin memory[wa][j*8+:8]<=mwd[j*8+:8];write_bytes=write_bytes+1;end
   end
   wleft=wleft-1;wa=wa+1;if(mwl)bdelay=12;
  end
  if(bdelay>0)begin bdelay=bdelay-1;if(bdelay==0)bv<=1;end
  if(bv&&mbr)bv<=0;
  if(mav&&ar&&!mat)begin ck(rleft==0&&!rdv);raddr=(ma-32'h02000000)>>4;rleft=ml+1;rid<=mid;end
  if(rleft>0&&!rdv&&cycles%3!=0&&cycles%750>=64&&!(mav&&ar&&!mat))begin rd<=(rid==9)?memory[raddr]:128'd0;rdv<=1;rdlast<=(rleft==1);end
  if(rdv&&mrr)begin rdv<=0;rleft=rleft-1;raddr=raddr+1;read_bytes=read_bytes+16;end
 end
 task frame;begin
  @(negedge pclk);vs=0;de=0;repeat(12)@(negedge pclk);vs=1;
  repeat(20)@(negedge pclk);
  for(y=0;y<1080;y=y+1)begin
   for(x=0;x<1920;x=x+1)begin
    @(negedge pclk);de=1;rgb=image_rgb(x,y);
    @(posedge pclk);#0.1;ck(od&&oh==hs&&ov==vs);
    if(y>=900&&x>=960&&expected_valid[(x-960)/320])begin ck(out==expected_picture[(x-960)/320]);saved_checks=saved_checks+1;end
    else ck(out==rgb);
    checks=checks+1;
   end
   @(negedge pclk);de=0;repeat(280)@(negedge pclk);
  end
  repeat(200)@(negedge pclk);
 end endtask
 initial begin
  for(qi=0;qi<4;qi=qi+1)request_wait[qi]=0;
  repeat(8)@(negedge pclk);rst=1;repeat(10)@(negedge pclk);
  for(f=0;f<4;f=f+1)begin
   fid=f+1;frame;
   @(negedge pclk);req=1;@(negedge pclk);req=0;
   frame;ck(saved==expected_valid);
   expected_valid[f%3]=1;expected_picture[f%3]=expand(image_rgb(0,0));
   frame;ck(saved==expected_valid);ck(!busy&&!error);ck(write_bytes==(f+1)*115200);
  end
  ck(!arb_fault);ck(max_backlog<=2);
  $display("DDR STATS max_request_wait=%0d max_video_wait=%0d ui_clock_mhz=96",max_request_wait,max_video_wait);
  if(errors==0)$display("TEST PASSED: snapshot_shared_ddr pixels=%0d thumbnail=%0d write_bytes=%0d read_bytes=%0d max_video_backlog=%0d",checks,saved_checks,write_bytes,read_bytes,max_backlog);
  else $display("TEST FAILED: snapshot_shared_ddr %0d error(s)",errors);
  $finish;
 end
 initial begin #500000000;errors=errors+1;$display("TEST FAILED: timeout");$finish;end
endmodule
