`timescale 1ns/1ps
// 完整图像与结果的双时钟缓存核心；默认四槽，RGB888不压缩。
// 此模块尚须与正式控制/特征录入及实际DDR仲裁一并验收。
module paired_video_buffer #(
 parameter PIXELS=2073600,BASE=32'h04000000,SLOT_BYTES=32'h00600000,
 parameter WRITE_FIFO_BITS=10,READ_FIFO_BITS=9,STREAM_WRITER=0
)(
 input wire pixel_clk,axi_clk,rst_n,enable,clear_pending,
 input wire [23:0] in_rgb,
 input wire in_de,in_hsync,in_vsync,
 input wire [31:0] in_frame_id,in_config,in_original_id,
 input wire result_valid,
 input wire [31:0] result_frame_id,
 input wire [1:0] result_status,
 input wire [15:0] result_track_id,
 output reg [23:0] out_rgb,
 output reg out_de,out_hsync,out_vsync,
 output wire shown_valid,
 output wire [31:0] shown_frame_id,shown_config,shown_epoch,
 output reg [31:0] shown_original_id,
 output wire [1:0] shown_status,
 output wire [15:0] shown_track_id,
 output wire allocated,
 output wire [1:0] allocated_slot,
 output wire [31:0] current_epoch,
 input wire [31:0] lookup_frame_id,
 output reg lookup_valid,
 output reg [1:0] lookup_slot,
 output reg [31:0] lookup_epoch,
 output wire write_command_valid,
 input wire write_command_ready,
 output wire [31:0] write_address,
 output wire [7:0] write_length,
 output wire [127:0] write_data,
 output wire write_valid,write_last,
 input wire write_ready,response_valid,
 input wire [1:0] response_code,
 output wire response_ready,
 output wire read_command_valid,
 input wire read_command_ready,
 output wire [31:0] read_address,
 output wire [7:0] read_length,
 input wire [127:0] read_data,
 input wire read_valid,read_last,
 input wire [1:0] read_code,
 output wire read_ready,
 output wire [WRITE_FIFO_BITS:0] write_level,
 output wire [READ_FIFO_BITS:0] read_level,
 output wire [2:0] queue_depth,queue_high,
 output wire fault,
 input wire source_frame_valid
);
 wire prst,arst;
 video_reset_sync p_reset(pixel_clk,rst_n,prst);
 video_reset_sync a_reset(axi_clk,rst_n,arst);
 reg de_d,vs_d,frame_active,enabled_d,local_fault;
 wire first=in_de&&!de_d&&!frame_active;
 wire boundary=vs_d&&!in_vsync;
 wire cancel=clear_pending||(enabled_d!=enable);
 always @(posedge pixel_clk or negedge prst)begin
  if(!prst)begin de_d<=0;vs_d<=1;frame_active<=0;enabled_d<=0;end
  else begin
   de_d<=in_de;vs_d<=in_vsync;enabled_d<=enable;
   if(!in_vsync)frame_active<=0;else if(first)frame_active<=1;
  end
 end
 wire allocate_ready;
 assign allocated=first&&enable&&source_frame_valid&&!cancel&&allocate_ready;
 reg [31:0] tag_id[0:3],tag_epoch[0:3],origin[0:3],retired_id[0:7],retired_epoch[0:7];
 reg [3:0] tags;reg [7:0] retired;reg [2:0] retire_wr,retire_cursor;
 integer integer_unused;
 wire [31:0] pack_count,writer_words,writer_bursts;
 wire [WRITE_FIFO_BITS:0] write_level_pixel;
 wire [READ_FIFO_BITS:0] read_level_pixel;
 reg result_found;reg [31:0] result_ep;integer k;
 reg result_pending;
 reg [31:0] result_id_q,result_epoch_q;
 reg [1:0] result_status_q;
 reg [15:0] result_track_q;
 always @(*)begin
  lookup_valid=0;lookup_slot=0;lookup_epoch=0;result_found=0;result_ep=0;
  for(k=0;k<8;k=k+1)begin
   if(retired[k]&&retired_id[k]==result_frame_id)begin result_found=1;result_ep=retired_epoch[k];end
  end
  for(k=0;k<4;k=k+1)begin
   if(tags[k]&&tag_id[k]==lookup_frame_id)begin lookup_valid=1;lookup_slot=k;lookup_epoch=tag_epoch[k];end
  end
  for(k=0;k<4;k=k+1)if(tags[k]&&tag_id[k]==result_frame_id)begin result_found=1;result_ep=tag_epoch[k];end
 end
 // 先锁存查找结果，再提交配对表，切断tag_epoch到表写使能的长路径。
 // clear同拍取消提交；跨代次返回仍由配对表按epoch拒收。
 always @(posedge pixel_clk or negedge prst)begin
  if(!prst)begin result_pending<=0;result_id_q<=0;result_epoch_q<=0;result_status_q<=0;result_track_q<=0;end
  else begin
   result_pending<=result_valid&&result_found&&!cancel;
   if(result_valid&&result_found&&!cancel)begin
    result_id_q<=result_frame_id;result_epoch_q<=result_ep;
    result_status_q<=result_status;result_track_q<=result_track_id;
   end
  end
 end
 wire pub_valid,pub_ready,pair_fault;wire [1:0] pub_slot,pub_status;wire [15:0] pub_track;wire [31:0] pub_id,pub_config;
 wire [3:0] pair_code;
 wire completion_update;wire [67:0] completion_pixel;
 wire header_valid,decoded_valid,decoded_last,decoder_fault;
 wire [1:0] decoded_slot;wire [31:0] decoded_id,decoded_config,decoded_epoch;wire [127:0] decoded_header;wire [23:0] decoded_rgb;
 reg held_valid;reg [1:0] held_slot;
 wire release_old=pub_ready&&pub_valid&&held_valid;
 inspection_pair_commit slots(
  .clk(pixel_clk),.rst_n(prst),.clear_pending(cancel),.allocate(allocated),.allocate_ready(allocate_ready),.frame_id(in_frame_id),.frame_config(in_config),.allocate_slot(allocated_slot),.epoch(current_epoch),
  .image_done(completion_update),.image_error(completion_pixel[66]),.image_slot(completion_pixel[65:64]),.image_frame_id(completion_pixel[31:0]),.image_epoch(completion_pixel[63:32]),
  .result_done(result_pending),.result_error(1'b0),.result_frame_id(result_id_q),.result_epoch(result_epoch_q),.result_status(result_status_q),.result_track_id(result_track_q),
  .publish_valid(pub_valid),.publish_ready(pub_ready),.publish_slot(pub_slot),.publish_frame_id(pub_id),.publish_config(pub_config),.publish_status(pub_status),.publish_track_id(pub_track),
  .release_valid(release_old),.release_slot(held_slot),.fault(pair_fault),.fault_code(pair_code),.queued(queue_depth),.high_water(queue_high));
 wire pack_valid,pack_ready,pack_fault;wire [129:0] pack_data,write_packet;wire write_packet_valid,write_packet_ready;
 rgb888_frame_pack #(.PIXELS(PIXELS)) pack(pixel_clk,prst,allocated,in_de,in_rgb,allocated_slot,in_frame_id,in_config,current_epoch,pack_valid,pack_ready,pack_data,pack_fault,pack_count);
 video_async_fifo #(.DATA_WIDTH(130),.ADDR_BITS(WRITE_FIFO_BITS)) write_fifo(pixel_clk,axi_clk,rst_n,pack_data,pack_valid,pack_ready,write_packet,write_packet_valid,write_packet_ready,write_level_pixel,write_level);
 wire ws_ready,writer_pixel_ready,writer_done,writer_fault;wire [31:0] writer_id,writer_epoch;
 wire write_header=write_packet[129:128]==0;
 assign write_packet_ready=write_header?ws_ready:writer_pixel_ready;
 wire [31:0] write_base=BASE+write_packet[1:0]*SLOT_BYTES;
 reg [1:0] writer_slot;
 generate if(STREAM_WRITER==0)begin: buffered_write
 paired_frame_writer #(.FRAME_BYTES(PIXELS*3)) writer(axi_clk,arst,write_packet_valid&&write_header,ws_ready,write_base,write_packet[33:2],write_packet[97:66],write_packet[127:0],write_packet_valid&&!write_header,write_packet[129:128]==2,writer_pixel_ready,
  write_command_valid,write_command_ready,write_address,write_length,write_data,write_valid,write_last,write_ready,response_valid,response_code,response_ready,writer_done,writer_fault,writer_id,writer_epoch,writer_words,writer_bursts);
 end else begin: fifo_credit_write
 paired_frame_writer_stream #(.FRAME_BYTES(PIXELS*3)) writer(axi_clk,arst,write_packet_valid&&write_header,ws_ready,write_base,write_packet[33:2],write_packet[97:66],write_packet[127:0],write_packet_valid&&!write_header,write_packet[129:128]==2,writer_pixel_ready,
  write_command_valid,write_command_ready,write_address,write_length,write_data,write_valid,write_last,write_ready,response_valid,response_code,response_ready,writer_done,writer_fault,writer_id,writer_epoch,writer_words,writer_bursts,{{(31-WRITE_FIFO_BITS){1'b0}},write_level});
 end endgenerate
 reg [67:0] completion_axi;wire completion_busy;
 always @(posedge axi_clk or negedge arst)begin
  if(!arst)begin writer_slot<=0;completion_axi<=0;end
  else begin
   if(write_packet_valid&&write_packet_ready&&write_header)writer_slot<=write_packet[1:0];
   if(writer_done)completion_axi<={~completion_axi[67],1'b0,writer_slot,writer_epoch,writer_id};
  end
 end
 video_control_mailbox #(.WIDTH(68)) complete_mailbox(axi_clk,pixel_clk,rst_n,completion_axi,completion_pixel,completion_update,completion_busy);
 reg [128:0] request_pixel;wire [128:0] request_axi;wire request_update,request_busy;
 assign pub_ready=boundary&&enable&&!cancel&&!request_busy;
 reg [31:0] published;
 always @(posedge pixel_clk or negedge prst)begin
  if(!prst)begin tags<=0;retired<=0;retire_wr<=0;retire_cursor<=0;local_fault<=0;held_valid<=0;held_slot<=0;request_pixel<=0;shown_original_id<=0;published<=0;end
  else begin
   if(first&&enable&&source_frame_valid&&!cancel&&!allocate_ready)local_fault<=1;
   if(result_valid&&!result_found&&!cancel)local_fault<=1;
   if(cancel)begin
    retire_cursor=retire_wr;
    for(integer_unused=0;integer_unused<4;integer_unused=integer_unused+1)if(tags[integer_unused])begin
     retired_id[retire_cursor]<=tag_id[integer_unused];retired_epoch[retire_cursor]<=tag_epoch[integer_unused];retired[retire_cursor]<=1;retire_cursor=retire_cursor+1'b1;
    end
    retire_wr<=retire_cursor;tags<=0;published<=0;
   end
   if(allocated)begin tags[allocated_slot]<=1;tag_id[allocated_slot]<=in_frame_id;tag_epoch[allocated_slot]<=current_epoch;origin[allocated_slot]<=in_original_id;end
   if(pub_ready&&pub_valid)begin
    held_valid<=1;held_slot<=pub_slot;published<=published+1'b1;
    request_pixel<={~request_pixel[128],pub_config[31],8'd0,(pub_status!=0?3'd1:3'd0),pub_track,pub_status,current_epoch,{1'b0,pub_config[30:0]},pub_id,pub_slot};
   end else if(boundary&&enable&&published!=0&&!cancel&&queue_depth!=0)local_fault<=1;
   if(header_valid)shown_original_id<=origin[decoded_slot];
   if(in_de&&enable&&shown_valid&&!cancel&&!decoded_valid)local_fault<=1;
  end
 end
 video_control_mailbox #(.WIDTH(129)) request_mailbox(pixel_clk,axi_clk,rst_n,request_pixel,request_axi,request_update,request_busy);
 wire reader_ready,reader_done,reader_fault;wire fifo_read_ready,reader_packet_valid;wire [129:0] reader_packet,pixel_packet;wire pixel_packet_valid,pixel_packet_ready;
 reg axi_fault;
 always @(posedge axi_clk or negedge arst)begin
  if(!arst)axi_fault<=0;
  else if((request_update&&!reader_ready)||(writer_done&&completion_busy))axi_fault<=1;
 end
 paired_frame_reader #(.FRAME_BYTES(PIXELS*3),.FIFO_CREDIT(1)) reader(axi_clk,arst,request_update,reader_ready,BASE+request_axi[1:0]*SLOT_BYTES,request_axi[127:0],read_command_valid,read_command_ready,read_address,read_length,read_data,read_valid,read_last,read_code,read_ready,reader_packet_valid,fifo_read_ready,reader_packet,reader_done,reader_fault,(32'd1<<READ_FIFO_BITS)-read_level);
 video_async_fifo #(.DATA_WIDTH(130),.ADDR_BITS(READ_FIFO_BITS)) read_fifo(axi_clk,pixel_clk,rst_n,reader_packet,reader_packet_valid,fifo_read_ready,pixel_packet,pixel_packet_valid,pixel_packet_ready,read_level,read_level_pixel);
 wire consume=shown_valid?in_de:1'b1;
 rgb888_frame_unpack #(.PIXELS(PIXELS)) unpack(pixel_clk,prst,pixel_packet_valid,pixel_packet_ready,pixel_packet,decoded_valid,consume,decoded_rgb,decoded_last,header_valid,decoded_slot,decoded_id,decoded_config,decoded_epoch,decoder_fault,decoded_header);
 reg have_header;reg [1:0] axi_fault_sync;
 always @(posedge pixel_clk or negedge prst)begin
  if(!prst)begin have_header<=0;axi_fault_sync<=0;out_de<=0;out_hsync<=1;out_vsync<=0;out_rgb<=0;end
  else begin
   axi_fault_sync<={axi_fault_sync[0],axi_fault|writer_fault|reader_fault};
   if(header_valid)have_header<=1;
   out_de<=in_de;out_hsync<=in_hsync;out_vsync<=in_vsync;
   out_rgb<=enable?(shown_valid&&decoded_valid?decoded_rgb:24'd0):in_rgb;
  end
 end
 assign shown_valid=have_header&&decoded_epoch==current_epoch&&enable;
 assign shown_frame_id=decoded_id;assign shown_config={decoded_header[127],decoded_config[30:0]};assign shown_epoch=decoded_epoch;
 assign shown_status=shown_valid&&!fault?decoded_header[99:98]:0;
 assign shown_track_id=shown_valid?decoded_header[115:100]:0;
 assign fault=local_fault|pack_fault|decoder_fault|pair_fault|axi_fault_sync[1];
endmodule
