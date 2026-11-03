`timescale 1ns/1ps
// 从已冻结、帧ID确定的显示源抓取缩略图。DDR服务须返回完整写应答后再提交。
module snapshot_capture #(
    parameter WIDTH=1920, HEIGHT=1080, SCALE=6,
    parameter [31:0] BASE_ADDR=32'h02000000,
    parameter [31:0] SLOT_BYTES=32'h00020000
)(
    input wire clk,rst_n,
    input wire request,cancel,
    input wire [31:0] requested_frame_id,
    input wire frame_start,frame_end,source_stable,
    input wire [31:0] source_frame_id,
    input wire in_valid,
    input wire [23:0] in_rgb,
    input wire write_ready,store_done,store_error,
    input wire display_boundary,display_reads_drained,
    output reg busy,done,error,
    output reg write_valid,
    output reg [31:0] write_address,
    output reg [15:0] write_pixel,
    output reg write_last,
    output reg abort_store,
    output reg [2:0] saved_valid,
    output reg [5:0] saved_slots,
    output reg [95:0] saved_frame_ids
);
    localparam TW=WIDTH/SCALE,TH=HEIGHT/SCALE;
    localparam WAIT_FRAME=1,CAPTURE=2,WAIT_STORE=3,COMMIT=4;
    reg [2:0] state;
    reg [31:0] target_id;
    reg [1:0] scratch_slot,replace_index;
    reg [31:0] pixel_count,sample_count;
    reg [$clog2(WIDTH)-1:0] x;
    reg [$clog2(HEIGHT)-1:0] y;
    reg [$clog2(SCALE)-1:0] sub_x,sub_y;
    reg bad_frame;
    reg store_completed; // 最后写应答可早于源帧结束，需保留到提交检查
    wire take_sample=(sub_x==0 && sub_y==0);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            busy<=0;done<=0;error<=0;write_valid<=0;write_last<=0;
            write_address<=0;write_pixel<=0;abort_store<=0;
            saved_valid<=0;saved_slots<={2'd2,2'd1,2'd0};saved_frame_ids<=0;
            scratch_slot<=3;replace_index<=0;state<=0;target_id<=0;
            store_completed<=0;
            x<=0;y<=0;sub_x<=0;sub_y<=0;pixel_count<=0;sample_count<=0;bad_frame<=0;
        end else begin
            done<=0;error<=0;abort_store<=0;
            if(store_done && busy)store_completed<=1;
            if(write_valid&&write_ready)begin write_valid<=0;write_last<=0;end
            if(cancel && busy)begin
                busy<=0;state<=0;write_valid<=0;abort_store<=1;
            end else if(store_error && busy)begin
                busy<=0;state<=0;write_valid<=0;error<=1;abort_store<=1;
            end else case(state)
                0:if(request)begin busy<=1;target_id<=requested_frame_id;state<=WAIT_FRAME;store_completed<=0;end
                WAIT_FRAME:if(frame_start && source_stable && source_frame_id==target_id)begin
                    x<=0;y<=0;sub_x<=0;sub_y<=0;pixel_count<=0;sample_count<=0;bad_frame<=0;state<=CAPTURE;
                end
                CAPTURE:begin
                    if(!source_stable || source_frame_id!=target_id)bad_frame<=1;
                    if(in_valid)begin
                        pixel_count<=pixel_count+1;
                        if(x==WIDTH-1)begin
                            x<=0;y<=y+1'b1;sub_x<=0;
                            sub_y<=(sub_y==SCALE-1)?0:sub_y+1'b1;
                        end else begin x<=x+1'b1;sub_x<=(sub_x==SCALE-1)?0:sub_x+1'b1;end
                        if(take_sample)begin
                            if((write_valid&&!write_ready)||pixel_count>=WIDTH*HEIGHT)bad_frame<=1;
                            else begin
                                write_valid<=1;write_address<=BASE_ADDR+scratch_slot*SLOT_BYTES+(sample_count<<1);
                                write_pixel<={in_rgb[23:19],in_rgb[15:10],in_rgb[7:3]};
                                write_last<=(sample_count==TW*TH-1);sample_count<=sample_count+1;
                            end
                        end
                    end
                    // frame_end在最后一个有效像素之后给出，不与最后像素同拍。
                    if(frame_end)begin
                        if(bad_frame || pixel_count!=WIDTH*HEIGHT || sample_count!=TW*TH ||
                           !source_stable || source_frame_id!=target_id)begin
                            busy<=0;state<=0;write_valid<=0;error<=1;abort_store<=1;
                        end else state<=WAIT_STORE;
                    end
                end
                WAIT_STORE:if((store_done || store_completed) && !write_valid)state<=COMMIT;
                COMMIT:if(display_boundary && display_reads_drained)begin
                    // 三张图保持槽位显示，第四次保存替换最早的一张。
                    scratch_slot<=saved_slots[replace_index*2+:2];
                    saved_slots[replace_index*2+:2]<=scratch_slot;
                    saved_frame_ids[replace_index*32+:32]<=target_id;
                    saved_valid[replace_index]<=1;
                    replace_index<=(replace_index==2)?0:replace_index+1'b1;
                    busy<=0;state<=0;done<=1;
                end
                default:begin busy<=0;state<=0;error<=1;end
            endcase
        end
    end
endmodule
