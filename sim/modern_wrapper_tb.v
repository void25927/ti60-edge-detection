`timescale 1ns/1ps
module modern_wrapper_tb;
    reg clk=0,rst_n=0,de=0,hs=0,vs=0;
    wire [23:0] rgb_o;
    wire de_o,hs_o,vs_o;
    integer errors=0,i,x,y,checks=0;
    reg [2:0] delayed[0:3];
    always #5 clk=~clk;
    video_ui_overlay #(.MODERN_UI(1),.CLK_FREQ_HZ(1000)) dut(
        .clk(clk),.rst_n(rst_n),.in_rgb(24'h123456),.in_de(de),.in_hsync(hs),.in_vsync(vs),
        .in_mode(2'd0),.in_display_mode(1'b0),.in_high_threshold(11'd80),.in_low_threshold(11'd40),
        .in_replay_offset(2'd0),.in_ddr_error(1'b0),.in_video_error(1'b0),.in_menu(3'd4),
        .in_median_enable(1'b1),.in_canny_enable(1'b1),.in_saving(1'b0),.in_saved_valid(3'd0),
        .inspection_background_ready(1'b1),.inspection_template_valid(1'b0),
        .inspection_learning(1'b0),.inspection_enabled(1'b0),.inspection_matched(1'b0),
        .inspection_fault(1'b0),.inspection_status(2'd0),.inspection_frame_id(32'd0),
        .inspection_detection_id(32'd0),.inspection_track_id(16'd0),.inspection_count(3'd0),
        .inspection_diagnostic(8'd0),.out_rgb(rgb_o),.out_de(de_o),.out_hsync(hs_o),.out_vsync(vs_o));
    always @(posedge clk)begin
        if(!rst_n)for(i=0;i<4;i=i+1)delayed[i]=0;
        else begin
            for(i=3;i>0;i=i-1)delayed[i]=delayed[i-1];
            delayed[0]={de,hs,vs};#1;
            checks=checks+1;
            if({de_o,hs_o,vs_o}!==delayed[3])begin
                errors=errors+1;if(errors<4)$display("ERROR wrapper latency");
            end
        end
    end
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        vs=1;repeat(3)@(negedge clk);vs=0;
        repeat(20)@(negedge clk);vs=1;
        for(y=0;y<84;y=y+1)begin
            for(x=0;x<1920;x=x+1)begin @(negedge clk);de=1;hs=1;end
            repeat(4)begin @(negedge clk);de=0;hs=0;end
        end
        repeat(8)@(negedge clk);
        if(dut.high_bcd!==16'h0080)errors=errors+1;
        if(errors==0)$display("TEST PASSED: modern_wrapper checks=%0d",checks);
        else $display("TEST FAILED: modern_wrapper errors=%0d",errors);
        $finish;
    end
endmodule
