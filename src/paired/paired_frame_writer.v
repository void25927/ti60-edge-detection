`timescale 1ns/1ps
// 已打包RGB888整帧写服务；输入必须来自可背压FIFO。仅最后B成功才提交。
module paired_frame_writer #(
 parameter FRAME_BYTES=6220800,MAX_BEATS=64
)(
 input wire clk,rst_n,start,
 output wire start_ready,
 input wire [31:0] base_address,frame_id,frame_epoch,
 input wire [127:0] in_data,
 input wire in_valid,in_last,
 output wire in_ready,
 output wire command_valid,
 input wire command_ready,
 output reg [31:0] command_address,
 output reg [7:0] command_length,
 output wire [127:0] write_data,
 output wire write_valid,write_last,
 input wire write_ready,response_valid,
 input wire [1:0] response_code,
 output wire response_ready,
 output reg done,fault,
 output reg [31:0] completed_id,completed_epoch,
 output reg [31:0] words_written,bursts
);
 localparam IDLE=0,COMMAND=2,DATA=3,RESPONSE=4;
 localparam WORDS=FRAME_BYTES/16;
 localparam RAM_ADDRESS_BITS=$clog2(2*MAX_BEATS);
 reg [2:0] state;
 // 双区轮转：收集下一突发与当前突发发送重叠；在B完成前不释放读区。
 reg [127:0] memory[0:2*MAX_BEATS-1];
 reg [127:0] output_q;
 reg [7:0] fill,beat;
 reg active,fill_bank,read_bank;
 reg [1:0] banks_ready;
 reg [31:0] next_address,total_received;
 reg [31:0] bank_address[0:1];
 reg [7:0] bank_length[0:1];
 reg [1:0] bank_final;
 reg [31:0] fid,epoch;
 wire accept=in_valid&&in_ready;
 wire [8:0] boundary_words=(13'd4096-{1'b0,next_address[11:0]})>>4;
 wire [31:0] remaining=WORDS-(total_received-fill);
 wire [31:0] boundary_limit=boundary_words<MAX_BEATS?boundary_words:MAX_BEATS;
 wire [7:0] next_limit=remaining<boundary_limit?remaining:boundary_limit;
 wire [RAM_ADDRESS_BITS-1:0] ram_write_address=fill_bank*MAX_BEATS+fill;
 wire [RAM_ADDRESS_BITS-1:0] ram_read_address=(state==COMMAND)?read_bank*MAX_BEATS:
  read_bank*MAX_BEATS+beat+((state==DATA&&write_ready&&!write_last)?1'b1:1'b0);
 assign start_ready=!active&&state==IDLE&&!fault;
 assign in_ready=active&&!banks_ready[fill_bank]&&total_received<WORDS&&!fault;
 assign command_valid=state==COMMAND&&!fault;
 assign write_valid=state==DATA&&!fault;
 assign write_last=beat==command_length;
 assign write_data=output_q;
 assign response_ready=state==RESPONSE;
 // 写缓冲同步读，输出停顿时不改变；首拍预读在COMMAND期间完成。
 always @(posedge clk)begin
  if(accept)memory[ram_write_address]<=in_data;
  // 单一同步读口；停顿时地址保持当前拍，避免综合器拆成两组异步选择树。
  output_q<=memory[ram_read_address];
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;done<=0;fault<=0;fid<=0;epoch<=0;completed_id<=0;completed_epoch<=0;
   words_written<=0;bursts<=0;command_address<=0;command_length<=0;fill<=0;beat<=0;
   active<=0;fill_bank<=0;read_bank<=0;banks_ready<=0;next_address<=0;total_received<=0;bank_final<=0;
  end else begin
   done<=0;
   if(accept)begin
    if(in_last!=(total_received+1==WORDS))begin fault<=1;active<=0;end
    else begin
     total_received<=total_received+1'b1;
     if(fill+1==next_limit)begin
      bank_address[fill_bank]<=next_address;bank_length[fill_bank]<=fill;
      bank_final[fill_bank]<=total_received+1==WORDS;
      banks_ready[fill_bank]<=1;fill<=0;fill_bank<=!fill_bank;
      next_address<=next_address+({24'd0,fill}+1)*16;
     end else fill<=fill+1'b1;
    end
   end
   case(state)
    IDLE:if(start&&start_ready)begin
     if(base_address[3:0]!=0 || FRAME_BYTES%16!=0 || WORDS==0 || MAX_BEATS<1 || MAX_BEATS>128)fault<=1;
     else begin fid<=frame_id;epoch<=frame_epoch;next_address<=base_address;words_written<=0;bursts<=0;fill<=0;active<=1;total_received<=0;fill_bank<=0;read_bank<=0;banks_ready<=0;end
    end else if(active&&banks_ready[read_bank]&&!fault)begin command_address<=bank_address[read_bank];command_length<=bank_length[read_bank];beat<=0;state<=COMMAND;end
    COMMAND:if(command_ready)state<=DATA;
    DATA:if(write_ready)begin
     if(write_last)state<=RESPONSE;else beat<=beat+1'b1;
    end
    RESPONSE:if(response_valid)begin
     if(response_code!=0)begin fault<=1;state<=IDLE;active<=0;end
     else begin
      words_written<=words_written+command_length+1'b1;bursts<=bursts+1'b1;
      banks_ready[read_bank]<=0;read_bank<=!read_bank;state<=IDLE;
      if(bank_final[read_bank])begin
       completed_id<=fid;completed_epoch<=epoch;done<=1;active<=0;
      end
     end
    end
    default:begin fault<=1;state<=IDLE;end
   endcase
  end
 end
endmodule
