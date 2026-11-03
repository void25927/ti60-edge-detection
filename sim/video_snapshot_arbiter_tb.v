`timescale 1ns/1ps
module video_snapshot_arbiter_tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0;
 reg [3:0] qv=0;wire [3:0] qr;
 reg [127:0] qa=0;reg [31:0] ql=0;
 reg [1:0] wv=0,wl=0;wire [1:0] wr,bv,rv;
 reg [255:0] wd=0;reg [31:0] ws=32'hffffffff;
 reg [1:0] br=3,rr=3;
 wire [127:0] rd;wire rl;wire [1:0] bc,rc;
 wire av,at,mwv,mwl,mbr,mrr;reg ar=0,mwr=0,mbv=0,mrv=0,mrl=0;
 wire [31:0] aa;wire [7:0] al;wire [3:0] ai,mwi;
 wire [127:0] mwd;wire [15:0] mws;
 reg [3:0] mbi=0,mri=0;reg [1:0] mbc=0,mrc=0;reg [127:0] mrd=0;
 wire fault;
 integer errors=0,cycles=0,n=0,i,j,owner=-1,left=0,delay_resp=0;
 integer completed[0:3],beat[0:1],total[0:1];
 reg [31:0] address=0;
 reg command_held=0;reg [44:0] held_command;
 video_snapshot_arbiter dut(clk,rst,qv,qr,qa,ql,wv,wr,wd,ws,wl,bv,br,rv,rr,rd,rl,bc,rc,
 av,ar,aa,al,ai,at,mwv,mwr,mwd,mws,mwl,mwi,mbv,mbr,mbi,mbc,mrv,mrr,mrd,mri,mrc,mrl,fault);
 task ck;input b;begin if(!b)begin errors=errors+1;$display("FAIL t=%0t owner=%0d left=%0d",$time,owner,left);end end endtask
 always @(negedge clk)begin
  ar=cycles%7==0;mwr=cycles%3!=0;rr=cycles%5==0?0:3;br=cycles%4==0?0:3;
 end
 always @(posedge clk)if(rst)begin
  cycles=cycles+1;
  if(command_held)ck(av&&{aa,al,ai,at}==held_command);
  command_held<=av&&!ar;held_command<={aa,al,ai,at};
  if(av&&ar)begin
   ck(owner==-1);ck(qr!=0);
   owner=ai==8?2:ai==9?3:at?0:1;
   ck(qr==(1<<owner));ck(aa==qa[owner*32+:32]);
   left=al+1;address=aa;
   if(at)begin
    beat[owner/2]=0;total[owner/2]=left;
    wd[(owner/2)*128+:128]<=aa;wv[owner/2]<=1;wl[owner/2]<=(left==1);
   end
  end
  if(mwv&&mwr)begin
   ck(owner==0||owner==2);ck(wr==(1<<(owner/2)));ck(mwd==address+beat[owner/2]*16);
   ck(mwl==(left==1));ck(mws==16'hffff);ck(mwi==ai);
   beat[owner/2]=beat[owner/2]+1;left=left-1;
   wd[(owner/2)*128+:128]<=address+beat[owner/2]*16;wl[owner/2]<=(left==1);
   if(left==0)begin wv[owner/2]<=0;delay_resp=11;end
  end
  if(delay_resp>0)begin delay_resp=delay_resp-1;if(delay_resp==0)begin mbv<=1;mbi<=ai;end end
  if(mbv&&mbr)begin
   ck(bv==(1<<(owner/2)));completed[owner]=completed[owner]+1;owner=-1;mbv<=0;
  end
  if(owner==1||owner==3)begin
   if(!mrv&&left>0&&cycles%4!=0)begin mrv<=1;mri<=ai;mrd<=address;mrl<=left==1;end
  end
  if(mrv&&mrr)begin
   ck(owner==1||owner==3);ck(rv==(1<<(owner/2)));ck(rd==address);ck(rl==(left==1));
   left=left-1;address=address+16;mrv<=0;
   if(left==0)begin completed[owner]=completed[owner]+1;owner=-1;end
  end
  for(i=0;i<4;i=i+1)if(completed[i]>=10)qv[i]<=0;
 end
 initial begin
  for(j=0;j<4;j=j+1)begin completed[j]=0;qa[j*32+:32]=j*4096;ql[j*8+:8]=(j<2)?127:7;end
  repeat(4)@(negedge clk);rst=1;qv=15;
  wait(completed[0]==10&&completed[1]==10&&completed[2]==10&&completed[3]==10);
  repeat(5)@(negedge clk);ck(!fault);ck(qv==0);ck(owner==-1);
  // 截图写错误必须锁存，阻止后续事务进入DDR。
  qv=4;mbc=2;wait(fault);@(negedge clk);ck(!av);
  rst=0;repeat(3)@(negedge clk);qv=0;rst=1;@(negedge clk);ck(!fault);
  if(errors==0)$display("TEST PASSED: video_snapshot_arbiter cycles=%0d",cycles);
  else $display("TEST FAILED: video_snapshot_arbiter %0d error(s)",errors);
  $finish;
 end
 initial begin #2000000;errors=errors+1;$display("TEST FAILED: timeout");$finish;end
endmodule
