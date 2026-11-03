`timescale 1ns/1ps
module video_history_tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=1;reg [1:0] mode=0,offset=0;reg [31:0] freeze_id=0;
 reg source=0,write_done=0,read_start=0;
 wire capture,valid,fault;wire [2:0] wi,ri,count;wire [1:0] active;wire [31:0] id;
 integer errors=0,n,k;reg [31:0] expected[0:3];reg [31:0] physical[0:5];
 reg [31:0] sequence_id=1;
 video_history_manager dut(clk,rst,mode,offset,freeze_id,source,write_done,read_start,
 capture,wi,ri,active,count,id,valid,fault);
 task ck;input good;begin if(!good)begin errors=errors+1;$display("FAIL %0t id=%0d",$time,id);end end endtask
 task commit;begin
  @(negedge clk);ck(capture);ck(!valid||wi!=ri);
  physical[wi]=sequence_id;
  for(k=3;k>0;k=k-1)expected[k]=expected[k-1];expected[0]=sequence_id;sequence_id=sequence_id+1;
  write_done=1;@(negedge clk);write_done=0;
 end endtask
 task scan;begin @(negedge clk);read_start=1;@(negedge clk);read_start=0;ck(!fault);ck(physical[ri]==id);end endtask
 initial begin
  for(k=0;k<6;k=k+1)physical[k]=0;for(k=0;k<4;k=k+1)expected[k]=0;
  repeat(3)@(negedge clk);rst=0;
  // 写入比显示快，反复轮转，历史引用必须仍对应真实帧。
  for(n=0;n<30;n=n+1)begin commit;if(n%3==0)scan;end
  mode=2;offset=3;read_start=1;commit;read_start=0;ck(!capture&&count==4);ck(wi!=ri);
  for(n=0;n<4;n=n+1)begin offset=n;scan;ck(id==expected[n]);end
  freeze_id=id;mode=1;scan;ck(id==freeze_id);
  repeat(4)begin source=1;scan;ck(!capture&&id==freeze_id);source=0;end
  mode=0;@(negedge clk);source=1;@(negedge clk);source=0;ck(capture);
  for(n=0;n<30;n=n+1)begin commit;scan;end
  mode=2;commit;for(n=0;n<4;n=n+1)begin offset=n;scan;ck(id==expected[n]);end
  mode=1;freeze_id=32'hffffffff;
  @(negedge clk);read_start=1;@(negedge clk);read_start=0;ck(fault);
  rst=1;@(negedge clk);rst=0;ck(!fault&&!valid&&count==0);
  if(errors==0)$display("TEST PASSED: video_history, commits=%0d",sequence_id-1);
  else $display("TEST FAILED: video_history %0d error(s)",errors);
  $finish;
 end
 initial begin #100000;errors=errors+1;$display("TEST FAILED: timeout");$finish;end
endmodule
