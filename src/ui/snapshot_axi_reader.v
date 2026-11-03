`timescale 1ns/1ps
// 一次请求读取三张已提交截图的一行，输出带位置的RGB565像素流。
module snapshot_axi_reader #(
 parameter WIDTH=320,HEIGHT=180,
 parameter [31:0] BASE_ADDR=32'h02000000,SLOT_BYTES=32'h00020000,
 parameter [3:0] AXI_ID=4'h9
)(
 input wire clk,rst_n,
 input wire request,
 output wire request_ready,
 input wire [7:0] request_y,
 input wire [2:0] saved_valid,
 input wire [5:0] saved_slots,
 output wire [3:0] arid,
 output reg [31:0] araddr,
 output reg [7:0] arlen,
 output wire arvalid,
 input wire arready,
 input wire [127:0] rdata,
 input wire [3:0] rid,
 input wire [1:0] rresp,
 input wire rlast,rvalid,
 output wire rready,
 output wire pixel_valid,
 input wire pixel_ready,
 output wire [15:0] pixel_data,
 output wire [1:0] pixel_slot,
 output reg [8:0] pixel_x,
 output reg [7:0] pixel_y,
 output reg done,fault
);
 localparam IDLE=0,SELECT=1,PREPARE=2,ADDRESS=3,READ=4,DRAIN=5;
 reg [2:0] state;
 reg [2:0] valid_snapshot;
 reg [5:0] slots_snapshot;
 reg [2:0] lane;
 reg [5:0] beats_left;
 reg [127:0] burst_data[0:63]; // 两个32拍突发的队列，接收与像素拆包并行
 reg [1:0] burst_slot[0:63];
 reg [1:0] fetch_slot;
 reg [5:0] write_ptr,read_ptr;
 reg [6:0] queued;
 reg [127:0] output_word;
 reg [1:0] output_slot;
 reg output_valid;
 reg [8:0] requested_pixels;
 reg [31:0] next_address;
 wire [31:0] remaining_beats=(WIDTH-requested_pixels)/8;
 wire [8:0] boundary_beats=(13'd4096-{1'b0,next_address[11:0]})>>4;
 wire [8:0] short_beats=(remaining_beats<32)?remaining_beats:32;
 wire [8:0] next_beats=(boundary_beats<short_beats)?boundary_beats:short_beats;
 assign request_ready=(state==IDLE)&&!fault;
 assign arid=AXI_ID;
 assign arvalid=(state==ADDRESS);
 assign rready=(state==READ)&&(queued<64);
 assign pixel_valid=output_valid&&!fault;
 assign pixel_data=output_word[lane*16+:16];
 assign pixel_slot=output_slot;
 wire push=rvalid&&rready;
 wire pop=(queued!=0)&&(!output_valid||(pixel_ready&&lane==7)||fault);
 // 整字同步读写，数据阵列不复位，由队列计数屏蔽无效内容。
 always @(posedge clk)begin
  if(push)begin burst_data[write_ptr]<=rdata;burst_slot[write_ptr]<=fetch_slot;end
  if(pop)begin output_word<=burst_data[read_ptr];output_slot<=burst_slot[read_ptr];end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;valid_snapshot<=0;slots_snapshot<=0;
   lane<=0;beats_left<=0;next_address<=0;
   write_ptr<=0;read_ptr<=0;queued<=0;requested_pixels<=0;output_valid<=0;
   araddr<=0;arlen<=0;fetch_slot<=0;pixel_x<=0;pixel_y<=0;done<=0;fault<=0;
  end else begin
   done<=0;
   case({push,pop})
    2'b10:queued<=queued+1'b1;
    2'b01:queued<=queued-1'b1;
    default:begin end
   endcase
   if(push)write_ptr<=write_ptr+1'b1;
   if(pop)read_ptr<=read_ptr+1'b1;
   if(fault)output_valid<=0;
   else if(pop)output_valid<=1;
   else if(pixel_valid&&pixel_ready&&lane==7)output_valid<=0;
   if(pixel_valid&&pixel_ready)begin
    if(lane==7)lane<=0;else lane<=lane+1'b1;
    pixel_x<=(pixel_x==WIDTH-1)?0:pixel_x+1'b1;
   end
   case(state)
    IDLE:if(request&&request_ready)begin
     if(request_y>=HEIGHT || WIDTH%8!=0)fault<=1;
     else begin
      pixel_y<=request_y;fetch_slot<=0;pixel_x<=0;
      valid_snapshot<=saved_valid;slots_snapshot<=saved_slots;state<=SELECT;
     end
    end
    SELECT:begin
     requested_pixels<=0;
     if(valid_snapshot[fetch_slot])begin
      next_address<=BASE_ADDR+slots_snapshot[fetch_slot*2+:2]*SLOT_BYTES+pixel_y*WIDTH*2;
      state<=PREPARE;
     end else if(fetch_slot==2)state<=DRAIN;
     else fetch_slot<=fetch_slot+1'b1;
    end
    PREPARE:begin
     araddr<=next_address;arlen<=next_beats-1'b1;beats_left<=next_beats[5:0];state<=ADDRESS;
     requested_pixels<=requested_pixels+(next_beats<<3);
    end
    ADDRESS:if(arready)state<=READ;
    READ:if(rvalid&&rready)begin
     if(rresp!=0 || rid!=AXI_ID || rlast!=(beats_left==1))fault<=1;
     beats_left<=beats_left-1'b1;next_address<=next_address+16;
     if(beats_left==1)begin
      if(fault||rresp!=0||rid!=AXI_ID||!rlast)state<=DRAIN;
      else if(requested_pixels==WIDTH)begin
       if(fetch_slot==2)state<=DRAIN;
       else begin fetch_slot<=fetch_slot+1'b1;state<=SELECT;end
      end else state<=PREPARE;
     end
    end
    DRAIN:if(queued==0&&!output_valid)begin
     if(fault)state<=IDLE;
     else begin state<=IDLE;done<=1;end
    end
    default:begin fault<=1;state<=IDLE;end
   endcase
   // fault时队列只排空不输出，已发布的DDR突发仍完整接收。
  end
 end
endmodule
