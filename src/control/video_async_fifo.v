`timescale 1ns/1ps
// 双时钟FIFO：Gray指针跨域，两侧分别同步释放复位；RAM不做复位清零。
// rst_n必须同时复位两侧，不能在工作中只复位一个时钟域。
module video_async_fifo #(
    parameter DATA_WIDTH=130,parameter ADDR_BITS=9 // 深度2^ADDR_BITS，ADDR_BITS至少2
)(
    input wire wr_clk,input wire rd_clk,input wire rst_n,
    input wire [DATA_WIDTH-1:0] in_data,input wire in_valid,output wire in_ready,
    output reg [DATA_WIDTH-1:0] out_data,output reg out_valid,input wire out_ready,
    output wire [ADDR_BITS:0] wr_count,output wire [ADDR_BITS:0] rd_count
);
    reg [DATA_WIDTH-1:0] memory[0:(1<<ADDR_BITS)-1];
    (* ASYNC_REG="TRUE" *) reg [2:0] wr_reset,rd_reset;
    wire wr_rst_n=wr_reset[2],rd_rst_n=rd_reset[2];
    reg [ADDR_BITS:0] wr_binary,rd_binary,wr_gray,rd_gray;
    (* ASYNC_REG="TRUE" *) reg [ADDR_BITS:0] rd_gray_w1,rd_gray_w2,wr_gray_r1,wr_gray_r2;
    function [ADDR_BITS:0] binary;input [ADDR_BITS:0] gray;integer n;begin
        binary[ADDR_BITS]=gray[ADDR_BITS];for(n=ADDR_BITS-1;n>=0;n=n-1)binary[n]=binary[n+1]^gray[n];
    end endfunction
    wire full=wr_gray=={~rd_gray_w2[ADDR_BITS:ADDR_BITS-1],rd_gray_w2[ADDR_BITS-2:0]};
    wire empty=rd_gray==wr_gray_r2;
    wire push=in_valid && in_ready;
    wire load=rd_reset[2] && !empty && (!out_valid || out_ready);
    assign in_ready=wr_reset[2] && !full;
    assign wr_count=wr_binary-binary(rd_gray_w2);
    // 读出寄存器内的一个字也计入可用水位。
    assign rd_count=binary(wr_gray_r2)-rd_binary+out_valid;
    always @(posedge wr_clk or negedge rst_n)begin
        if(!rst_n)wr_reset<=0;else wr_reset<={wr_reset[1:0],1'b1};
    end
    always @(posedge rd_clk or negedge rst_n)begin
        if(!rst_n)rd_reset<=0;else rd_reset<={rd_reset[1:0],1'b1};
    end
    always @(posedge wr_clk or negedge wr_rst_n)begin
        if(!wr_rst_n)begin wr_binary<=0;wr_gray<=0;rd_gray_w1<=0;rd_gray_w2<=0;end
        else begin
            rd_gray_w1<=rd_gray;rd_gray_w2<=rd_gray_w1;
            if(push)begin wr_binary<=wr_binary+1'b1;wr_gray<=((wr_binary+1'b1)>>1)^(wr_binary+1'b1);end
        end
    end
    always @(posedge wr_clk)if(push)memory[wr_binary[ADDR_BITS-1:0]]<=in_data;
    always @(posedge rd_clk)if(load)out_data<=memory[rd_binary[ADDR_BITS-1:0]];
    always @(posedge rd_clk or negedge rd_rst_n)begin
        if(!rd_rst_n)begin rd_binary<=0;rd_gray<=0;wr_gray_r1<=0;wr_gray_r2<=0;out_valid<=0;end
        else begin
            wr_gray_r1<=wr_gray;wr_gray_r2<=wr_gray_r1;
            if(load)begin rd_binary<=rd_binary+1'b1;rd_gray<=((rd_binary+1'b1)>>1)^(rd_binary+1'b1);out_valid<=1;end
            else if(out_ready)out_valid<=0;
        end
    end
endmodule
