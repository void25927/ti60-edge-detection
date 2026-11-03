`timescale 1ns/1ps
module snapshot_axi_reader_tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,req=0;wire ready,av,rr,pv,done,fault;
 reg [7:0] y=0;reg [2:0] valid=7;reg [5:0] slots={2'd1,2'd3,2'd0};
 wire [3:0] aid;wire [31:0] aa;wire [7:0] al;
 reg ar=0,rv=0,rl=0,pr=0;reg [127:0] rd=0;reg [3:0] rid=9;reg [1:0] resp=0;
 wire [15:0] pd;wire [1:0] ps;wire [8:0] px;wire [7:0] py;
 integer errors=0,checks=0,cycle=0,remaining=0,k,j,bursts=0;
 reg [31:0] addr=0;reg badlast=0;reg held=0;reg [15:0] held_data;
 snapshot_axi_reader dut(clk,rst,req,ready,y,valid,slots,aid,aa,al,av,ar,
 rd,rid,resp,rl,rv,rr,pv,pr,pd,ps,px,py,done,fault);
 task ck;input good;begin if(!good)begin errors=errors+1;$display("FAIL %0t",$time);end end endtask
 task reset;begin @(negedge clk);rst=0;req=0;repeat(3)@(negedge clk);rst=1;end endtask
 task start;begin @(negedge clk);req=1;@(negedge clk);req=0;end endtask
 always @(negedge clk)begin ar=cycle%3==0;pr=cycle%5!=0;end
 always @(posedge clk)begin
  if(!rst)begin rv<=0;remaining<=0;cycle<=0;held<=0;end
  else begin
   cycle<=cycle+1;
   if(av&&ar)begin
    // 新读队列支持32拍；4KB边界和逐像素校验保持不变。
    ck(remaining==0&&!rv);ck(aid==9&&al<32);ck(aa[11:0]+(al+1)*16<=4096);
    addr<=aa;remaining<=al+1;bursts=bursts+1;
   end
   if(!rv&&remaining>0&&cycle%4!=0)begin
    for(j=0;j<8;j=j+1)rd[j*16+:16]<=((addr>>1)+j)^16'h1234;
    rv<=1;rl<=(remaining==1)^badlast;
   end
   if(rv&&rr)begin rv<=0;remaining<=remaining-1;addr<=addr+16;end
   if(held)ck(pv&&pd==held_data);
   held<=pv&&!pr;held_data<=pd;
   if(pv&&pr)begin
    ck(pd==((((32'h02000000+slots[ps*2+:2]*32'h20000+py*640+px*2)>>1)^16'h1234)&32'hffff));
    checks=checks+1;
   end
  end
 end
 initial begin
  reset;
  for(k=0;k<180;k=k+1)begin y=k;start;wait(done);@(negedge clk);ck(!fault);end
  ck(checks==172800);
  valid=0;start;wait(done);@(negedge clk);ck(checks==172800);
  valid=1;resp=2;start;wait(fault);wait(ready||(!av&&!rv&&remaining==0));repeat(20)@(negedge clk);ck(!pv);
  reset;resp=0;badlast=1;start;wait(fault);repeat(120)@(negedge clk);ck(!pv);
  reset;badlast=0;rid=8;start;wait(fault);repeat(120)@(negedge clk);ck(!pv);
  reset;rid=9;start;wait(done);@(negedge clk);ck(!fault);
  if(errors==0)$display("TEST PASSED: snapshot_axi_reader checks=%0d bursts=%0d",checks,bursts);
  else $display("TEST FAILED: snapshot_axi_reader %0d error(s)",errors);
  $finish;
 end
 initial begin #10000000;errors=errors+1;$display("TEST FAILED: timeout");$finish;end
endmodule
