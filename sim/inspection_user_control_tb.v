`timescale 1ns/1ps
module inspection_user_control_tb;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,lr=0,sr=0,ov=0,tv=0,ack=0,bg=0,clear=0,fv=1;
 reg [31:0] fid=0,ofid=0;reg [2:0] count=1;reg [7:0] ferr=0;
 wire pulse,pending,en,rejected,inv;wire [31:0] target;
 integer errors=0,checks=0,trace,i;reg [31:0] rng=32'had075391;
 inspection_user_control #(.SESSION_CONTROL(1)) dut(.clk(clk),.rst_n(rst_n),.learn_request(lr),.start_request(sr),.request_frame_id(fid),
  .observation_valid(ov),.observation_frame_id(ofid),.object_count(count),.frame_error(ferr),.center_x(11'd0),.center_y(11'd0),.area(22'd1000),
  .template_valid(tv),.template_learned(ack),.background_ready(bg),.learn_pulse(pulse),.learn_pending(pending),.detect_enabled(en),
  .command_rejected(rejected),.invalidate_results(inv),.session_clear(clear),.request_frame_valid(fv),.learn_frame_id(target));
 initial trace=$fopen("single_frame_control_trace.txt","w");
 always @(posedge clk)begin #2;$fdisplay(trace,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",rst_n,lr,sr,fid,ov,ofid,tv,ack,bg,clear,fv,pulse,pending,en,rejected,inv,target,count,ferr);end
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task ck;input ok;begin checks=checks+1;if(!ok)begin errors=errors+1;$display("CONTROL ERROR check=%0d pulse=%b pending=%b enabled=%b rejected=%b target=%h",checks,pulse,pending,en,rejected,target);end end endtask
 task short_press;begin sr=1;tick;sr=0;tick;end endtask
 task long_press;input [31:0] id;begin fid=id;lr=1;tick;ck(pulse);lr=0;tick;end endtask
 initial begin
  repeat(3)tick;rst_n=1;tick;
  short_press;ck(!en&&rejected);
  lr=1;tick;ck(!pulse&&!pending&&rejected);lr=0;tick;bg=1;
  long_press(100);ck(pending&&target==100&&!en);
  // 不等待三帧：命令当拍即发单次请求；旧观测不能改目标帧。
  ov=1;ofid=99;tick;ck(pending&&!pulse&&target==100);ov=0;
  short_press;ck(!en&&rejected&&pending);
  ov=1;ofid=100;count=0;ferr=1;tick;ck(!pending&&rejected);ov=0;count=1;ferr=0;
  ofid=101;ov=1;tick;ck(!pending&&!pulse);ov=0;
  long_press(200);ack=1;tv=1;tick;ack=0;ck(!pending&&!en&&!rejected);
  short_press;ck(en&&!rejected&&inv==0);
  // 长按电平保持不重复触发；录入时关闭检测。
  fid=300;lr=1;tick;ck(pulse&&!en&&pending);repeat(5)begin tick;ck(!pulse&&pending&&target==300);end
  lr=0;tick;fid=301;lr=1;tick;ck(!pulse&&pending&&target==300&&rejected);lr=0;tick;
  ack=1;tick;ack=0;short_press;ck(en);short_press;ck(!en);short_press;ck(en);
  // 指定帧已错过，不能把未来帧当标准件；覆盖32位帧号回绕。
  long_press(32'hffffffff);ov=1;ofid=32'hfffffffe;tick;ck(pending);ofid=0;tick;ck(!pending&&rejected);ov=0;
  fv=0;lr=1;tick;ck(!pending&&!pulse&&rejected);lr=0;fv=1;tick;
  long_press(500);clear=1;tick;ck(!pending&&!pulse&&inv);clear=0;tick;
  fid=600;ov=1;ofid=600;lr=1;tick;ck(!pending&&!pulse&&rejected);ov=0;lr=0;tick;
  fid=700;lr=1;sr=1;tick;ck(pending&&!en&&pulse);lr=0;sr=0;tick;
  rst_n=0;tick;ck(!pending&&!pulse&&!en&&!rejected);rst_n=1;tick;
  // 随机逐拍轨迹交由独立Python状态机复算，覆盖握手、复位和会话优先级。
  for(i=0;i<2000;i=i+1)begin
   rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
   fid=fid+((i%10)==0);lr=rng[0]&&rng[1];sr=rng[2]&&rng[3];ov=rng[4];ofid=fid+rng[6:5]-2;
   tv=rng[7];ack=rng[8]&&rng[9];bg=rng[10];clear=rng[11]&&rng[12]&&rng[13];fv=rng[14];rst_n=!(rng[15:12]==0);tick;
  end
  $display("single_frame_control checks=%0d random_cycles=2000 errors=%0d",checks,errors);
  if(!errors)$display("TEST PASSED");else $display("TEST FAILED");$fclose(trace);$finish;
 end
endmodule
