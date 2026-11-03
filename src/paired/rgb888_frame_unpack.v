`timescale 1ns/1ps
// 128位字节流解包；头部与像素同序，边界或数量错误锁存fault。
module rgb888_frame_unpack #(parameter PIXELS=2073600)(
 input wire clk,rst_n,
 input wire in_valid,
 output wire in_ready,
 input wire [129:0] in_data,
 output wire out_valid,
 input wire out_ready,
 output wire [23:0] out_rgb,
 output wire out_last,
 output reg header_valid,
 output reg [1:0] slot,
 output reg [31:0] frame_id,frame_config,epoch,
 output reg fault,
 output reg [127:0] frame_metadata
);
 reg [255:0] buffer;
 reg [8:0] bits;
 reg active,last_seen;
 reg [31:0] pixels,words;
 wire pop=out_valid&&out_ready;
 wire [8:0] remaining=bits-(pop?9'd24:9'd0);
 wire [255:0] shifted=pop?(buffer>>24):buffer;
 wire header=in_data[129:128]==0;
 assign out_valid=active&&bits>=24&&!fault;
 assign out_rgb=buffer[23:0];
 assign out_last=out_valid&&pixels==PIXELS-1;
 assign in_ready=!fault && (header?(!active&&bits==0):active&&!last_seen&&remaining<=128);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin buffer<=0;bits<=0;active<=0;last_seen<=0;pixels<=0;words<=0;header_valid<=0;slot<=0;frame_id<=0;frame_config<=0;epoch<=0;fault<=0;frame_metadata<=0;end
  else begin
   header_valid<=0;
   if(pop)begin
    buffer<=shifted;bits<=remaining;pixels<=pixels+1'b1;
    if(pixels==PIXELS-1)begin
     if(!last_seen || bits!=24)fault<=1;
     active<=0;
    end
   end
   if(in_valid&&in_ready)begin
    if(header)begin
     frame_metadata<=in_data[127:0];slot<=in_data[1:0];frame_id<=in_data[33:2];frame_config<=in_data[65:34];epoch<=in_data[97:66];
     active<=1;last_seen<=0;pixels<=0;words<=0;header_valid<=1;
    end else begin
     if(in_data[129:128]==3 || (in_data[129:128]==2)!=(words==PIXELS*3/16-1))fault<=1;
     buffer<=shifted|({128'd0,in_data[127:0]}<<remaining);bits<=remaining+128;
     words<=words+1'b1;if(in_data[129:128]==2)last_seen<=1;
    end
   end
  end
 end
endmodule
