`timescale 1ns/1ps
// 将一行内连续前景编码为闭区间；每拍接收一像素，空拍不结束区间。
module inspection_run_encoder #(
    parameter IMAGE_WIDTH=1920, IMAGE_HEIGHT=1080
)(
    input wire clk,rst_n,
    input wire in_valid,in_mask,in_frame_start,
    input wire [10:0] in_x,in_y,
    input wire [31:0] in_frame_id,
    output reg run_valid,
    output reg [10:0] run_x0,run_x1,run_y,
    output reg [31:0] run_frame_id,
    output reg frame_done,frame_bad,
    output reg [21:0] frame_pixels,
    output reg [20:0] frame_runs
);
    reg active,open_run;
    reg [10:0] expected_x,expected_y,start_x;
    reg [31:0] frame_id;
    wire new_frame=in_frame_start;
    wire [10:0] ex=new_frame ? 11'd0 : expected_x;
    wire [10:0] ey=new_frame ? 11'd0 : expected_y;
    wire eligible=in_valid && (active || new_frame);
    wire sequence_ok=(in_x==ex && in_y==ey &&
                      in_frame_id==(new_frame ? in_frame_id : frame_id));
    wire bad_now=(!new_frame && frame_bad) || !sequence_ok;
    wire was_open=!new_frame && open_run;
    wire last_x=(in_x==IMAGE_WIDTH-1);
    wire emit_run=eligible && !bad_now &&
                  ((!in_mask && was_open) || (in_mask && last_x));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            active<=0;open_run<=0;expected_x<=0;expected_y<=0;start_x<=0;frame_id<=0;
            run_valid<=0;run_x0<=0;run_x1<=0;run_y<=0;run_frame_id<=0;
            frame_done<=0;frame_bad<=0;frame_pixels<=0;frame_runs<=0;
        end else begin
            run_valid<=0;frame_done<=0;
            if(new_frame)begin
                active<=1;open_run<=0;expected_x<=0;expected_y<=0;
                frame_id<=in_frame_id;frame_bad<=0;frame_pixels<=0;frame_runs<=0;
            end
            if(eligible)begin
                frame_pixels<=new_frame ? 22'd1 : frame_pixels+1'b1;
                if(bad_now)begin
                    frame_bad<=1;open_run<=0;
                end else begin
                    if(in_mask && !was_open)start_x<=in_x;
                    open_run<=in_mask && !last_x;
                    if(emit_run)begin
                        run_valid<=1;
                        run_x0<=was_open ? start_x : in_x;
                        run_x1<=in_mask ? in_x : in_x-1'b1;
                        run_y<=in_y;run_frame_id<=in_frame_id;
                        frame_runs<=new_frame ? 21'd1 : frame_runs+1'b1;
                    end
                end
                // 即使本帧异常也排空至预期帧尾，frame_bad禁止结果提交。
                if(ex==IMAGE_WIDTH-1)begin
                    expected_x<=0;
                    if(ey==IMAGE_HEIGHT-1)begin
                        frame_done<=1;active<=0;open_run<=0;
                    end else expected_y<=ey+1'b1;
                end else expected_x<=ex+1'b1;
            end
        end
    end
endmodule
