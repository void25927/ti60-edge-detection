`timescale 1ns/1ps
// 高度大于宽度，复现旧版底部横坐标清零问题。
module bayer_coordinate_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,v=0,hs=0,vs=0;
    wire ov,oh,of; wire[7:0] r,g,b;
    integer errors=0, checks=0, expected_x=0, row,x, lower_checks=0;
    VIP_RAW8_RGB888 #(.IMG_HDISP(16),.IMG_VDISP(20)) dut(
        .clk(clk),.rst_n(rst_n),.mirror(2'b00),.per_frame_vsync(vs),
        .per_frame_href(v),.per_frame_hsync(hs),.per_img_RAW(8'd100),
        .post_frame_vsync(of),.post_frame_href(ov),.post_frame_hsync(oh),
        .post_img_red(r),.post_img_green(g),.post_img_blue(b));
    always @(posedge clk) begin
        if(!rst_n || !dut.matrix_frame_href) expected_x=0;
        else expected_x=(expected_x<15)?expected_x+1:0;
        #1;
        if(rst_n) begin
            checks=checks+1;
            if(dut.point_cnt!==expected_x) begin errors=errors+1;if(errors<5)$display("ERROR: Bayer x row=%d",dut.line_cnt);end
            if(dut.line_cnt>=16 && dut.matrix_frame_href) lower_checks=lower_checks+1;
        end
    end
    initial begin
        repeat(4) @(negedge clk);rst_n=1;vs=1;
        for(row=0;row<20;row=row+1) begin
            v=1;hs=1; for(x=0;x<16;x=x+1) @(negedge clk);
            v=0;hs=0;repeat(10) @(negedge clk);
        end
        vs=0;repeat(10) @(negedge clk);
        if(lower_checks<32) errors=errors+1;
        if(!errors)$display("TEST PASSED: bayer_coordinate, %d checks",checks);
        else $display("TEST FAILED: bayer_coordinate, %d errors",errors);
        $finish;
    end
endmodule
