`timescale 1ns/1ps
module video_auto_levels_tb;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, enable=1, valid=0, hs=0, vs=1, ack=0;
    reg [7:0] r=0,g=0,b=0;
    wire [7:0] ro,go,bo;
    wire vo,ho,so,request,frame_ok;
    wire [9:0] rg,bg;
    wire [15:0] exposure;
    wire [6:0] gain;
    integer errors=0, checks=0, i, j;
    integer er0=0,eg0=0,eb0=0,er1=0,eg1=0,eb1=0;
    reg v0=0,h0=0,s0=1,v1=0,h1=0,s1=1;
    reg check_stream=0;
    video_auto_levels #(.FRAME_PIXELS(16),.MIN_WB_SAMPLES(8),.UPDATE_FRAMES(2),
        .EXP_MAX(256),.EXP_MIN(64),.EXP_STEP(64),.GAIN_MAX(8)) dut(
        .clk(clk),.rst_n(rst_n),.auto_enable(enable),.in_red(r),.in_green(g),.in_blue(b),
        .in_valid(valid),.in_hsync(hs),.in_vsync(vs),.ae_ack_toggle(ack),
        .out_red(ro),.out_green(go),.out_blue(bo),.out_valid(vo),.out_hsync(ho),.out_vsync(so),
        .red_gain(rg),.blue_gain(bg),.exposure_lines(exposure),.analog_gain_index(gain),
        .ae_request_toggle(request),.frame_ok(frame_ok));
    function integer corrected;
        input integer pixel, gain_value;
        integer value;
        begin value=(pixel*gain_value+128)/256; corrected=(value>255)?255:value; end
    endfunction
    always @(posedge clk) if (rst_n) begin
        er1=er0; eg1=eg0; eb1=eb0; v1=v0; h1=h0; s1=s0;
        er0=valid?corrected(r,rg):0; eg0=valid?g:0; eb0=valid?corrected(b,bg):0;
        v0=valid; h0=hs; s0=vs;
        #1;
        if (check_stream) begin
            checks=checks+1;
            if (ro!==er1[7:0] || go!==eg1[7:0] || bo!==eb1[7:0] ||
                vo!==v1 || ho!==h1 || so!==s1) begin
                errors=errors+1; $display("ERROR: data/control alignment at %t",$time);
            end
        end
    end
    task expect_value;
        input integer condition;
        input [255:0] label_text;
        begin checks=checks+1; if (!condition) begin errors=errors+1; $display("ERROR: %s",label_text); end end
    endtask
    task frame;
        input integer red, green, blue, pixels;
        integer k;
        begin
            @(negedge clk); vs=0; valid=0; repeat(6) @(negedge clk);
            for(k=0;k<pixels;k=k+1) begin r=red;g=green;b=blue;valid=1;hs=1; @(negedge clk); end
            valid=0;hs=0; repeat(6) @(negedge clk); vs=1; repeat(6) @(negedge clk);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst_n=1; repeat(3) @(negedge clk); check_stream=1;
        frame(100,100,100,16); frame(100,100,100,16); frame(100,100,100,16);
        expect_value(rg==256 && bg==256 && exposure==256 && gain==0,"neutral frame stable");
        // 帧边界交付上帧统计，随后模拟I2C应答。
        for(i=0;i<7;i=i+1) begin frame(32,32,32,16); ack=request; end
        expect_value(gain==8 && exposure==256,"dark gain reaches limit");
        for(i=0;i<12;i=i+1) begin frame(200,200,200,16); ack=request; end
        expect_value(gain==0 && exposure==64,"bright reduces gain then exposure");
        for(i=0;i<10;i=i+1) begin frame(32,32,32,16); ack=request; end
        expect_value(exposure==256,"dark increases exposure before gain");
        j=rg; frame(60,120,60,16); frame(60,120,60,16);
        expect_value(rg>j && bg>256,"green cast increases red blue");
        // 自动停止及不完整帧不得推动任何反馈。
        enable=0; j=rg;
        for(i=0;i<5;i=i+1) frame(20,200,20,16);
        expect_value(rg==j,"freeze holds gains");
        enable=1; frame(20,200,20,8); frame(20,200,20,8);
        expect_value(rg==j,"partial frame ignored");
        // 曝光邮箱未应答时载荷保持；全黑无白平衡样本，不改变RGB增益。
        for(i=0;i<4;i=i+1) begin frame(0,0,0,16); ack=request; end
        ack=~request;
        j=exposure*128+gain;
        for(i=0;i<6;i=i+1) frame(0,0,0,16);
        expect_value(j==exposure*128+gain,"mailbox payload stable before ACK");
        ack=request;
        // 极端色偏达到增益边界后不得绕回。
        for(i=0;i<150;i=i+1) begin frame(16,220,16,16); ack=request; end
        expect_value(rg==768 && bg==768,"white balance upper clamp");
        for(i=0;i<165;i=i+1) begin frame(239,32,239,16); ack=request; end
        expect_value(rg==128 && bg==128,"white balance lower clamp");
        // 随机视频节拍对照独立定点计算，共512组；停止自动更新。
        enable=0;
        for(i=0;i<512;i=i+1) begin
            @(negedge clk); r=$random;g=$random;b=$random;valid=$random;hs=$random;vs=1;
        end
        @(negedge clk); valid=0; repeat(4) @(negedge clk);
        rst_n=0; #1;
        expect_value(ro==0 && go==0 && bo==0 && !vo && rg==256 && exposure==256,"async reset");
        check_stream=0; repeat(3) @(negedge clk); rst_n=1;
        repeat(3) @(negedge clk); frame(100,100,100,16);
        expect_value(!request && !gain,"reset recovery");
        if(errors==0) $display("TEST PASSED: video_auto_levels, %0d checks",checks);
        else $display("TEST FAILED: video_auto_levels, %0d error(s)",errors);
        $finish;
    end
    initial begin #2000000; $display("TEST FAILED: video_auto_levels timeout"); errors=errors+1; $finish; end
endmodule
