`timescale 1ns/1ps
// 复用上游FIFO存储：整突发可用后才申请DDR，B成功后才提交。
module paired_frame_writer_stream #(
 parameter FRAME_BYTES=6220800,MAX_BEATS=64
)(
 input wire clk,rst_n,start,output wire start_ready,
 input wire [31:0] base_address,frame_id,frame_epoch,
 input wire [127:0] in_data,input wire in_valid,in_last,output wire in_ready,
 output wire command_valid,input wire command_ready,
 output reg [31:0] command_address,output reg [7:0] command_length,
 output wire [127:0] write_data,output wire write_valid,write_last,
 input wire write_ready,response_valid,input wire [1:0] response_code,
 output wire response_ready,output reg done,fault,
 output reg [31:0] completed_id,completed_epoch,words_written,bursts,
 input wire [31:0] available_words
);
 localparam IDLE=0,WAIT_WORDS=1,COMMAND=2,DATA=3,RESPONSE=4;
 localparam WORDS=FRAME_BYTES/16;
 reg [2:0] state;
 reg [31:0] fid,epoch,remaining;
 reg [7:0] beat;
 wire [8:0] boundary=(13'd4096-{1'b0,command_address[11:0]})>>4;
 wire [31:0] boundary_limit=boundary<MAX_BEATS?boundary:MAX_BEATS;
 wire [31:0] amount=remaining<boundary_limit?remaining:boundary_limit;
 assign start_ready=state==IDLE&&!fault;
 assign command_valid=state==COMMAND&&!fault;
 assign write_valid=state==DATA&&in_valid&&!fault;
 assign write_data=in_data;
 assign write_last=beat==command_length;
 assign in_ready=state==DATA&&write_ready&&!fault;
 assign response_ready=state==RESPONSE;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;command_address<=0;command_length<=0;done<=0;fault<=0;fid<=0;epoch<=0;remaining<=0;beat<=0;completed_id<=0;completed_epoch<=0;words_written<=0;bursts<=0;end
  else begin
   done<=0;
   case(state)
    IDLE:if(start&&start_ready)begin
     if(base_address[3:0]!=0||FRAME_BYTES%16!=0||WORDS==0||MAX_BEATS<1||MAX_BEATS>128)fault<=1;
     else begin command_address<=base_address;fid<=frame_id;epoch<=frame_epoch;remaining<=WORDS;words_written<=0;bursts<=0;state<=WAIT_WORDS;end
    end
    WAIT_WORDS:if(available_words>=amount)begin command_length<=amount-1'b1;beat<=0;state<=COMMAND;end
    COMMAND:if(command_valid&&command_ready)state<=DATA;
    DATA:if(write_valid&&write_ready)begin
     if(in_last!=(remaining==beat+1))begin fault<=1;end
     if(write_last)state<=RESPONSE;else beat<=beat+1'b1;
    end
    RESPONSE:if(response_valid)begin
     if(response_code!=0)begin fault<=1;state<=IDLE;end
     else begin
      words_written<=words_written+command_length+1'b1;bursts<=bursts+1'b1;
      if(remaining==command_length+1)begin completed_id<=fid;completed_epoch<=epoch;done<=1;state<=IDLE;end
      else begin remaining<=remaining-command_length-1'b1;command_address<=command_address+({24'd0,command_length}+1)*16;state<=WAIT_WORDS;end
     end
    end
    default:begin fault<=1;state<=IDLE;end
   endcase
  end
 end
endmodule
