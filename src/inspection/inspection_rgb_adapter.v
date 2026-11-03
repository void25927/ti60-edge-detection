`timescale 1ns/1ps
// 旁路采样正式AWB后的RGB；不对视频施加背压。重复/历史帧不推进跟踪。
module inspection_rgb_adapter #(
    parameter IMAGE_WIDTH=1920, IMAGE_HEIGHT=1080,
    parameter BG_X0=448, BG_X1=1472,FOREGROUND_THRESHOLD=32,SESSION_CONTROL=0
)(
    input wire clk,rst_n,in_valid,in_vsync,
    input wire [23:0] in_rgb,
    input wire [31:0] source_frame_id,
    input wire source_frame_valid,live_mode,engine_ready,
    input wire calibrate_request,learn_request,
    output reg out_valid,out_start,out_learn,
    output reg [10:0] out_x,out_y,
    output reg [23:0] out_rgb,
    output reg [31:0] out_frame_id,
    output reg [23:0] background,
    output reg background_ready,calibrating,
    output reg fault,
    output reg [31:0] accepted_frames,repeated_frames,busy_frames,pixel_count,
    output reg [7:0] threshold,
    input wire session_clear
);
    reg [10:0] x,y;
    reg was_valid,vs_d,armed,capture,cal_frame,learn_pending,cal_pending,have_last;
    reg [31:0] frame_id,last_id;
    reg [15:0] sr,sg,sb;
    reg [8:0] samples;
    reg [7:0] minr,ming,minb,maxr,maxg,maxb;
    wire first=in_valid && armed;
    // 顶部背景带共128个样本；每个LIVE帧更新供下一帧使用，跟随AE亮度慢变。
    // 样本不均匀时保留旧背景，避免器件进入采样带后污染背景模型。
    wire sample=in_valid && x>=BG_X0 && x<BG_X1 && x[5:0]==32 && y>=8 && y<16;
    wire last=in_valid && x==IMAGE_WIDTH-1 && y==IMAGE_HEIGHT-1;
    wire candidate=source_frame_valid && live_mode && background_ready &&
                   (!have_last || source_frame_id!=last_id);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            x<=0;y<=0;was_valid<=0;vs_d<=0;armed<=1;capture<=0;cal_frame<=0;
            learn_pending<=0;cal_pending<=1;have_last<=0;frame_id<=0;last_id<=0;
            sr<=0;sg<=0;sb<=0;samples<=0;minr<=255;ming<=255;minb<=255;maxr<=0;maxg<=0;maxb<=0;
            out_valid<=0;out_start<=0;out_learn<=0;out_x<=0;out_y<=0;out_rgb<=0;out_frame_id<=0;
            background<=0;background_ready<=0;calibrating<=0;fault<=0;threshold<=FOREGROUND_THRESHOLD;
            accepted_frames<=0;repeated_frames<=0;busy_frames<=0;pixel_count<=0;
        end else begin
            was_valid<=in_valid;vs_d<=in_vsync;out_valid<=0;out_start<=0;out_learn<=0;
            if(calibrate_request)begin cal_pending<=1;background_ready<=0;learn_pending<=0;end
            else if(learn_request)learn_pending<=1;
            // 源vsync为高有效帧包络：只在上升沿重新武装，不把行间空拍误认成新帧。
            if(in_vsync && !vs_d)begin
                if(capture && pixel_count!=IMAGE_WIDTH*IMAGE_HEIGHT)fault<=1;
                x<=0;y<=0;armed<=1;capture<=0;pixel_count<=0;
            end
            if(was_valid && !in_valid && !armed)begin
                if(x!=0)fault<=1;
                if(y<IMAGE_HEIGHT-1)y<=y+1'b1;
            end
            if(in_valid)begin
                if(first)begin
                    armed<=0;frame_id<=source_frame_id;x<=1;y<=0;pixel_count<=1;
                    capture<=candidate && engine_ready && !cal_pending;
                    cal_frame<=live_mode && source_frame_valid;
                    if(live_mode && source_frame_valid)begin
                        calibrating<=!background_ready;cal_pending<=0;sr<=0;sg<=0;sb<=0;samples<=0;
                        minr<=255;ming<=255;minb<=255;maxr<=0;maxg<=0;maxb<=0;
                    end
                    if(candidate && !cal_pending)begin
                        if(engine_ready)begin
                            out_valid<=1;out_start<=1;out_learn<=learn_pending;learn_pending<=0;
                            out_x<=0;out_y<=0;out_rgb<=in_rgb;out_frame_id<=source_frame_id;
                            last_id<=source_frame_id;have_last<=1;accepted_frames<=accepted_frames+1'b1;
                        end else begin busy_frames<=busy_frames+1'b1;fault<=1;end
                    end else if(source_frame_valid && have_last && source_frame_id==last_id)
                        repeated_frames<=repeated_frames+1'b1;
                end else begin
                    pixel_count<=pixel_count+1'b1;
                    x<=(x==IMAGE_WIDTH-1)?11'd0:x+1'b1;
                    if(capture)begin
                        out_valid<=1;out_x<=x;out_y<=y;out_rgb<=in_rgb;out_frame_id<=frame_id;
                        if(source_frame_id!=frame_id || !source_frame_valid)begin
                            // 不静默更换帧号：污染像素携带错误ID，由下游拒绝本帧。
                            out_frame_id<=~frame_id;fault<=1;
                        end
                    end
                end
                if(cal_frame && sample)begin
                    sr<=sr+in_rgb[23:16];sg<=sg+in_rgb[15:8];sb<=sb+in_rgb[7:0];samples<=samples+1'b1;
                    if(in_rgb[23:16]<minr)minr<=in_rgb[23:16];if(in_rgb[23:16]>maxr)maxr<=in_rgb[23:16];
                    if(in_rgb[15:8]<ming)ming<=in_rgb[15:8];if(in_rgb[15:8]>maxg)maxg<=in_rgb[15:8];
                    if(in_rgb[7:0]<minb)minb<=in_rgb[7:0];if(in_rgb[7:0]>maxb)maxb<=in_rgb[7:0];
                end
                if(last)begin
                    capture<=0;
                    if(cal_frame)begin
                        calibrating<=0;cal_frame<=0;
                        if(samples==128 && maxr-minr<=24 && maxg-ming<=24 && maxb-minb<=24)begin
                            background<={sr[14:7],sg[14:7],sb[14:7]};background_ready<=1;
                            if(!background_ready)have_last<=0;
                        end else if(!background_ready)cal_pending<=1;
                    end
                end
            end
            if(SESSION_CONTROL && session_clear===1'b1)begin
                out_valid<=0;out_start<=0;out_learn<=0;capture<=0;armed<=1;have_last<=0;learn_pending<=0;
                // 保留已校准背景，下一LIVE完整帧重新开始采样。
                cal_frame<=0;calibrating<=0;x<=0;y<=0;
            end
        end
    end
endmodule
