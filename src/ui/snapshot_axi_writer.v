`timescale 1ns/1ps
// 截图像素打包为128位、最多8拍的AXI写突发；只在最后真实B响应后报告完成。
// 上游须使用可背压FIFO。cancel后已发布事务继续排空，禁止旧响应提交新截图。
module snapshot_axi_writer #(
    parameter [3:0] AXI_ID=4'h8
)(
    input wire clk,rst_n,cancel,
    input wire in_valid,
    output wire in_ready,
    input wire [31:0] in_address,
    input wire [15:0] in_pixel,
    input wire in_last,
    output wire [3:0] awid,
    output reg [31:0] awaddr,
    output reg [7:0] awlen,
    output wire [2:0] awsize,
    output wire [1:0] awburst,
    output wire awvalid,
    input wire awready,
    output wire [127:0] wdata,
    output wire [15:0] wstrb,
    output wire wlast,wvalid,
    input wire wready,
    input wire [3:0] bid,
    input wire [1:0] bresp,
    input wire bvalid,
    output wire bready,
    output reg done,fault,
    output wire drained,
    output wire cancel_ready // 独立取消握手，不依赖cancel，避免组合反馈
);
    localparam FILL=0,ADDR=1,DATA=2,RESP=3;
    reg [1:0] state;
    reg [127:0] data_mem[0:7];
    reg [127:0] pack_data,data_output;
    reg [15:0] last_mask;
    reg [5:0] count; // 一个突发最多接收64个RGB565像素
    reg [2:0] beat;
    reg final_burst,cancelled;
    reg [31:0] expected_address;
    wire accept=in_valid&&in_ready;
    wire invalid_address=in_address[0] ||
        ((count==0)?(in_address[3:0]!=0):(in_address!=expected_address));
    assign in_ready=(state==FILL)&&!fault&&!cancel;
    assign cancel_ready=(state==FILL);
    assign awid=AXI_ID;
    assign awsize=3'd4;
    assign awburst=2'b01;
    assign awvalid=(state==ADDR);
    assign wvalid=(state==DATA);
    assign wdata=data_output;
    assign wstrb=wlast?last_mask:16'hffff;
    assign wlast=({5'd0,beat}==awlen);
    assign bready=(state==RESP);
    assign drained=(state==FILL)&&(count==0);
    wire [127:0] packed_next={in_pixel,pack_data[127:16]};
    // 整字写RAM，避免二维数组可变位选写入被综合成大规模寄存器选择器。
    always @(posedge clk)begin
        if(accept&&!invalid_address&&(count[2:0]==7||in_last))
            data_mem[count[5:3]]<=packed_next>>((7-count[2:0])*16);
        if(state==ADDR)data_output<=data_mem[0];
        else if(state==DATA&&wready&&!wlast)data_output<=data_mem[beat+1'b1];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            state<=FILL;count<=0;beat<=0;awaddr<=0;awlen<=0;
            final_burst<=0;cancelled<=0;expected_address<=0;done<=0;fault<=0;
            pack_data<=0;last_mask<=0;
        end else begin
            done<=0;
            if(cancel)begin
                cancelled<=1;
                if(state==FILL)begin count<=0;cancelled<=0;end
            end
            case(state)
                FILL:if(accept)begin
                    if(invalid_address)begin fault<=1;count<=0;end
                    else begin
                        if(count==0)begin awaddr<=in_address;cancelled<=0;end
                        expected_address<=in_address+2;
                        pack_data<=packed_next;
                        // 最后像素、8拍上限或4KB末尾均结束本次突发。
                        if(in_last || count==63 || in_address[11:0]==12'hffe)begin
                            awlen<={5'd0,count[5:3]};final_burst<=in_last;
                            last_mask<=16'hffff>>((7-count[2:0])*2);
                            state<=ADDR;beat<=0;
                        end else count<=count+1'b1;
                    end
                end
                ADDR:if(awready)state<=DATA;
                DATA:if(wready)begin
                    if(wlast)state<=RESP;
                    else beat<=beat+1'b1;
                end
                RESP:if(bvalid)begin
                    if(bresp!=0 || bid!=AXI_ID)fault<=1;
                    else if(final_burst&&!cancelled&&!cancel&&!fault)done<=1;
                    count<=0;state<=FILL;cancelled<=0;
                end
                default:begin state<=FILL;count<=0;fault<=1;end
            endcase
        end
    end
endmodule
