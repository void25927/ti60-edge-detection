`timescale 1ns/1ps
// 截图服务：显示域取样、跨域FIFO、DDR读写、三图双行缓存及帧边界提交。
module snapshot_system #(parameter UI_FOOTER_HEIGHT=0)(
 input wire pixel_clk,axi_clk,rst_n,
 input wire request,cancel,freeze_request,
 input wire [31:0] source_frame_id,
 input wire source_frame_valid,
 input wire [1:0] source_mode,
 input wire [23:0] in_rgb,
 input wire in_de,in_hsync,in_vsync,
 output wire [23:0] out_rgb,
 output wire out_de,out_hsync,out_vsync,
 output wire busy,done,error,
 output wire [2:0] saved_valid,
 output reg [31:0] freeze_frame_id,
 output wire [31:0] awaddr,araddr,
 output wire [7:0] awlen,arlen,
 output wire awvalid,arvalid,wvalid,wlast,bready,rready,
 input wire awready,arready,wready,bvalid,rvalid,rlast,
 output wire [127:0] wdata,
 output wire [15:0] wstrb,
 input wire [127:0] rdata,
 input wire [1:0] bresp,rresp
);
 wire pixel_rst_n,axi_rst_n;
 video_reset_sync u_pixel_reset(pixel_clk,rst_n,pixel_rst_n);
 video_reset_sync u_axi_reset(axi_clk,rst_n,axi_rst_n);
 reg [10:0] x,y;
 reg de_d,vs_d,freeze_d;
 reg [31:0] displayed_id;
 wire frame_start=vs_d&&!in_vsync;
 wire frame_end=de_d&&!in_de&&y==1079;
 wire line_start=in_de&&!de_d;
 wire [10:0] actual_x=line_start?0:x;
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin x<=0;y<=0;de_d<=0;vs_d<=1;freeze_d<=0;displayed_id<=0;freeze_frame_id<=0;end
  else begin
   de_d<=in_de;vs_d<=in_vsync;freeze_d<=freeze_request;
   if(frame_start)begin x<=0;y<=0;end
   else if(in_de)x<=actual_x+1'b1;
   else if(de_d)begin x<=0;y<=y+1'b1;end
   if(line_start&&y==0)displayed_id<=source_frame_id;
   if((freeze_request&&!freeze_d)||request)freeze_frame_id<=displayed_id;
  end
 end
 wire cap_busy,cap_done,cap_error,cap_abort,cap_valid,cap_ready,cap_last;
 wire [31:0] cap_addr;
 wire [15:0] cap_pixel;
 wire [5:0] saved_slots;
 wire [95:0] saved_ids;
 reg abort_pending,abort_queued;
 wire ack_valid;wire [1:0] ack_data;
 wire [1:0] faults_pixel;
 wire lines_fault,load_fault;
 wire [7:0] reader_pending;
 assign busy=cap_busy||abort_pending;
 assign done=cap_done;
 assign error=cap_error||(|faults_pixel)||lines_fault||load_fault;
 snapshot_capture u_capture(
  .clk(pixel_clk),.rst_n(pixel_rst_n),.request(request&&!abort_pending),.cancel(cancel),
  .requested_frame_id(displayed_id),.frame_start(frame_start),.frame_end(frame_end),
  .source_stable(source_frame_valid&&source_mode==1),.source_frame_id(source_frame_id),
  .in_valid(in_de),.in_rgb(in_rgb),.write_ready(cap_ready),
  .store_done(ack_valid&&ack_data==1),.store_error(|faults_pixel),
  .display_boundary(frame_start),.display_reads_drained(reader_pending==0),
  .busy(cap_busy),.done(cap_done),.error(cap_error),.write_valid(cap_valid),
  .write_address(cap_addr),.write_pixel(cap_pixel),.write_last(cap_last),.abort_store(cap_abort),
  .saved_valid(saved_valid),.saved_slots(saved_slots),.saved_frame_ids(saved_ids));
 wire input_ready;
 wire [49:0] packet;
 wire packet_valid,packet_ready;
 wire send_abort=abort_pending&&!abort_queued;
 assign cap_ready=input_ready&&!send_abort;
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin abort_pending<=0;abort_queued<=0;end
  else begin
   if(cap_abort)begin abort_pending<=1;abort_queued<=0;end
   if(send_abort&&input_ready)abort_queued<=1;
   if(ack_valid&&ack_data==2)begin abort_pending<=0;abort_queued<=0;end
  end
 end
 video_async_fifo #(.DATA_WIDTH(50),.ADDR_BITS(9)) u_write_fifo(
  .wr_clk(pixel_clk),.rd_clk(axi_clk),.rst_n(rst_n),
  .in_data(send_abort?{1'b1,49'd0}:{1'b0,cap_last,cap_addr,cap_pixel}),
  .in_valid(send_abort||cap_valid),.in_ready(input_ready),
  .out_data(packet),.out_valid(packet_valid),.out_ready(packet_ready),.wr_count(),.rd_count());
 wire writer_ready,writer_done,writer_fault,writer_drained;
 wire writer_cancel_ready;
 wire abort_accept=packet_valid&&packet[49]&&writer_cancel_ready;
 assign packet_ready=packet[49]?writer_cancel_ready:writer_ready;
 snapshot_axi_writer u_writer(
  .clk(axi_clk),.rst_n(axi_rst_n),.cancel(abort_accept),
  .in_valid(packet_valid&&!packet[49]),.in_ready(writer_ready),
  .in_address(packet[47:16]),.in_pixel(packet[15:0]),.in_last(packet[48]),
  .awid(),.awaddr(awaddr),.awlen(awlen),.awsize(),.awburst(),.awvalid(awvalid),.awready(awready),
  .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),
  .bid(4'd8),.bresp(bresp),.bvalid(bvalid),.bready(bready),
  .done(writer_done),.fault(writer_fault),.drained(writer_drained),.cancel_ready(writer_cancel_ready));
 wire ack_ready;
 reg ack_overflow;
 always @(posedge axi_clk or negedge axi_rst_n)begin
  if(!axi_rst_n)ack_overflow<=0;
  else if((writer_done||abort_accept)&&!ack_ready)ack_overflow<=1;
 end
 video_async_fifo #(.DATA_WIDTH(2),.ADDR_BITS(2)) u_write_ack(
  .wr_clk(axi_clk),.rd_clk(pixel_clk),.rst_n(rst_n),
  .in_data(abort_accept?2'd2:2'd1),.in_valid(writer_done||abort_accept),.in_ready(ack_ready),
  .out_data(ack_data),.out_valid(ack_valid),.out_ready(1'b1),.wr_count(),.rd_count());
 // 缩略图前一行预取第0行；底栏启用时预取和显示位置同时上移。
 localparam PREFETCH_TOP=899-UI_FOOTER_HEIGHT;
 wire request_line=line_start&&y>=PREFETCH_TOP&&y<PREFETCH_TOP+180&&(|saved_valid);
 wire [7:0] requested_y=y-PREFETCH_TOP;
 wire request_fifo_ready,request_out_valid,reader_ready;
 wire [16:0] request_packet;
 reg scheduler_fault;
 reg [7:0] pending_rows;
 assign reader_pending=pending_rows;
 wire load_valid;wire [35:0] load_packet;
 wire completed_row=load_valid&&load_packet[35];
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin pending_rows<=0;scheduler_fault<=0;end
  else begin
   case({request_line&&request_fifo_ready,completed_row})
    2'b10:pending_rows<=pending_rows+1'b1;
    2'b01:pending_rows<=pending_rows-1'b1;
    default:begin end
   endcase
   if(request_line&&!request_fifo_ready)scheduler_fault<=1;
   if(frame_start&&pending_rows!=0)scheduler_fault<=1;
  end
 end
 video_async_fifo #(.DATA_WIDTH(17),.ADDR_BITS(2)) u_read_request(
  .wr_clk(pixel_clk),.rd_clk(axi_clk),.rst_n(rst_n),
  .in_data({saved_valid,saved_slots,requested_y}),.in_valid(request_line),.in_ready(request_fifo_ready),
  .out_data(request_packet),.out_valid(request_out_valid),.out_ready(reader_ready),.wr_count(),.rd_count());
 wire rp_valid,rp_ready,read_done,reader_fault;
 wire [15:0] rp_data;wire [1:0] rp_slot;wire [8:0] rp_x;wire [7:0] rp_y;
 wire raw_reader_ready,load_ready;
 reg row_done_pending;
 assign reader_ready=raw_reader_ready&&!row_done_pending&&!read_done;
 snapshot_axi_reader u_reader(
  .clk(axi_clk),.rst_n(axi_rst_n),.request(request_out_valid&&reader_ready),.request_ready(raw_reader_ready),
  .request_y(request_packet[7:0]),.saved_valid(request_packet[16:14]),.saved_slots(request_packet[13:8]),
  .arid(),.araddr(araddr),.arlen(arlen),.arvalid(arvalid),.arready(arready),
  .rdata(rdata),.rid(4'd9),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready),
  .pixel_valid(rp_valid),.pixel_ready(rp_ready),.pixel_data(rp_data),.pixel_slot(rp_slot),
  .pixel_x(rp_x),.pixel_y(rp_y),.done(read_done),.fault(reader_fault));
 always @(posedge axi_clk or negedge axi_rst_n)begin
  if(!axi_rst_n)row_done_pending<=0;
  else begin
   if(read_done)row_done_pending<=1;
   if(row_done_pending&&load_ready)row_done_pending<=0;
  end
 end
 assign rp_ready=load_ready&&!row_done_pending;
 video_async_fifo #(.DATA_WIDTH(36),.ADDR_BITS(8)) u_read_pixels(
  .wr_clk(axi_clk),.rd_clk(pixel_clk),.rst_n(rst_n),
  .in_data(row_done_pending?{1'b1,35'd0}:{1'b0,rp_slot,rp_x,rp_y,rp_data}),
  .in_valid(row_done_pending||rp_valid),.in_ready(load_ready),
  .out_data(load_packet),.out_valid(load_valid),.out_ready(1'b1),.wr_count(),.rd_count());
 video_control_mailbox #(.WIDTH(2)) u_faults(
  .src_clk(axi_clk),.dst_clk(pixel_clk),.async_rst_n(rst_n),
  .src_data({reader_fault,writer_fault|ack_overflow}),.dst_data(faults_pixel),.dst_update(),.src_busy());
 wire overlay_fault;
 assign lines_fault=overlay_fault||scheduler_fault;
 snapshot_line_overlay #(.FOOTER_HEIGHT(UI_FOOTER_HEIGHT)) u_overlay(
  .clk(pixel_clk),.rst_n(pixel_rst_n),.clear_lines(frame_start),.saved_valid(saved_valid),
  .load_valid(load_valid&&!load_packet[35]),.load_slot(load_packet[34:33]),
  .load_x(load_packet[32:24]),.load_y(load_packet[23:16]),.load_pixel(load_packet[15:0]),
  .in_x(actual_x),.in_y(y),.in_rgb(in_rgb),.in_de(in_de),.in_hsync(in_hsync),.in_vsync(in_vsync),
  .out_rgb(out_rgb),.out_de(out_de),.out_hsync(out_hsync),.out_vsync(out_vsync),
  .underflow_seen(overlay_fault),.load_error(load_fault));
endmodule
