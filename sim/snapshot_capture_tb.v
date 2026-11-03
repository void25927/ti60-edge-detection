`timescale 1ns/1ps
module snapshot_capture_tb;
reg clk=0,rst=0,req=0,cancel=0,sof=0,eof=0,stable=1,v=0,ready=1,ack=0,fail=0,bound=0,drained=1;
reg[31:0]id=0,src_id=0;reg[23:0]rgb=0;
wire busy,done,error,wv,last,abort_store;wire[31:0]addr;wire[15:0]data;
wire[2:0]valid;wire[5:0]slots;wire[95:0]ids;
integer errors=0,frame,x,y,writes=0;reg[1:0]slot;
reg[15:0]expect_pixel[0:3];reg[31:0]expect_base;
always #5 clk=~clk;
snapshot_capture #(.WIDTH(12),.HEIGHT(12),.SCALE(6)) dut(clk,rst,req,cancel,id,sof,eof,stable,src_id,v,rgb,ready,ack,fail,bound,drained,
 busy,done,error,wv,addr,data,last,abort_store,valid,slots,ids);
task tick;begin @(posedge clk);#1;end endtask
task ck;input c;input[255:0]m;begin if(c!==1'b1)begin errors=errors+1;$display("ERROR %0s",m);end end endtask
always @(posedge clk)if(rst&&wv&&ready)begin
 if(addr!==expect_base+writes*2 || data!==expect_pixel[writes] || last!==(writes==3))errors=errors+1;
 writes=writes+1;
end
initial begin
 tick;@(negedge clk);rst=1;
 for(frame=0;frame<4;frame=frame+1)begin
  writes=0;id=frame+10;src_id=id;expect_base=32'h02000000+((frame==0)?3:frame-1)*32'h20000;
  // 以源坐标构造颜色，取样应只选(0,0)、(6,0)、(0,6)、(6,6)。
  expect_pixel[0]={5'd0,6'd0,5'd0};expect_pixel[1]={5'd6,6'd0,5'd6};
  expect_pixel[2]={5'd0,6'd6,5'd6};expect_pixel[3]={5'd6,6'd6,5'd12};
  req=1;tick;@(negedge clk);req=0;sof=1;tick;@(negedge clk);sof=0;
  for(y=0;y<12;y=y+1)for(x=0;x<12;x=x+1)begin
   v=1;rgb=((x&31)<<19)|((y&63)<<10)|(((x+y)&31)<<3);tick;@(negedge clk);
  end
  v=0;eof=1;tick;@(negedge clk);eof=0;tick;
  ck(writes==4,"all samples");ck(busy,"wait DDR acknowledgement");
  @(negedge clk);ack=1;tick;@(negedge clk);ack=0;bound=1;drained=0;tick;ck(!done,"wait display drain");
  @(negedge clk);drained=1;tick;ck(done&&!busy,"atomic commit");
  ck(ids[(frame%3)*32+:32]==id,"frame identity");@(negedge clk);bound=0;
 end
 ck(valid==7,"three saved frames");ck(ids[31:0]==13&&ids[63:32]==11&&ids[95:64]==12,"oldest replacement");
 req=1;tick;@(negedge clk);req=0;cancel=1;tick;ck(!busy&&abort_store,"cancel");
 @(negedge clk);cancel=0;req=1;tick;@(negedge clk);req=0;fail=1;tick;ck(error&&!busy,"DDR fault");
 ck(valid==7&&ids[31:0]==13,"fault preserves prior snapshots");
 // 输入不可背压，写服务阻塞至下一采样点时必须丢弃整张，不能提交半张。
 @(negedge clk);fail=0;req=1;ready=0;tick;@(negedge clk);req=0;sof=1;tick;@(negedge clk);sof=0;
 for(y=0;y<12;y=y+1)for(x=0;x<12;x=x+1)begin v=1;rgb=0;tick;@(negedge clk);end
 v=0;eof=1;tick;ck(error&&abort_store&&!busy,"write backpressure rejects frame");
 ck(valid==7&&ids[31:0]==13,"no corrupt snapshot publish");
 @(negedge clk);eof=0;ready=1;rst=0;tick;ck(valid==0&&!busy,"reset invalidates snapshots");
 if(errors==0)$display("TEST PASSED: snapshot_capture");else $display("TEST FAILED: snapshot_capture errors=%0d",errors);
 $finish;
end
endmodule
