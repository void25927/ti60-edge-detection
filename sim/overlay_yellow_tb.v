`timescale 1ns/1ps
module overlay_yellow_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,v=0,edge_bit=0;
    reg[7:0] level=0;
    wire[7:0] r,g,b;wire ov,oh,of;
    integer errors=0,i;
    edge_overlay #(.EDGE_R(255),.EDGE_G(255),.EDGE_B(0),.EXPAND_PIXELS(4),.ADAPTIVE_COLOR(0)) dut(
        .clk(clk),.rst_n(rst_n),.in_valid(v),.in_hsync(v),.in_vsync(1'b1),
        .in_red(level),.in_green(level),.in_blue(level),.in_edge(edge_bit),
        .out_red(r),.out_green(g),.out_blue(b),.out_valid(ov),.out_hsync(oh),.out_vsync(of));
    task row_test;
        input[7:0] brightness;
        input[23:0] edge_color;
        begin
            @(negedge clk);v=0;edge_bit=0;level=brightness;
            @(negedge clk);v=1;
            for(i=0;i<8;i=i+1) begin
                edge_bit=(i==1);@(posedge clk);#1;
                if({r,g,b}!==((i>=1 && i<=5)?edge_color:{3{brightness}})) errors=errors+1;
                if(!ov || !oh || !of) errors=errors+1;
                @(negedge clk);
            end
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        row_test(200,24'hffff00);row_test(40,24'hffff00);row_test(160,24'hffff00);
        if(!errors)$display("TEST PASSED: overlay_yellow");else $display("TEST FAILED: overlay_yellow %d errors",errors);
        $finish;
    end
endmodule


