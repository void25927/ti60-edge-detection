`timescale 1ns/1ps
// 仅统计HDMI场同步；不等同于相机帧率或识别吞吐。串行除法不在视频数据通路上。
module video_ui_metrics #(
    parameter CLK_FREQ_HZ=148800000
)(
    input wire clk,rst_n,frame_start,
    output reg [15:0] fps_bcd,
    output reg [19:0] frame_bcd
);
    reg seen;
    reg [31:0] elapsed,den,num,quot;
    reg [32:0] remn;
    reg [5:0] div_left;
    reg [16:0] frame_mod;
    reg [29:0] fps_shift;
    reg [36:0] frame_shift;
    reg [4:0] fps_left,frame_left;
    wire [32:0] trial={remn[31:0],num[31]};
    wire ge=(trial>={1'b0,den});
    wire [31:0] next_quot={quot[30:0],ge};
    wire [31:0] period_cycles=(&elapsed)?32'hffffffff:elapsed+1'b1;
    function [29:0] adjust_fps;
        input [29:0] s;
        reg [29:0] t; integer j;
        begin
            t=s;
            for(j=0;j<4;j=j+1)if(t[14+4*j+:4]>=5)t[14+4*j+:4]=t[14+4*j+:4]+4'd3;
            adjust_fps=t;
        end
    endfunction
    function [36:0] adjust_frame;
        input [36:0] s;
        reg [36:0] t; integer j;
        begin
            t=s;
            for(j=0;j<5;j=j+1)if(t[17+4*j+:4]>=5)t[17+4*j+:4]=t[17+4*j+:4]+4'd3;
            adjust_frame=t;
        end
    endfunction
    wire [29:0] next_fps=adjust_fps(fps_shift)<<1;
    wire [36:0] next_frame=adjust_frame(frame_shift)<<1;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            seen<=0;elapsed<=0;den<=1;num<=0;quot<=0;remn<=0;div_left<=0;
            frame_mod<=0;fps_shift<=0;frame_shift<=0;fps_left<=0;frame_left<=0;
            fps_bcd<=0;frame_bcd<=0;
        end else begin
            if(!(&elapsed))elapsed<=elapsed+1'b1;
            if(frame_start)begin
                seen<=1;elapsed<=0;
                frame_mod<=(frame_mod==99999)?0:frame_mod+1'b1;
                frame_shift<={20'd0,(frame_mod==99999)?17'd0:frame_mod+17'd1};
                frame_left<=17;
                // 首次场同步不构成完整周期，不显示伪造帧率。
                if(seen)begin
                    den<=period_cycles;
                    num<=CLK_FREQ_HZ*10+(period_cycles>>1);
                    remn<=0;quot<=0;div_left<=32;
                end
            end else if(div_left!=0)begin
                remn<=ge?trial-{1'b0,den}:trial;
                quot<=next_quot;num<={num[30:0],1'b0};div_left<=div_left-1'b1;
                if(div_left==1)begin
                    fps_shift<={16'd0,(next_quot>9999)?14'd9999:next_quot[13:0]};
                    fps_left<=14;
                end
            end
            if(frame_left!=0 && !frame_start)begin
                frame_shift<=next_frame;frame_left<=frame_left-1'b1;
                if(frame_left==1)frame_bcd<=next_frame[36:17];
            end
            if(fps_left!=0)begin
                fps_shift<=next_fps;fps_left<=fps_left-1'b1;
                if(fps_left==1)fps_bcd<=next_fps[29:14];
            end
        end
    end
endmodule
