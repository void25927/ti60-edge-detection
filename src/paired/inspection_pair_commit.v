`timescale 1ns/1ps
// 同一时钟域的配对提交表；图像最终B成功和算法结果齐备后才能发布。
// FIFO按分配顺序发布，显示端持有的槽只能显式release；不使用LAST替代。
module inspection_pair_commit #(
 parameter SLOTS=4, SLOT_BITS=$clog2(SLOTS), TIMEOUT=3200000
)(
 input wire clk,rst_n,clear_pending,
 input wire allocate,
 output wire allocate_ready,
 input wire [31:0] frame_id,frame_config,
 output wire [SLOT_BITS-1:0] allocate_slot,
 output wire [31:0] epoch,
 input wire image_done,image_error,
 input wire [SLOT_BITS-1:0] image_slot,
 input wire [31:0] image_frame_id,image_epoch,
 input wire result_done,result_error,
 input wire [31:0] result_frame_id,result_epoch,
 input wire [1:0] result_status,
 input wire [15:0] result_track_id,
 output wire publish_valid,
 input wire publish_ready,
 output wire [SLOT_BITS-1:0] publish_slot,
 output wire [31:0] publish_frame_id,publish_config,
 output wire [1:0] publish_status,
 output wire [15:0] publish_track_id,
 input wire release_valid,
 input wire [SLOT_BITS-1:0] release_slot,
 output reg fault,
 output reg [3:0] fault_code,
 output reg [SLOT_BITS:0] queued,high_water
);
 reg [SLOTS-1:0] busy,held,pixels,results;
 reg [31:0] ids[0:SLOTS-1],configs[0:SLOTS-1];
 reg [1:0] statuses[0:SLOTS-1];
 reg [15:0] tracks[0:SLOTS-1];
 reg [31:0] ages[0:SLOTS-1];
 reg [SLOT_BITS-1:0] order[0:SLOTS-1];
 reg [SLOT_BITS-1:0] wr,rd,free_slot,hit;
 reg found,matched;
 reg [31:0] generation;
 integer i,k;
 always @(*)begin
  found=0;free_slot=0;matched=0;hit=0;
  for(k=0;k<SLOTS;k=k+1)begin
   if(!busy[k]&&!found)begin found=1;free_slot=k;end
   if(busy[k]&&!held[k]&&ids[k]==result_frame_id)begin matched=1;hit=k;end
  end
 end
 wire [SLOT_BITS-1:0] head=order[rd];
 assign allocate_ready=found&&!fault&&!clear_pending&&queued<SLOTS;
 assign allocate_slot=free_slot;
 assign epoch=generation;
 assign publish_valid=queued!=0&&!fault&&!clear_pending&&busy[head]&&!held[head]&&pixels[head]&&results[head];
 assign publish_slot=head;
 assign publish_frame_id=ids[head];assign publish_config=configs[head];
 assign publish_status=statuses[head];assign publish_track_id=tracks[head];
 wire push=allocate&&allocate_ready;
 wire pop=publish_valid&&publish_ready;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   busy<=0;held<=0;pixels<=0;results<=0;wr<=0;rd<=0;generation<=0;
   queued<=0;high_water<=0;fault<=0;fault_code<=0;
  end else begin
   if(release_valid)begin
    if(release_slot>=SLOTS || !held[release_slot])begin fault<=1;fault_code<=1;end
    else begin held[release_slot]<=0;busy[release_slot]<=0;end
   end
   if(clear_pending)begin
    // 显示持有帧不被覆盖；旧时代异步返回在下方按epoch拒收。
    busy<=held;pixels<=0;results<=0;queued<=0;wr<=0;rd<=0;
    generation<=generation+1'b1;
    if(release_valid&&release_slot<SLOTS&&held[release_slot])busy[release_slot]<=0;
   end else if(!fault)begin
    case({push,pop})2'b10:queued<=queued+1'b1;2'b01:queued<=queued-1'b1;default:begin end endcase
    if(push&&!pop&&queued+1'b1>high_water)high_water<=queued+1'b1;
    if(push)begin
     busy[free_slot]<=1;held[free_slot]<=0;pixels[free_slot]<=0;results[free_slot]<=0;
     ids[free_slot]<=frame_id;configs[free_slot]<=frame_config;ages[free_slot]<=0;
     order[wr]<=free_slot;wr<=(wr==SLOTS-1)?0:wr+1'b1;
     for(i=0;i<SLOTS;i=i+1)if(busy[i]&&ids[i]==frame_id)begin fault<=1;fault_code<=2;end
    end
    if(pop)begin held[head]<=1;rd<=(rd==SLOTS-1)?0:rd+1'b1;end
    for(i=0;i<SLOTS;i=i+1)if(busy[i]&&!held[i]&&!(pixels[i]&&results[i]))begin
     if(ages[i]>=TIMEOUT)begin fault<=1;fault_code<=3;end else ages[i]<=ages[i]+1'b1;
    end
    if(image_done&&image_epoch==generation)begin
     if(image_error || image_slot>=SLOTS || !busy[image_slot] || held[image_slot] || ids[image_slot]!=image_frame_id || pixels[image_slot])begin fault<=1;fault_code<=4;end
     else pixels[image_slot]<=1;
    end
    if(result_done&&result_epoch==generation)begin
     if(result_error || !matched || results[hit])begin fault<=1;fault_code<=5;end
     else begin results[hit]<=1;statuses[hit]<=result_status;tracks[hit]<=result_track_id;end
    end
   end
  end
 end
endmodule
