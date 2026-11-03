`timescale 1ns/1ps
// 使用工程原始FIFO，验证实际视频控制器、仲裁、帧槽及DDR等待的组合行为。
module video_ddr_path_tb;
`ifdef FULL_HD
 localparam FRAME_BYTES=1920*1080,FRAME_BITS=22,MEM_WORDS=6*262144;
`else
 localparam FRAME_BYTES=2048,FRAME_BITS=12,MEM_WORDS=1536;
`endif
 reg ac=0,pc=0,cc=0;always #5.208333 ac=~ac;always #3.36 pc=~pc;always #11.9 cc=~cc;
 reg rst=1,wvs=0,we=0,rvs=1,re=0;reg [31:0] wp=0;
 reg [1:0] mode=0,offset=0;reg [31:0] freeze_id=0;
 wire [7:0] pixel;wire pixel_valid;wire [12:0] count;
 wire [2:0] wi,ri,hist;wire [31:0] fid;wire fv,ff;wire [1:0] active;
 wire [31:0] wa,ra;wire [7:0] wl,rl;wire wav,rav,wv,wlast;wire [127:0] wd;wire [15:0] ws;
 wire [3:0] qr;wire [1:0] wr,bv,rv;wire [127:0] rdata;wire rlast;wire [1:0] bresp,rresp;
 wire av,at,mwv,mwl,br,rr;wire [31:0] addr;wire [7:0] len;wire [3:0] aid,wid;wire [127:0] mwd;wire [15:0] mws;
 reg ar=0,mwr=0,mbv=0,mrv=0,mrl=0;reg [127:0] mrd=0;reg [3:0] bid=0,rid=0;
 wire arb_fault;
 reg [127:0] mem[0:MEM_WORDS-1];
 integer errors=0,checks=0,cycle=0,waddr=0,raddr=0,wleft=0,rleft=0,bd=0,i,f;
 integer max_write_words=0,max_read_pixels=0,fifo_overflows=0,fifo_underflows=0;
 reg stall_reads=0;reg [31:0] expected;
 axi4_ctrl #(.C_ID_LEN(4),.C_BUF_SIZE(FRAME_BITS),.C_RD_END_ADDR(FRAME_BYTES),.C_W_WIDTH(32)) dut(
 .axi_clk(ac),.axi_reset(rst),.axi_awaddr(wa),.axi_awlen(wl),.axi_awvalid(wav),.axi_awready(qr[0]),
 .axi_wdata(wd),.axi_wstrb(ws),.axi_wlast(wlast),.axi_wvalid(wv),.axi_wready(wr[0]),
 .axi_bid(4'd0),.axi_bresp(bresp),.axi_bvalid(bv[0]),
 .axi_araddr(ra),.axi_arlen(rl),.axi_arvalid(rav),.axi_arready(qr[1]),
 .axi_rid(4'd0),.axi_rdata(rdata),.axi_rresp(rresp),.axi_rlast(rlast),.axi_rvalid(rv[0]),
 .wframe_pclk(cc),.wframe_vsync(wvs),.wframe_data_en(we),.wframe_data(wp),
 .rframe_pclk(pc),.rframe_vsync(rvs),.rframe_data_en(re),.rframe_data(pixel),
 .rframe_data_valid(pixel_valid),.rframe_data_count(count),.frame_mode_request(mode),
 .replay_frame_offset(offset),.frame_mode_active(active),.frame_write_index(wi),.frame_read_index(ri),
 .frame_history_count(hist),.freeze_frame_id(freeze_id),.display_frame_id(fid),.display_frame_valid(fv),.frame_fault(ff));
 video_snapshot_arbiter arb(.clk(ac),.rst_n(!rst),.request_valid({2'b00,rav,wav}),.request_ready(qr),
 .request_address({64'd0,ra,wa}),.request_length({16'd0,rl,wl}),
 .write_valid({1'b0,wv}),.write_ready(wr),.write_data({128'd0,wd}),.write_strobe({16'd0,ws}),.write_last({1'b0,wlast}),
 .response_valid(bv),.response_ready(2'b11),.read_valid(rv),.read_ready(2'b11),.read_data(rdata),.read_last(rlast),
 .response_code(bresp),.read_code(rresp),.avalid(av),.aready(ar),.aaddr(addr),.alen(len),.aid(aid),.atype(at),
 .wvalid(mwv),.wready(mwr),.wdata(mwd),.wstrb(mws),.wlast(mwl),.wid(wid),
 .bvalid(mbv),.bready(br),.bid(bid),.bresp(2'b00),.rvalid(mrv),.rready(rr),.rdata(mrd),.rid(rid),.rresp(2'b00),.rlast(mrl),.fault(arb_fault));
 task ck;input ok;begin checks=checks+1;if(!ok)begin errors=errors+1;if(errors<15)$display("FAIL time=%0t fid=%0d pix=%h count=%0d",$time,fid,pixel,count);end end endtask
 always @(negedge ac)begin ar=(cycle%3!=0);mwr=(cycle%4!=0);end
 always @(posedge cc)if(!rst)begin
  if(dut.Gen_FIFO_W32.u_W0_FIFO_32.wr_datacount_o>max_write_words)
   max_write_words=dut.Gen_FIFO_W32.u_W0_FIFO_32.wr_datacount_o;
  if(dut.Gen_FIFO_W32.u_W0_FIFO_32.u_efx_fifo_top.overflow_o===1'b1)fifo_overflows=fifo_overflows+1;
 end
 always @(posedge pc)if(!rst)begin
  if(count>max_read_pixels)max_read_pixels=count;
  if(re&&!pixel_valid)fifo_underflows=fifo_underflows+1;
 end
 always @(posedge ac)begin
  cycle=cycle+1;
  if(av&&ar&&at)begin waddr=addr>>4;wleft=len+1;bid<=aid;end
  if(mwv&&mwr)begin
   ck(wleft>0&&waddr<MEM_WORDS&&mwl==(wleft==1));mem[waddr]<=mwd;
   waddr=waddr+1;wleft=wleft-1;if(wleft==0)bd=17;
  end
  if(bd>0)begin bd=bd-1;if(bd==0)mbv<=1;end
  if(mbv&&br)mbv<=0;
  if(av&&ar&&!at)begin ck(rleft==0&&!mrv);raddr=addr>>4;rleft=len+1;rid<=aid;end
  if(rleft>0&&!mrv&&!stall_reads&&cycle%3!=0&&!(av&&ar&&!at))begin
   mrd<=mem[raddr];mrl<=(rleft==1);mrv<=1;
  end
  if(mrv&&rr)begin mrv<=0;raddr=raddr+1;rleft=rleft-1;end
 end
 task camera;input integer id;integer ci;begin
  @(negedge cc);wvs=1;
  repeat(20)@(negedge cc);
  for(ci=0;ci<FRAME_BYTES/4;ci=ci+1)begin we=1;wp={4{id[7:0]}};@(negedge cc);end
  we=0;wvs=0;repeat(500)@(negedge ac);
 end endtask
 task boundary;begin @(negedge pc);rvs=0;repeat(45)@(negedge pc);rvs=1;end endtask
 task read_frame;integer pi;begin
  repeat(700)@(negedge ac);expected=fid;ck(fv&&!ff&&!arb_fault);
  for(pi=0;pi<FRAME_BYTES;pi=pi+1)begin
   @(negedge pc);ck(pixel_valid&&pixel===expected[7:0]);re=1;
  end
  @(negedge pc);re=0;
 end endtask
 initial begin
  repeat(15)@(negedge ac);rst=0;repeat(30)@(negedge ac);
  for(f=1;f<=6;f=f+1)begin camera(f);boundary;read_frame;end
  fork camera(7);begin boundary;read_frame;end join
  mode=2;offset=3;repeat(25)@(negedge ac);boundary;read_frame;ck(fid==4);
  freeze_id=fid;mode=1;repeat(25)@(negedge ac);boundary;read_frame;ck(fid==4);
  mode=0;repeat(25)@(negedge ac);
  // 故意让旧读响应跨越下一次显示边界，随后检查新帧不混入旧数据。
  stall_reads=1;boundary;wait(rleft>0);
  mode=2;offset=3;repeat(50)@(negedge ac);boundary;
  repeat(100)@(negedge ac);stall_reads=0;read_frame;
  ck(!ff&&!arb_fault);
  ck(fifo_overflows==0&&fifo_underflows==0);
  $display("FIFO STATS max_write_words=%0d of 2048 max_read_pixels=%0d of 8192 overflow=%0d underflow=%0d",max_write_words,max_read_pixels,fifo_overflows,fifo_underflows);
  if(errors==0)$display("TEST PASSED: video_ddr_path checks=%0d",checks);
  else $display("TEST FAILED: video_ddr_path %0d error(s)",errors);
  $finish;
 end
 initial begin #500000000;errors=errors+1;$display("TEST FAILED: video_ddr_path timeout");$finish;end
endmodule
