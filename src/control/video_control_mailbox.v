`timescale 1ns/1ps
// 多位配置整组跨域：请求/应答翻转握手，收到应答前保持邮箱数据。
// 忙期间合并连续配置变化，最终值必达；不用于传递必须逐次保留的事件。
module video_control_mailbox #(
    parameter WIDTH=27,parameter [WIDTH-1:0] RESET_VALUE=0
)(
    input wire src_clk,input wire dst_clk,input wire async_rst_n,
    input wire [WIDTH-1:0] src_data,
    output reg [WIDTH-1:0] dst_data,output reg dst_update,output wire src_busy
);
    wire src_rst_n,dst_rst_n;
    video_reset_sync src_reset(src_clk,async_rst_n,src_rst_n);
    video_reset_sync dst_reset(dst_clk,async_rst_n,dst_rst_n);
    reg [WIDTH-1:0] held_data;
    reg request_toggle,ack_toggle;
    (* ASYNC_REG="TRUE" *) reg ack_s1,ack_s2,req_d1,req_d2;
    assign src_busy=request_toggle!=ack_s2;
    always @(posedge src_clk or negedge src_rst_n)begin
        if(!src_rst_n)begin held_data<=RESET_VALUE;request_toggle<=0;ack_s1<=0;ack_s2<=0;end
        else begin
            ack_s1<=ack_toggle;ack_s2<=ack_s1;
            if(!src_busy && src_data!=held_data)begin
                held_data<=src_data;request_toggle<=~request_toggle;
            end
        end
    end
    always @(posedge dst_clk or negedge dst_rst_n)begin
        if(!dst_rst_n)begin dst_data<=RESET_VALUE;dst_update<=0;req_d1<=0;req_d2<=0;ack_toggle<=0;end
        else begin
            req_d1<=request_toggle;req_d2<=req_d1;dst_update<=0;
            if(req_d2!=ack_toggle)begin
                dst_data<=held_data;dst_update<=1;ack_toggle<=req_d2;
            end
        end
    end
endmodule
