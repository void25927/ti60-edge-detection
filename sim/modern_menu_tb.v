`timescale 1ns/1ps
module modern_menu_tb;
    reg clk=0,rst_n=0,fs=0,fn=0,ok=0,fl=0,ol=0,busy=0,done=0,err=0;
    reg [3:0] history=8;
    wire [2:0] menu,offset;
    wire med,can,view,te,add,sub,active,paused,req,cancel,saving;
    wire [1:0] mode;
    integer errors=0;
    always #5 clk=~clk;
    feature_menu_controller #(.INSPECTION_MENU(1),.MODERN_MENU(1),.HISTORY_FRAMES(8),.REPLAY_HOLD_FRAMES(1)) dut(
        .clk(clk),.rst_n(rst_n),.frame_start(fs),.function_press(fn),.confirm_press(ok),
        .function_long_press(fl),.confirm_long_press(ol),.history_count(history),
        .snapshot_busy(busy),.snapshot_done(done),.snapshot_error(err),.menu_index(menu),
        .median_enable(med),.canny_enable(can),.display_mode(view),.threshold_enable(te),
        .threshold_add(add),.threshold_sub(sub),.ddr_mode(mode),.replay_offset(offset),
        .replay_active(active),.replay_paused(paused),.snapshot_request(req),.snapshot_cancel(cancel),.saving(saving));
    task check;input good;input [255:0] label;
        begin if(good!==1'b1)begin errors=errors+1;$display("ERROR %s",label);end end
    endtask
    task press;input integer key;
        begin @(negedge clk);fn=key==0;fl=key==1;ok=key==2;ol=key==3;
            @(posedge clk);#1;
            @(negedge clk);fn=0;fl=0;ok=0;ol=0;
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        check(menu==4&&med&&can&&!view,"display reset");
        press(2);check(view,"display confirm toggle");press(3);check(view,"display confirm long blank");
        press(1);check(view&&menu==4,"function long display no action");
        press(0);check(menu==3,"algorithm order");press(2);check(!can,"algorithm toggle");
        press(0);check(menu==0,"median order");press(2);check(!med,"median toggle");
        press(0);check(menu==1&&te,"threshold order");
        @(negedge clk);ok=1;#1;check(add&&!sub,"threshold add");ok=0;ol=1;#1;check(sub&&!add,"threshold sub");ol=0;
        press(0);check(menu==2,"history order");history=0;press(1);check(!active,"empty history");
        history=8;press(1);check(active&&offset==7,"replay oldest");
        press(2);check(paused,"pause");press(2);check(!paused,"resume");
        press(3);check(req&&saving,"save");press(0);check(menu==5&&!active&&cancel,"inspect and exit replay");
        press(0);check(menu==4,"menu wrap");
        @(negedge clk);fn=1;fl=1;@(posedge clk);#1;check(menu==3&&view,"short priority over long");
        if(errors==0)$display("TEST PASSED: modern_menu");else $display("TEST FAILED: modern_menu %0d",errors);
        $finish;
    end
endmodule
