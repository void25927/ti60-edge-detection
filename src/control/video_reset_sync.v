`timescale 1ns/1ps
// 异步置位复位、三级同步释放；每个时钟域独立实例化。
module video_reset_sync(input wire clk,input wire async_rst_n,output wire rst_n);
    (* ASYNC_REG="TRUE" *) reg [2:0] release_pipe;
    always @(posedge clk or negedge async_rst_n)begin
        if(!async_rst_n)release_pipe<=0;
        else release_pipe<={release_pipe[1:0],1'b1};
    end
    assign rst_n=release_pipe[2];
endmodule
