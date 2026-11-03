`timescale 1ns/1ps
// 显示帧的紧凑匹配特征：只存比较器实际消费的768位宽度表+46位几何量。
// 13个64位字/槽；计数直方图不参与现有比较，重建时置零而不改有效特征。
module inspection_display_features(
 input wire clk,rst_n,
 input wire invalidate,
 input wire [1:0] invalidate_slot,
 input wire write_valid,
 output wire write_ready,
 input wire [1:0] write_slot,
 input wire [3:0] write_index,
 input wire [63:0] write_data,
 input wire write_last,write_bad,
 input wire [31:0] write_frame_id,write_config,write_epoch,
 input wire query,
 output wire query_ready,
 input wire [31:0] query_frame_id,query_epoch,
 output wire out_valid,
 input wire out_ready,
 output wire [1837:0] descriptor,
 output reg [31:0] out_frame_id,out_config,
 output reg out_bad,
 output reg fault
);
 reg [64:0] memory[0:127];
 reg [64:0] read_q;
 reg [3:0] valid,bad;
 reg [31:0] ids[0:3],configs[0:3],epochs[0:3];
 reg writing;
 reg [1:0] wslot,rslot;
 reg [3:0] expected,index;
 reg [831:0] restored;
 reg restored_valid;
 reg [2:0] state;
 localparam IDLE=0,ISSUE=1,COPY=2,RESPONSE=3;
 reg found;reg [1:0] selected;integer i;
 always @(*)begin
  found=0;selected=0;
  for(i=0;i<4;i=i+1)if(valid[i]&&ids[i]==query_frame_id&&epochs[i]==query_epoch)begin found=1;selected=i;end
 end
 wire invalidate_read=invalidate&&invalidate_slot==rslot&&state!=IDLE;
 assign write_ready=!fault;
 assign query_ready=state==IDLE;
 assign out_valid=state==RESPONSE&&!invalidate_read;
 assign descriptor={restored_valid?restored[813:0]:814'd0,1024'd0};
 wire [6:0] write_address={write_slot,1'b0,write_index};
 wire [6:0] read_address={rslot,1'b0,index};
 wire accepted_write=write_valid&&write_ready&&write_index<=12&&
  ((!writing&&write_index==0&&!valid[write_slot])||(writing&&write_slot==wslot&&write_index==expected&&write_frame_id==ids[wslot]&&write_config==configs[wslot]&&write_epoch==epochs[wslot]));
 always @(posedge clk)begin
  if(accepted_write)memory[write_address]<={^write_data,write_data};
  read_q<=memory[read_address];
  // 数据寄存器不复位；有效位仅在13字全部装载后开放，未命中仍输出全零。
  if(state==COPY)restored<={read_q[63:0],restored[831:64]};
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin valid<=0;bad<=0;writing<=0;wslot<=0;rslot<=0;expected<=0;index<=0;restored_valid<=0;state<=IDLE;out_frame_id<=0;out_config<=0;out_bad<=0;fault<=0;end
  else begin
   if(write_valid&&write_ready)begin
    if(!accepted_write||write_last!=(write_index==12))begin fault<=1;valid[write_slot]<=0;writing<=0;end
    else begin
     if(!writing)begin writing<=1;wslot<=write_slot;ids[write_slot]<=write_frame_id;configs[write_slot]<=write_config;epochs[write_slot]<=write_epoch;bad[write_slot]<=write_bad;end
     else if(write_bad)bad[write_slot]<=1;
     expected<=write_index+1'b1;
     if(write_last)begin valid[write_slot]<=1;writing<=0;end
    end
   end
   case(state)
    IDLE:if(query)begin
     restored_valid<=0;out_frame_id<=query_frame_id;out_config<=found?configs[selected]:0;out_bad<=!found;
     index<=0;rslot<=selected;
     if(found)begin out_bad<=bad[selected];state<=ISSUE;end else state<=RESPONSE;
    end
    ISSUE:state<=COPY;
    COPY:begin
     // 按0～12字顺序恢复：最后一字留在高位，避免832位动态写选择网络。
     if((^read_q)!==1'b0)begin out_bad<=1;fault<=1;end
     if(index==12)begin restored_valid<=1;state<=RESPONSE;end else begin index<=index+1'b1;state<=ISSUE;end
    end
    RESPONSE:if(out_valid&&out_ready)state<=IDLE;
    default:begin fault<=1;state<=IDLE;end
   endcase
   if(invalidate)begin
    valid[invalidate_slot]<=0;
    if(writing&&wslot==invalidate_slot)begin writing<=0;fault<=1;end
    if(invalidate_read)begin out_bad<=1;state<=RESPONSE;end
   end
  end
 end
endmodule
