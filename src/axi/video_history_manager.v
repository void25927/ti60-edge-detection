`timescale 1ns/1ps
// 原图帧槽保护：历史、当前显示和写入槽不互相覆盖。控制输入已整组跨域。
module video_history_manager #(
 parameter HISTORY_FRAMES=4, FRAME_SLOTS=6,
 parameter OFFSET_BITS=(HISTORY_FRAMES<=2)?1:$clog2(HISTORY_FRAMES),
 parameter COUNT_BITS=$clog2(HISTORY_FRAMES+1), INDEX_BITS=$clog2(FRAME_SLOTS)
)(
 input wire clk,rst,
 input wire [1:0] requested_mode,
 input wire [OFFSET_BITS-1:0] replay_offset,
 input wire [31:0] freeze_frame_id,
 input wire source_frame_boundary,write_frame_done,read_frame_boundary,
 output reg capture_enable,
 output reg [INDEX_BITS-1:0] write_index,read_index,
 output reg [1:0] active_mode,
 output reg [COUNT_BITS-1:0] history_count,
 output reg [31:0] read_frame_id,
 output reg read_valid,fault
);
 reg [INDEX_BITS-1:0] history[0:HISTORY_FRAMES-1];
 reg [31:0] slot_id[0:FRAME_SLOTS-1];
 reg [31:0] next_id;
 reg [FRAME_SLOTS-1:0] valid_slots;
 integer i,j,k;
 reg found,freeze_found,used;
 reg [INDEX_BITS-1:0] free_slot,freeze_slot,protected_read;
 wire [OFFSET_BITS-1:0] offset=(replay_offset<history_count)?replay_offset:0;
 always @(*)begin
  found=0;free_slot=0;freeze_found=0;freeze_slot=0;used=0;
  protected_read=read_index;
  // 同拍换读帧和提交写帧时，保护即将显示的槽，而不是已经释放的旧槽。
  if(read_frame_boundary&&requested_mode==2&&history_count!=0)protected_read=history[offset];
  else if(read_frame_boundary&&requested_mode==0)protected_read=write_index;
  else if(read_frame_boundary&&requested_mode==1)
   for(i=0;i<FRAME_SLOTS;i=i+1)if(valid_slots[i]&&slot_id[i]==freeze_frame_id)protected_read=i;
  for(i=0;i<FRAME_SLOTS;i=i+1)begin
   // 提交后最旧历史退出；新的写槽不能覆盖新历史前三帧或显示帧。
   used=(i==write_index)||(read_valid&&i==protected_read);
   for(j=0;j<HISTORY_FRAMES-1;j=j+1)if(j<history_count&&i==history[j])used=1;
   if(!used&&!found)begin free_slot=i;found=1;end
   if(valid_slots[i]&&slot_id[i]==freeze_frame_id)begin freeze_slot=i;freeze_found=1;end
  end
 end
 always @(posedge clk)begin
  if(rst)begin
   capture_enable<=1;write_index<=0;read_index<=FRAME_SLOTS-1;active_mode<=0;
   history_count<=0;read_frame_id<=0;read_valid<=0;fault<=0;next_id<=1;valid_slots<=0;
   for(k=0;k<HISTORY_FRAMES;k=k+1)history[k]<=0;
   for(k=0;k<FRAME_SLOTS;k=k+1)slot_id[k]<=0;
  end else begin
   if(write_frame_done&&capture_enable)begin
    slot_id[write_index]<=next_id;valid_slots[write_index]<=1;next_id<=next_id+1'b1;
    for(k=HISTORY_FRAMES-1;k>0;k=k-1)history[k]<=history[k-1];
    history[0]<=write_index;
    if(history_count<HISTORY_FRAMES)history_count<=history_count+1'b1;
    if(found)begin write_index<=free_slot;valid_slots[free_slot]<=0;end
    else begin fault<=1;capture_enable<=0;end
    if(requested_mode!=0)begin capture_enable<=0;active_mode<=requested_mode;end
   end
   if(!capture_enable&&requested_mode==0&&source_frame_boundary&&!fault)begin
    capture_enable<=1;active_mode<=0;
   end
   if(read_frame_boundary)begin
    if(requested_mode==1)begin
     if(freeze_found)begin read_index<=freeze_slot;read_frame_id<=freeze_frame_id;read_valid<=1;end
     else fault<=1;
    end else if(requested_mode==2&&history_count!=0)begin
     read_index<=history[offset];read_frame_id<=slot_id[history[offset]];read_valid<=1;
    end else if(requested_mode==0)begin
     if(write_frame_done&&capture_enable)begin read_index<=write_index;read_frame_id<=next_id;read_valid<=1;end
     else if(history_count!=0)begin read_index<=history[0];read_frame_id<=slot_id[history[0]];read_valid<=1;end
    end
    if(!capture_enable&&requested_mode!=0)active_mode<=requested_mode;
   end
  end
 end
endmodule
