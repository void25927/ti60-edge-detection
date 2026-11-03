`timescale 1ns/1ps
`include "ui_assets.vh"
module modern_ui_tb;
    reg clk=0,rst_n=0,de=0,hs=1,vs=0;
    reg [23:0] rgb=0;
    reg [2:0] menu=4;
    reg matched=1;
    reg [7:0] diagnostic=0;
    reg [15:0] threshold_bcd=16'h0080;
    wire [23:0] output_rgb;
    wire output_de,output_hs,output_vs;
    integer errors=0,checks=0,x,y,k,fp,output_count=0;
    integer output_x=0,output_y=0;
    reg capturing=0;
    reg [23:0] rgb_delay[0:2];
    reg [2:0] ctl_delay[0:2];
    reg [10:0] x_delay[0:2],y_delay[0:2];
    reg [23:0] expected_pixel;
    always #5 clk=~clk;
    vision_ui_renderer dut(.clk(clk),.rst_n(rst_n),.in_rgb(rgb),.in_de(de),.in_hsync(hs),.in_vsync(vs),
        .menu(menu),.median_enable(1'b1),.canny_enable(1'b1),.replay_active(1'b0),.replay_paused(1'b0),.saving(1'b0),
        .threshold_bcd(threshold_bcd),.fps_text(" 60"),.background_ready(1'b1),.template_valid(1'b1),
        .learning(1'b0),.enabled(1'b1),.matched(matched),.fault(1'b0),.ddr_error(1'b0),.video_error(1'b0),
        .result_status(2'd1),.object_count(3'd1),.frame_id(32'd14),.detection_id(32'd14),.diagnostic(diagnostic),
        .out_rgb(output_rgb),.out_de(output_de),.out_hsync(output_hs),.out_vsync(output_vs));
    function [23:0] scene;
        input integer px,py;
        integer dx,dy,dist1,dist2;
        reg plate,hole;
        begin
            scene=((px/24+py/24)%2)?24'h454b52:24'h42484f;
            plate=(px>=600&&px<1420&&py>=360&&py<660)||(px>=780&&px<1240&&py>=280&&py<740);
            dx=px-720;dy=py-510;dist1=dx*dx+dy*dy;
            dx=px-1300;dist2=dx*dx+dy*dy;
            hole=dist1<2500||dist2<2500;
            if(plate&&!hole)scene=(py%4==0)?24'hbac0c6:24'hc8cdd2;
            if((dist1>=2401&&dist1<=2601)||(dist2>=2401&&dist2<=2601))scene=24'hffea30;
            if(plate&&!hole&&((px==600||px==1419)||(py==360||py==659)||(px==780||px==1239)||(py==280||py==739)))scene=24'hffea30;
        end
    endfunction
    always @(posedge clk)begin
        if(!rst_n)begin
            for(k=0;k<3;k=k+1)begin ctl_delay[k]=0;rgb_delay[k]=0;x_delay[k]=0;y_delay[k]=0;end
        end else begin
            for(k=2;k>0;k=k-1)begin ctl_delay[k]=ctl_delay[k-1];rgb_delay[k]=rgb_delay[k-1];x_delay[k]=x_delay[k-1];y_delay[k]=y_delay[k-1];end
            ctl_delay[0]={de,hs,vs};rgb_delay[0]=rgb;x_delay[0]=dut.x;y_delay[0]=dut.y;
            #1;
            if({output_de,output_hs,output_vs}!==ctl_delay[2])begin
                errors=errors+1;if(errors<4)$display("ERROR video control alignment");
            end
            if(output_de)begin
                checks=checks+1;
                if(y_delay[2]>=400&&y_delay[2]<700&&output_rgb!==rgb_delay[2])begin
                    errors=errors+1;if(errors<4)$display("ERROR transparent center");
                end
                // Status-line gaps must be completely transparent.
                if(x_delay[2]>=32&&x_delay[2]<480&&y_delay[2]>=128&&y_delay[2]<136&&output_rgb!==rgb_delay[2])begin
                    errors=errors+1;if(errors<4)$display("ERROR transparent status gap");
                end
                // Display-menu long-confirm description is blank; short-confirm switches view.
                if(x_delay[2]>=1440&&y_delay[2]>=1040&&y_delay[2]<1072&&output_rgb!==24'h08243c&&x_delay[2]!=1440&&x_delay[2]!=960)begin
                    errors=errors+1;if(errors<4)$display("ERROR blank confirm description");
                end
                if(capturing)begin
                    $fwrite(fp,"%c%c%c",output_rgb[23:16],output_rgb[15:8],output_rgb[7:0]);
                    output_count=output_count+1;
                end
            end
        end
    end
    initial begin
        fp=$fopen("sim/modelsim_modern_ui/modern_ui.ppm","wb");
        $fwrite(fp,"P6\n1920 1080\n255\n");
        repeat(5)@(negedge clk);rst_n=1;
        repeat(5)@(negedge clk);vs=1;capturing=1;
        for(y=0;y<1080;y=y+1)begin
            for(x=0;x<1920;x=x+1)begin @(negedge clk);de=1;hs=1;rgb=scene(x,y);end
            repeat(4)begin @(negedge clk);de=0;hs=0;end
        end
        repeat(8)@(negedge clk);capturing=0;$fclose(fp);
        if(output_count!=1920*1080)begin errors=errors+1;$display("ERROR pixel count %0d",output_count);end
        if(dut.result_string!==`UI_S_PASS)begin errors=errors+1;$display("ERROR matching result");end
        // A new frame lacking a match cannot inherit the last PASS.
        vs=0;matched=0;repeat(5)@(negedge clk);vs=1;
        for(y=0;y<=80;y=y+1)begin
            for(x=0;x<1920;x=x+1)begin @(negedge clk);de=1;end
            repeat(4)begin @(negedge clk);de=0;end
        end
        if(dut.result_string!==`UI_S_WAIT)begin errors=errors+1;$display("ERROR stale PASS");end
        // 具体诊断必须跨过ROM流水仍可显示，不能被残留PASS遮住。
        vs=0;diagnostic=8'h38;matched=1;repeat(5)@(negedge clk);vs=1;
        for(y=0;y<=328;y=y+1)begin
            for(x=0;x<1920;x=x+1)begin @(negedge clk);de=1;end
            repeat(4)begin @(negedge clk);de=0;end
        end
        if(dut.result_string!==`UI_S_FAULT || dut.diagnostic_q!==8'h38)begin errors=errors+1;$display("ERROR E38 priority");end
        if(dut.hint(4,2)!==`UI_S_TOGGLE_DISPLAY || dut.hint(4,3)!==0 || dut.hint(4,1)!==0)errors=errors+1;
        // 阈值可变位数仍从同一x=224开始，而不是隐藏高位留下空白。
        force dut.x=11'd224;force dut.y=11'd96;
        threshold_bcd=16'h0080;#1;
        if(dut.g_index!==0 || dut.digit!==8 || !dut.g_text)errors=errors+1;
        threshold_bcd=16'h0008;#1;if(dut.digit!==8 || dut.threshold_skip!==3)errors=errors+1;
        threshold_bcd=16'h0800;#1;if(dut.digit!==8 || dut.threshold_skip!==1)errors=errors+1;
        threshold_bcd=16'h2040;#1;if(dut.digit!==2 || dut.threshold_skip!==0)errors=errors+1;
        threshold_bcd=16'h0000;#1;if(dut.digit!==0 || dut.threshold_skip!==3)errors=errors+1;
        release dut.x;release dut.y;
        // 英文每字占一半宽布局单元；中文第二半携带bit8，不删笔画。
        if(dut.strings[`UI_S_CANNY*32+5]!==9'd0 || dut.strings[`UI_S_CANNY*32+1][8]!==0 ||
           dut.strings[`UI_S_ON*32+1][8]!==1)errors=errors+1;
        if(errors==0)$display("TEST PASSED: modern_ui checks=%0d",checks);
        else $display("TEST FAILED: modern_ui errors=%0d",errors);
        $finish;
    end
endmodule
