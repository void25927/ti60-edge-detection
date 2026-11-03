`timescale 1ns/1ps
module threshold_case #(parameter T=128)(output reg done,output integer errors);
    reg clk=0,rst_n=0;
    reg [10:0] g=0;
    reg [10:0] runtime_threshold=T;
    reg v=0,w=0,h=0,f=0;
    wire [7:0] pixel; wire ov,ow,oh,of;
    reg [7:0] expected; reg [3:0] ec;
    integer n,seed,checks;
    always #5 clk=~clk;
    gradient_threshold #(.THRESHOLD(T)) dut(.clk(clk),.rst_n(rst_n),
        .in_gradient(g),.in_valid(v),.in_window_valid(w),.in_hsync(h),.in_vsync(f),
        .in_threshold(runtime_threshold),
        .out_pixel(pixel),.out_valid(ov),.out_window_valid(ow),.out_hsync(oh),.out_vsync(of));
    // 独立整数参考比较：包含等于阈值的情况。
    function [7:0] reference;
        input integer value,threshold;
        input valid,window_ok;
        begin
            reference=0;
            if(valid && window_ok && value>=threshold) reference=255;
        end
    endfunction
    always @(posedge clk) begin
        expected=rst_n?reference(g,T,v,w):0;
        ec=rst_n?{f,h,v&&w,v}:0;
        #1;checks=checks+1;
        if(pixel!==expected || {of,oh,ow,ov}!==ec) begin
            if(errors<8) $display("ERROR: threshold T=%0d g=%0d",T,g);
            errors=errors+1;
        end
    end
    initial begin
        done=0;errors=0;checks=0;seed=7;
        repeat(3) @(negedge clk);rst_n=1;
        // 穷举11位输入范围，包括0、阈值±1、2040和2047。
        for(n=0;n<2048;n=n+1) begin
            @(negedge clk);#1;g=n;v=1;w=1;h=n%2;f=(n/2)%2;
        end
        for(n=0;n<512;n=n+1) begin
            @(negedge clk);#1;
            g=$random(seed);v=n%2;w=(n/2)%2;h=(n/4)%2;f=(n/8)%2;
            if(n==255) begin
                #1;rst_n=0;#1;
                if({pixel,ov,ow,oh,of}!==0) errors=errors+1;
                repeat(3) @(negedge clk);rst_n=1;
            end
        end
        repeat(3) @(negedge clk);
        $display("Threshold=%0d checked_cycles=%0d errors=%0d",T,checks,errors);
        done=1;
    end
endmodule
module gradient_threshold_tb;
    wire d0,d128,d2047; wire [31:0] e0,e128,e2047;
    integer errors;
    threshold_case #(0) a(d0,e0);
    threshold_case #(128) b(d128,e128);
    threshold_case #(2047) c(d2047,e2047);
    initial begin
        errors=0;wait(d0&&d128&&d2047);#2;errors=e0+e128+e2047;
        if(errors==0) $display("TEST PASSED: gradient_threshold");
        else $display("TEST FAILED: gradient_threshold, %0d error(s)",errors);
        $finish;
    end
    initial begin #1000000;errors=errors+1;$display("TEST FAILED: gradient_threshold timeout");$finish;end
endmodule
