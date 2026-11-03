`timescale 1ns/1ps
// 8项完整帧号匹配缓存。历史图像无结果时返回UNKNOWN，不按低位索引冒认。
module inspection_result_history #(
    parameter PAYLOAD_WIDTH=832
)(
    input wire clk,rst_n,invalidate,commit_valid,
    input wire [31:0] commit_frame_id,
    input wire [PAYLOAD_WIDTH-1:0] commit_payload,
    input wire select_frame,
    input wire [31:0] display_frame_id,
    input wire display_valid,
    output reg matched,
    output reg [31:0] selected_frame_id,
    output reg [PAYLOAD_WIDTH-1:0] selected_payload
);
    reg [7:0] valid;
    reg [31:0] ids[0:7];
    reg [PAYLOAD_WIDTH-1:0] data[0:7];
    reg [2:0] wr;
    integer i;
    // 有效位复位即可；大数据阵列不复位，允许推断存储。
    always @(posedge clk)if(commit_valid && !invalidate)begin
        ids[wr]<=commit_frame_id;data[wr]<=commit_payload;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin valid<=0;wr<=0;matched<=0;selected_frame_id<=0;selected_payload<=0;end
        else if(invalidate)begin valid<=0;matched<=0;selected_payload<=0;wr<=0;end
        else begin
            if(commit_valid)begin valid[wr]<=1;wr<=wr+1'b1;end
            if(select_frame)begin
                matched<=0;selected_payload<=0;selected_frame_id<=display_frame_id;
                for(i=0;i<8;i=i+1)if(valid[i] && ids[i]==display_frame_id && display_valid)begin
                    matched<=1;selected_payload<=data[i];
                end
                if(commit_valid && commit_frame_id==display_frame_id && display_valid)begin
                    matched<=1;selected_payload<=commit_payload;
                end
            end
        end
    end
endmodule
