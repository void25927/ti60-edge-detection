`timescale 1ns/1ps
// 连续RGB888字节序打包，不改色深；每16像素对应3个128位字。
// 00头部{epoch,config,fid,slot}，01数据，10最后数据；FIFO满禁止伪提交。
module rgb888_frame_pack #(parameter PIXELS=2073600)(
 input wire clk,rst_n,start,in_valid,
 input wire [23:0] in_rgb,
 input wire [1:0] slot,
 input wire [31:0] frame_id,frame_config,epoch,
 output reg out_valid,
 input wire out_ready,
 output reg [129:0] out_data,
 output reg fault,
 output reg [31:0] accepted_pixels
);
 reg [127:0] buffer;
 reg [7:0] bits;
 reg active;
 wire available=!out_valid||out_ready;
 wire [151:0] joined={24'd0,buffer}|({128'd0,in_rgb}<<bits);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin buffer<=0;bits<=0;active<=0;out_valid<=0;out_data<=0;fault<=0;accepted_pixels<=0;end
  else begin
   if(out_valid&&out_ready)out_valid<=0;
   if(start&&!fault)begin
    if(active || !available || PIXELS%16!=0 || PIXELS==0)fault<=1;
    else begin
     out_data<={2'b00,30'd0,epoch,frame_config,frame_id,slot};out_valid<=1;active<=1;
     buffer<=in_valid?{104'd0,in_rgb}:128'd0;bits<=in_valid?24:0;accepted_pixels<=in_valid?1:0;
    end
   end else if(in_valid&&active&&!fault)begin
    accepted_pixels<=accepted_pixels+1'b1;
    if(bits+24>=128)begin
     if(!available)begin fault<=1;active<=0;end
     else begin
      out_data<={(accepted_pixels==PIXELS-1)?2'b10:2'b01,joined[127:0]};out_valid<=1;
      buffer<=joined>>128;bits<=bits+24-128;
     end
    end else begin buffer<=joined[127:0];bits<=bits+24;end
    if(accepted_pixels==PIXELS-1)begin
     active<=0;if(bits!=104)fault<=1;
    end
   end
  end
 end
endmodule
