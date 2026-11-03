`timescale 1ns/1ps
// RAW读写、快照读写、配对图读写；每次完整锁定一个事务，紧急水位有限优先。
module paired_video_arbiter(
 input wire clk,rst_n,
 input wire [5:0] request_valid,urgent,
 output wire [5:0] request_ready,
 input wire [191:0] request_address,
 input wire [47:0] request_length,
 input wire [2:0] write_valid,
 output wire [2:0] write_ready,
 input wire [383:0] write_data,
 input wire [47:0] write_strobe,
 input wire [2:0] write_last,
 output wire [2:0] response_valid,
 input wire [2:0] response_ready,
 output wire [2:0] read_valid,
 input wire [2:0] read_ready,
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
 reg [2:0] state,owner,round_robin,urgent_cursor,urgent_grants;
 reg [8:0] beats_left;
 reg found,found_urgent;reg [2:0] chosen,chosen_urgent;integer i,k,u;
 always @(*)begin
  found=0;found_urgent=0;chosen=0;chosen_urgent=0;k=0;u=0;
  for(i=0;i<6;i=i+1)begin
   k=round_robin+i;if(k>=6)k=k-6;
   if(!found&&request_valid[k])begin found=1;chosen=k;end
   u=urgent_cursor+i;if(u>=6)u=u-6;
   if(!found_urgent&&request_valid[u]&&urgent[u])begin found_urgent=1;chosen_urgent=u;end
  end
  if(found_urgent&&urgent_grants<4)chosen=chosen_urgent;
 end
 wire [1:0] channel=owner>>1;
 assign request_ready=(state==COMMAND&&aready)?(6'b000001<<owner):0;
 assign write_ready=(state==WRITE&&wready)?(3'b001<<channel):0;
 assign wvalid=state==WRITE&&write_valid[channel];
 assign wdata=write_data[channel*128+:128];assign wstrb=write_strobe[channel*16+:16];
 assign wlast=write_last[channel];assign wid=aid;
 assign response_valid=(state==BRESPONSE&&bvalid)?(3'b001<<channel):0;
 assign bready=state==BRESPONSE&&response_ready[channel];
 assign response_code=(bid!=aid)?2'b10:bresp;
 assign read_valid=(state==READ&&rvalid)?(3'b001<<channel):0;
 assign rready=state==READ&&read_ready[channel];assign read_data=rdata;assign read_last=rlast;
 assign read_code=(rid!=aid || rlast!=(beats_left==1))?2'b10:rresp;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;owner<=0;round_robin<=0;urgent_cursor<=0;urgent_grants<=0;beats_left<=0;avalid<=0;aaddr<=0;alen<=0;aid<=0;atype<=0;fault<=0;end
  else case(state)
   IDLE:if(found&&!fault)begin
    owner<=chosen;
    // 紧急选择不得推进普通轮转游标，否则持续紧急请求会饿死中间客户端。
    if(found_urgent&&urgent_grants<4)begin urgent_grants<=urgent_grants+1'b1;urgent_cursor<=(chosen==5)?0:chosen+1'b1;end
    else begin urgent_grants<=0;round_robin<=(chosen==5)?0:chosen+1'b1;end
    aaddr<=request_address[chosen*32+:32];alen<=request_length[chosen*8+:8];
    aid<=chosen<2?4'd0:chosen+4'd6;atype<=!chosen[0];avalid<=1;state<=COMMAND;
    beats_left<={1'b0,request_length[chosen*8+:8]}+1'b1;
   end
   COMMAND:if(aready)begin avalid<=0;state<=atype?WRITE:READ;end
   WRITE:if(wvalid&&wready)begin
    if(wlast!=(beats_left==1))fault<=1;
    beats_left<=beats_left-1'b1;if(beats_left==1)state<=BRESPONSE;
   end
   BRESPONSE:if(bvalid&&bready)begin if(response_code!=0)fault<=1;state<=IDLE;end
   READ:if(rvalid&&rready)begin
    if(read_code!=0)fault<=1;beats_left<=beats_left-1'b1;if(beats_left==1)state<=IDLE;
   end
   default:begin state<=IDLE;fault<=1;avalid<=0;end
  endcase
 end
endmodule
