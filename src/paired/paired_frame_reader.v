`timescale 1ns/1ps
// 整帧读DMA：128位FWFT输出接异步FIFO；消费者背压直接约束RREADY。
module paired_frame_reader #(parameter FRAME_BYTES=6220800,MAX_BEATS=64,FIFO_CREDIT=0)(
 input wire clk,rst_n,start,
 output wire start_ready,
 input wire [31:0] base_address,
 input wire [127:0] header_data,
 output wire command_valid,
 input wire command_ready,
 output reg [31:0] command_address,
 output wire [7:0] command_length,
 input wire [127:0] read_data,
 input wire read_valid,read_last,
 input wire [1:0] read_code,
 output wire read_ready,
 output wire out_valid,
 input wire out_ready,
 output wire [129:0] out_data,
 output reg done,fault,
 input wire [31:0] output_space
);
 localparam IDLE=0,HEADER=1,PREP=2,COMMAND=3,DATA=4;
 reg [2:0] state;
 reg [127:0] header_q;
 reg [8:0] left,length;
 reg [31:0] words;
 wire [8:0] boundary_words=(13'd4096-{1'b0,command_address[11:0]})>>4;
 wire [31:0] remaining=FRAME_BYTES/16-words;
 wire [31:0] bounded=boundary_words<MAX_BEATS?boundary_words:MAX_BEATS;
 assign start_ready=state==IDLE&&!fault;
 // 单事务共享总线不得在显示消隐时锁住一个无法排空的读突发。
 // 写端域FIFO水位是保守值：仅在整突发都有空间时发命令。
 assign command_valid=state==COMMAND&&!fault&&(!FIFO_CREDIT || output_space>=length);
 assign command_length=length-1'b1;
 assign out_valid=!fault&&((state==HEADER)||(state==DATA&&read_valid));
 assign out_data=state==HEADER?{2'b00,header_q}:{(words==FRAME_BYTES/16-1)?2'b10:2'b01,read_data};
 assign read_ready=state==DATA&&out_ready&&!fault;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;header_q<=0;command_address<=0;left<=0;length<=0;words<=0;done<=0;fault<=0;end
  else begin
   done<=0;
   case(state)
    IDLE:if(start&&!fault)begin
     if(base_address[3:0]!=0 || FRAME_BYTES%16!=0 || FRAME_BYTES==0 || MAX_BEATS<1 || MAX_BEATS>256)fault<=1;
     else begin command_address<=base_address;header_q<=header_data;words<=0;state<=HEADER;end
    end
    HEADER:if(out_ready)state<=PREP;
    PREP:begin length<=remaining<bounded?remaining:bounded;left<=remaining<bounded?remaining:bounded;state<=COMMAND;end
    COMMAND:if(command_valid&&command_ready)state<=DATA;
    DATA:if(read_valid&&read_ready)begin
     if(read_code!=0 || read_last!=(left==1))begin fault<=1;state<=IDLE;end
     else begin
      words<=words+1'b1;left<=left-1'b1;
      if(words==FRAME_BYTES/16-1)begin state<=IDLE;done<=1;end
      else if(left==1)begin command_address<=command_address+({23'd0,length}<<4);state<=PREP;end
     end
    end
    default:begin fault<=1;state<=IDLE;end
   endcase
  end
 end
endmodule
