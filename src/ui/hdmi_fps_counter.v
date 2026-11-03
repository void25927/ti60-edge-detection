`timescale 1ns/1ps
// HDMI场同步计数：一个像素时钟秒内的完整场边沿数，不代表算法吞吐。
module hdmi_fps_counter #(
    parameter integer CLK_HZ=148800000,
    parameter VSYNC_ACTIVE_LEVEL=1'b0
)(
    input wire clk,rst_n,vsync,
    output reg [11:0] fps_bcd,
    output reg fps_valid,fps_update,
    output wire [7:0] char_hundreds,char_tens,char_units
);
    localparam CW=(CLK_HZ>1)?$clog2(CLK_HZ):1;
    reg [CW-1:0] tick;
    reg [9:0] frames;
    reg vs_d;
    wire edge_seen=(vsync==VSYNC_ACTIVE_LEVEL)&&(vs_d!=VSYNC_ACTIVE_LEVEL);
    wire [10:0] total={1'b0,frames}+edge_seen;
    wire [9:0] bounded=(total>999)?10'd999:total[9:0];
    assign char_hundreds=!fps_valid?8'h2d:8'h30+{4'd0,fps_bcd[11:8]};
    assign char_tens=!fps_valid?8'h2d:8'h30+{4'd0,fps_bcd[7:4]};
    assign char_units=!fps_valid?8'h2d:8'h30+{4'd0,fps_bcd[3:0]};
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin tick<=0;frames<=0;vs_d<=VSYNC_ACTIVE_LEVEL;
            fps_bcd<=0;fps_valid<=0;fps_update<=0;end
        else begin
            vs_d<=vsync;fps_update<=0;
            if(tick==CLK_HZ-1)begin
                tick<=0;frames<=0;fps_update<=1;fps_valid<=1;
                fps_bcd[11:8]<=bounded/100;
                fps_bcd[7:4]<=(bounded%100)/10;
                fps_bcd[3:0]<=bounded%10;
            end else begin
                tick<=tick+1'b1;
                if(edge_seen && frames<999)frames<=frames+1'b1;
            end
        end
    end
endmodule
