`timescale 1ns/1ps
// 真实低有效按键经过消抖、短长按分类、菜单及阈值寄存器的联合自检。
module onboard_keys_tb;
reg clk=0,rst_n=0,fs=0;
reg [1:0] raw=2'b11;
wire [1:0] held,down,up,short_p,long_p;
wire [2:0] menu;
wire med,can,view,te,add,sub,active,paused,req,cancel,saving;
wire [1:0] mode,offset;
wire [10:0] high_t,low_t,pending;
reg busy=0,done=0,fault=0;
reg [2:0] history=4;
integer errors=0,checks=0,shots=0,fn_short=0,fn_long=0,ok_short=0,ok_long=0;
integer saved_count,n;
always #5 clk=~clk;
genvar k;
generate for(k=0;k<2;k=k+1)begin: keys
    // 缩短计数便于仿真；短按与长按使用相同实际RTL。
    debounce #(.CLK_FREQ_HZ(1000),.DEBOUNCE_MS(3)) db(
        clk,rst_n,raw[k],held[k],down[k],up[k]);
    key_event_controller #(.CLK_FREQ_HZ(1000),.LONG_PRESS_MS(40)) ev(
        clk,rst_n,held[k],down[k],up[k],short_p[k],long_p[k]);
end endgenerate
feature_menu_controller dut(
    .clk(clk),.rst_n(rst_n),.frame_start(fs),
    .function_press(short_p[0]),.confirm_press(short_p[1]),
    .function_long_press(long_p[0]),.confirm_long_press(long_p[1]),
    .history_count(history),.snapshot_busy(busy),.snapshot_done(done),.snapshot_error(fault),
    .menu_index(menu),.median_enable(med),.canny_enable(can),.display_mode(view),
    .threshold_enable(te),.threshold_add(add),.threshold_sub(sub),
    .ddr_mode(mode),.replay_offset(offset),.replay_active(active),.replay_paused(paused),
    .snapshot_request(req),.snapshot_cancel(cancel),.saving(saving));
threshold_controller th(.clk(clk),.rst_n(rst_n),.adjust_enable(te),
    .add_pulse(add),.sub_pulse(sub),.frame_start(fs),
    .high_threshold(high_t),.low_threshold(low_t),.pending_high_threshold(pending));
always @(posedge clk)begin
    if(rst_n)begin
        if(req)shots=shots+1;
        if(short_p[0])fn_short=fn_short+1;
        if(long_p[0])fn_long=fn_long+1;
        if(short_p[1])ok_short=ok_short+1;
        if(long_p[1])ok_long=ok_long+1;
    end
end
task check;input condition;input [511:0] msg;begin
    checks=checks+1;
    if(condition!==1'b1)begin errors=errors+1;$display("ERROR: %0s",msg);end
end endtask
task cycles;input integer n;begin repeat(n)@(negedge clk);end endtask
task tap;input integer key;begin
    @(negedge clk);raw[key]=0;cycles(12);raw[key]=1;cycles(12);
end endtask
task hold_key;input integer key;begin
    @(negedge clk);raw[key]=0;cycles(100);raw[key]=1;cycles(12);
end endtask
task frame;begin fs=1;cycles(1);fs=0;cycles(2);end endtask
initial begin
    cycles(4);rst_n=1;cycles(4);
    check(menu==0&&med&&can,"reset defaults");
    // 抖动时间小于消抖门限，不应切菜单。
    raw[0]=0;cycles(1);raw[0]=1;cycles(1);raw[0]=0;cycles(1);raw[0]=1;cycles(12);
    check(menu==0&&fn_short==0&&fn_long==0,"bounce ignored");
    saved_count=ok_short;hold_key(1);
    check(med&&ok_short==saved_count&&ok_long==1,"long confirm does not toggle median");
    tap(1);check(!med,"short confirm toggles median");
    hold_key(0);check(menu==0&&!active&&fn_short==0,"long function does not cycle menu");
    tap(0);check(menu==1,"threshold menu");
    tap(1);check(pending==88&&high_t==80,"short adds once pending frame");
    frame;check(high_t==88&&low_t==44,"frame applies threshold");
    saved_count=ok_short;hold_key(1);
    check(pending==80&&ok_short==saved_count,"long subtracts once no release add");
    frame;check(high_t==80&&low_t==40,"long threshold applied");
    tap(0);tap(1);check(menu==2&&!active,"confirm in live replay menu does not start");
    saved_count=fn_short;hold_key(0);
    check(menu==2&&active&&!paused&&offset==3&&fn_short==saved_count,"function long starts stays menu");
    tap(1);check(paused&&mode==1,"confirm short freezes");
    hold_key(1);check(shots==1&&saving&&paused,"long saves paused frame once");
    done=1;cycles(1);done=0;cycles(2);check(!saving&&paused,"save retains pause");
    tap(1);check(!paused&&mode==2,"confirm short resumes");
    hold_key(1);check(shots==2&&saving&&!paused&&mode==1,"save holds running replay");
    done=1;cycles(1);done=0;cycles(2);check(!saving&&mode==2,"save resumes running replay");
    hold_key(1);tap(0);check(menu==3&&!active&&!saving&&mode==0,"leave cancels unfinished save");
    tap(1);check(!can,"Canny toggle");tap(0);tap(1);check(view,"view toggle");
    tap(0);check(menu==0&&!med&&!can&&view,"menu wrap preserves settings");
    raw[1]=0;cycles(10);rst_n=0;raw=3;cycles(4);rst_n=1;cycles(60);
    check(menu==0&&med&&can&&!view&&!active&&!saving,"reset during press no phantom action");
    // 扫描长按临界点及其两侧；每次有效按键只能归类为一个事件。
    for(n=10;n<=65;n=n+1)begin
        saved_count=ok_short+ok_long;
        raw[1]=0;cycles(n);raw[1]=1;cycles(12);
        check(ok_short+ok_long==saved_count+1,"boundary press has exactly one event");
    end
    if(errors==0)$display("TEST PASSED: onboard_keys checks=%0d",checks);
    else $display("TEST FAILED: onboard_keys errors=%0d",errors);
    $finish;
end
initial begin #1000000;$display("TEST FAILED: onboard_keys timeout");$finish;end
endmodule
