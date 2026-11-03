`timescale 1ns/1ps
module feature_menu_tb;
reg clk=0,rst_n=0,fs=0,fn=0,ok=0,k1=0,k2=0,busy=0,done=0,fault=0;
reg[2:0]history=4;
wire[2:0]menu;wire med,can,view,te,add,sub,active,paused,req,cancel,saving;
wire[1:0]mode,offset;
integer errors=0,i;
always #5 clk=~clk;
feature_menu_controller #(.REPLAY_HOLD_FRAMES(2)) dut(clk,rst_n,fs,fn,ok,k1,k2,history,busy,done,fault,
 menu,med,can,view,te,add,sub,mode,offset,active,paused,req,cancel,saving);
task tick;begin @(posedge clk);#1;end endtask
task check;input condition;input[255:0]msg;begin if(condition!==1'b1)begin errors=errors+1;$display("ERROR %0s",msg);end end endtask
task press;input integer key;begin
 @(negedge clk);fn=(key==0);ok=(key==1);k1=(key==2);k2=(key==3);tick;
 @(negedge clk);fn=0;ok=0;k1=0;k2=0;
end endtask
task frame;begin @(negedge clk);fs=1;tick;@(negedge clk);fs=0;end endtask
initial begin
 tick;@(negedge clk);rst_n=1;tick;check(menu==0&&med&&can&&mode==0,"reset");
 press(1);check(!med,"median toggle");press(0);check(menu==1&&te,"threshold menu");
 @(negedge clk);ok=1;#1;check(add&&!sub,"threshold up");k2=1;#1;check(!add&&!sub,"conflicting events cancel");ok=0;#1;check(sub&&!add,"threshold down");k2=0;
 press(2);check(menu==1&&!active,"function long outside replay");
 press(0);check(menu==2,"replay menu");press(1);check(!active,"confirm cannot start replay");
 history=0;press(2);check(!active,"empty history");
 history=4;press(2);check(active&&offset==3&&mode==2,"start oldest");frame;frame;check(offset==2,"advance");
 press(1);check(paused&&mode==1,"pause");frame;frame;check(offset==2,"pause holds");
 press(1);check(!paused&&mode==2,"resume");press(3);check(req&&saving&&mode==1,"save holds replay");
 busy=1;frame;frame;check(offset==2,"save holds offset");
 @(negedge clk);busy=0;done=1;tick;@(negedge clk);done=0;check(mode==2&&!saving,"save completion resumes");
 press(3);press(0);check(cancel&&!active&&menu==3&&mode==0,"leave cancels save and replay");
 press(1);check(!can,"Canny toggle");press(0);press(1);check(view,"display toggle");
 press(0);check(menu==0&&!med&&!can&&view,"wrap preserves options");
 // 功能键短按优先，不得同时执行旧菜单动作。
 @(negedge clk);fn=1;ok=1;k1=1;tick;check(menu==1&&!med,"function priority");
 @(negedge clk);fn=0;ok=0;k1=0;rst_n=0;tick;check(menu==0&&med&&can&&!view,"reset recovery");
 if(errors==0)$display("TEST PASSED: feature_menu");else $display("TEST FAILED: feature_menu errors=%0d",errors);
 $finish;
end
endmodule
