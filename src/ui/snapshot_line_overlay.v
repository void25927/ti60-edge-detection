`timescale 1ns/1ps
// DDR预取三张缩略图的当前/下一行；不在片上保存整张截图。
module snapshot_line_overlay #(
 parameter DISPLAY_WIDTH=1920,DISPLAY_HEIGHT=1080,THUMB_WIDTH=320,THUMB_HEIGHT=180,FOOTER_HEIGHT=0
)(
 input wire clk,rst_n,clear_lines,
 input wire [2:0] saved_valid,
 input wire load_valid,
 input wire [1:0] load_slot,
 input wire [8:0] load_x,
 input wire [7:0] load_y,
 input wire [15:0] load_pixel,
 input wire [10:0] in_x,in_y,
 input wire [23:0] in_rgb,
 input wire in_de,in_hsync,in_vsync,
 output wire [23:0] out_rgb,
 output reg out_de,out_hsync,out_vsync,
 output reg underflow_seen,load_error
);
 localparam LEFT=DISPLAY_WIDTH-3*THUMB_WIDTH,TOP=DISPLAY_HEIGHT-THUMB_HEIGHT-FOOTER_HEIGHT;
 reg [15:0] bank0[0:2*THUMB_WIDTH-1],bank1[0:2*THUMB_WIDTH-1],bank2[0:2*THUMB_WIDTH-1];
 reg [5:0] ready;
 reg [7:0] row_tag[0:5];
 reg [8:0] next_x[0:5];
 integer i;
 wire [2:0] load_index={load_slot,load_y[0]};
 wire [$clog2(2*THUMB_WIDTH)-1:0] write_addr=load_y[0]*THUMB_WIDTH+load_x;
 wire region=in_de && in_y>=TOP && in_y<TOP+THUMB_HEIGHT && in_x>=LEFT && in_x<DISPLAY_WIDTH;
 wire [1:0] slot=(in_x<LEFT+THUMB_WIDTH)?0:(in_x<LEFT+2*THUMB_WIDTH)?1:2;
 wire [10:0] sx=in_x-LEFT-slot*THUMB_WIDTH;
 wire [7:0] sy=in_y-TOP;
 wire [2:0] index={slot,sy[0]};
 wire [$clog2(2*THUMB_WIDTH)-1:0] read_addr=region ? sy[0]*THUMB_WIDTH+sx : 0;
 wire available=ready[index] && row_tag[index]==sy;
 reg [15:0] q0,q1,q2;
 reg [23:0] background;
 reg use_image,pixel_ready;
 reg [1:0] slot_d;
 wire [15:0] selected=(slot_d==0)?q0:(slot_d==1)?q1:q2;
 wire [23:0] expanded={selected[15:11],selected[15:13],selected[10:5],selected[10:9],selected[4:0],selected[4:2]};
 assign out_rgb=use_image ? (pixel_ready?expanded:24'd0) : background;
 // RAM不复位；ready/row_tag保证旧内容不会显示。
 always @(posedge clk)begin
   if(load_valid && load_slot<3 && load_x<THUMB_WIDTH && load_y<THUMB_HEIGHT && !clear_lines)begin
     case(load_slot)
       0:bank0[write_addr]<=load_pixel;
       1:bank1[write_addr]<=load_pixel;
       2:bank2[write_addr]<=load_pixel;
     endcase
   end
   q0<=bank0[read_addr];q1<=bank1[read_addr];q2<=bank2[read_addr];
 end
 always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin
     ready<=0;underflow_seen<=0;load_error<=0;
     background<=0;use_image<=0;pixel_ready<=0;slot_d<=0;
     out_de<=0;out_hsync<=0;out_vsync<=0;
     for(i=0;i<6;i=i+1)begin row_tag[i]<=0;next_x[i]<=0;end
   end else begin
     background<=in_de?in_rgb:0;use_image<=region&&saved_valid[slot];pixel_ready<=available;slot_d<=slot;
     out_de<=in_de;out_hsync<=in_hsync;out_vsync<=in_vsync;
     if(region&&saved_valid[slot]&&!available)underflow_seen<=1;
     if(clear_lines)begin ready<=0;for(i=0;i<6;i=i+1)next_x[i]<=0;end
     else if(load_valid)begin
       if(load_slot>=3 || load_x>=THUMB_WIDTH || load_y>=THUMB_HEIGHT)load_error<=1;
       else if(load_x==0)begin
         ready[load_index]<=(THUMB_WIDTH==1);row_tag[load_index]<=load_y;next_x[load_index]<=1;
       end else if(load_x==next_x[load_index] && row_tag[load_index]==load_y)begin
         next_x[load_index]<=load_x+1'b1;
         if(load_x==THUMB_WIDTH-1)ready[load_index]<=1;
       end else begin ready[load_index]<=0;load_error<=1;end
     end
   end
 end
endmodule
