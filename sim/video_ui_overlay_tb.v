`timescale 1ns / 1ps

module video_ui_overlay_tb;
    localparam W=512;
    localparam H=80;
    reg clk=0;
    reg rst_n=0;
    reg [23:0] pixel=24'h123456;
    reg de=0,hs=0,vs=1;
    reg [1:0] mode=0;
    reg display_mode=0;
    reg [10:0] high_threshold=80;
    reg [10:0] low_threshold=40;
    reg [1:0] replay_offset=3;
    reg ddr_error=0,video_error=0;
    wire [23:0] rgb;
    wire out_de,out_hs,out_vs;
    integer errors=0;
    integer x,y;

    always #5 clk=~clk;
    video_ui_overlay #(.DISPLAY_WIDTH(W),.DISPLAY_HEIGHT(H),
                       .VSYNC_ACTIVE_LEVEL(1'b0)) dut(
        .clk(clk),.rst_n(rst_n),.in_rgb(pixel),.in_de(de),
        .in_hsync(hs),.in_vsync(vs),.in_mode(mode),
        .in_display_mode(display_mode),
        .in_high_threshold(high_threshold),.in_low_threshold(low_threshold),
        .in_replay_offset(replay_offset),.in_ddr_error(ddr_error),
        .in_video_error(video_error),.out_rgb(rgb),.out_de(out_de),
        .in_menu(3'd0),.in_median_enable(1'b1),.in_canny_enable(1'b1),.in_saving(1'b0),.in_saved_valid(3'd0),
        .out_hsync(out_hs),.out_vsync(out_vs)
    );

    task send_line;
        input integer row;
        begin
            hs=1;
            for(x=0;x<W;x=x+1) begin
                @(negedge clk); de=1; pixel=24'h123456;
                @(posedge clk); #1;
                if(row==0 && x==0 && (rgb!==24'h102840 || !out_de)) begin
                    $display("ERROR UI background rgb=%h de=%b",rgb,out_de); errors=errors+1;
                end
                if(row==63 && x==0 && rgb!==24'h40C0FF) begin
                    $display("ERROR separator rgb=%h",rgb); errors=errors+1;
                end
                if(row==64 && x==0 && rgb!==24'h123456) begin
                    $display("ERROR passthrough rgb=%h",rgb); errors=errors+1;
                end
            end
            @(negedge clk); de=0; hs=0;
            @(posedge clk); #1;
            if(out_de!==0) begin $display("ERROR DE delay"); errors=errors+1; end
        end
    endtask

    initial begin
        vs=1;
        repeat(3) @(posedge clk); rst_n=1;
        // VSYNC低有效：从高变低进入场同步，触发阈值BCD转换。
        repeat(3) @(posedge clk);
        vs=0;
        repeat(3) @(posedge clk);
        vs=1;
        repeat(17) @(posedge clk);
        if(dut.high_bcd!==16'h0080 || dut.low_bcd!==16'h0040) begin
            $display("ERROR BCD high=%h low=%h",dut.high_bcd,dut.low_bcd);
            errors=errors+1;
        end

        mode=3; display_mode=1; ddr_error=1; video_error=1;
        for(y=0;y<=64;y=y+1) send_line(y);

        if(out_hs!==0 || out_vs!==1) begin
            $display("ERROR sync alignment"); errors=errors+1;
        end
        if(errors==0) $display("TEST PASSED: video_ui_overlay");
        else $display("TEST FAILED: video_ui_overlay, %0d error(s)",errors);
        $finish;
    end
endmodule
