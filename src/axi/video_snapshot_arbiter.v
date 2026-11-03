`timescale 1ns/1ps
// 四类请求共享厂商DDR命令口：视频写/读、截图写/读。
// 每次锁定完整事务。显示预取最多优先两次，随后轮转服务其他客户端。
module video_snapshot_arbiter(
 input wire clk,rst_n,
 input wire [3:0] request_valid,
 output wire [3:0] request_ready,
 input wire [127:0] request_address,
 input wire [31:0] request_length,
 input wire [1:0] write_valid,
 output wire [1:0] write_ready,
 input wire [255:0] write_data,
 input wire [31:0] write_strobe,
 input wire [1:0] write_last,
 output wire [1:0] response_valid,
 input wire [1:0] response_ready,
 output wire [1:0] read_valid,
 input wire [1:0] read_ready,
 output wire [127:0] read_data,
 output wire read_last,
 output wire [1:0] response_code,read_code,
 output reg avalid,
 input wire aready,
 output reg [31:0] aaddr,
 output reg [7:0] alen,
 output reg [3:0] aid,
 output reg atype,
 output wire wvalid,
 input wire wready,
 output wire [127:0] wdata,
 output wire [15:0] wstrb,
 output wire wlast,
 output wire [3:0] wid,
 input wire bvalid,
 output wire bready,
 input wire [3:0] bid,
 input wire [1:0] bresp,
 input wire rvalid,
 output wire rready,
 input wire [127:0] rdata,
 input wire [3:0] rid,
 input wire [1:0] rresp,
 input wire rlast,
 output reg fault
);
 localparam IDLE=0,COMMAND=1,WRITE=2,BRESPONSE=3,READ=4;
 reg [2:0] state;
 reg [1:0] owner,round_robin;
 reg [1:0] display_grants;
 reg [8:0] beats_left;
 reg found;reg [1:0] chosen,candidate;
 integer i;
 always @(*)begin
  found=0;chosen=0;candidate=0;
  for(i=0;i<4;i=i+1)begin
   candidate=round_robin+i;
   if(!found&&request_valid[candidate])begin found=1;chosen=candidate;end
  end
  if(request_valid[3]&&display_grants<2)begin found=1;chosen=3;end
 end
 assign request_ready=(state==COMMAND&&aready)?(4'b0001<<owner):0;
 assign write_ready=(state==WRITE&&wready)?(2'b01<<owner[1]):0;
 assign wvalid=(state==WRITE)&&write_valid[owner[1]];
 assign wdata=write_data[owner[1]*128+:128];
 assign wstrb=write_strobe[owner[1]*16+:16];
 assign wlast=write_last[owner[1]];
 assign wid=aid;
 assign response_valid=(state==BRESPONSE&&bvalid)?(2'b01<<owner[1]):0;
 assign bready=(state==BRESPONSE)&&response_ready[owner[1]];
 assign response_code=bresp;
 assign read_valid=(state==READ&&rvalid)?(2'b01<<owner[1]):0;
 assign rready=(state==READ)&&read_ready[owner[1]];
 assign read_data=rdata;
 assign read_last=rlast;
 assign read_code=rresp;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;owner<=0;round_robin<=0;beats_left<=0;display_grants<=0;
   avalid<=0;aaddr<=0;alen<=0;aid<=0;atype<=0;fault<=0;
  end else case(state)
   IDLE:if(found&&!fault)begin
    owner<=chosen;round_robin<=chosen+1'b1;
    if(chosen==3)begin
     if(display_grants<2)display_grants<=display_grants+1'b1;
    end else display_grants<=0;
    aaddr<=request_address[chosen*32+:32];alen<=request_length[chosen*8+:8];
    aid<=chosen[1]?{3'b100,chosen[0]}:4'd0;
    atype<=!chosen[0];avalid<=1;state<=COMMAND;
    beats_left<={1'b0,request_length[chosen*8+:8]}+1'b1;
   end
   COMMAND:if(aready)begin avalid<=0;state<=atype?WRITE:READ;end
   WRITE:if(wvalid&&wready)begin
    if(wlast!=(beats_left==1))fault<=1;
    beats_left<=beats_left-1'b1;
    if(beats_left==1)state<=BRESPONSE;
   end
   BRESPONSE:if(bvalid&&bready)begin
    if(bresp!=0||bid!=aid)fault<=1;
    state<=IDLE;
   end
   READ:if(rvalid&&rready)begin
    if(rresp!=0||rid!=aid||rlast!=(beats_left==1))fault<=1;
    beats_left<=beats_left-1'b1;
    if(beats_left==1)state<=IDLE;
   end
   default:begin state<=IDLE;fault<=1;avalid<=0;end
  endcase
 end
endmodule
