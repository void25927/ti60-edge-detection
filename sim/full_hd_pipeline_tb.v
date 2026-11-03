`timescale 1ns/1ps

// 独立整图参考模型，检查灰度与边缘输出使用同一源坐标。
module pipeline_case #(
    parameter W=8,H=6,POL=0,FRAMES=3,GAPS=1
)(output reg done,output integer errors);
    localparam LATENCY=8;
    reg clk=0,rst_n=0;
    reg [7:0] r=0,g=0,b=0;
    reg v=0,hs=0,vs=POL;
    wire [7:0] out_gray,out_edge;
    wire [7:0] out_red,out_green,out_blue;
    wire ov,ow,oh,of;
    reg [7:0] reference_image[0:W*H-1];
    reg [23:0] reference_rgb[0:W*H-1];
    reg [7:0] expected_gray_pipe[0:LATENCY-1];
    reg [7:0] expected_edge_pipe[0:LATENCY-1];
    reg [23:0] expected_rgb_pipe[0:LATENCY-1];
    reg [3:0] expected_ctrl_pipe[0:LATENCY-1];
    integer x,y,k,gray,gx,gy,mag,expected_edge;
    integer frame,row,col,cycles,valid_count;
    reg window_ok;
    reg [23:0] color;

    always #5 clk=~clk;

    edge_video_pipeline #(
        .IMAGE_WIDTH(W),.ADDR_WIDTH($clog2(W)),.THRESHOLD(128),
        .EDGE_MODE(0),
        .VSYNC_ACTIVE_LEVEL(POL)
    ) dut (
        .clk(clk),.rst_n(rst_n),.in_red(r),.in_green(g),.in_blue(b),
        .in_valid(v),.in_hsync(hs),.in_vsync(vs),
        .in_high_threshold(11'd128),.in_low_threshold(11'd64),
        .in_median_enable(1'b1),.in_canny_enable(1'b1),
        .out_red(out_red),.out_green(out_green),.out_blue(out_blue),
        .out_gray(out_gray),.out_edge(out_edge),.out_valid(ov),
        .out_window_valid(ow),.out_hsync(oh),.out_vsync(of)
    );

    function [23:0] scene;
        input integer xx,yy,ff;
        integer rr,gg,bb;
        begin
            case(ff%3)
                0: begin rr=64;gg=128;bb=192;end
                1: begin
                    rr=(xx*37+yy*19)&255;
                    gg=(xx*11+yy*47)&255;
                    bb=(xx*71+yy*7)&255;
                end
                default: begin
                    rr=(((xx/3)+(yy/2))%2)?255:0;
                    gg=rr;bb=rr;
                end
            endcase
            scene={rr[7:0],gg[7:0],bb[7:0]};
        end
    endfunction

    always @(posedge clk) begin
        if(!rst_n) begin
            x=0;y=0;
            for(k=0;k<LATENCY;k=k+1) begin
                expected_gray_pipe[k]=0;
                expected_edge_pipe[k]=0;
                expected_rgb_pipe[k]=0;
                expected_ctrl_pipe[k]=0;
            end
        end else begin
            for(k=LATENCY-1;k>0;k=k-1) begin
                expected_gray_pipe[k]=expected_gray_pipe[k-1];
                expected_edge_pipe[k]=expected_edge_pipe[k-1];
                expected_rgb_pipe[k]=expected_rgb_pipe[k-1];
                expected_ctrl_pipe[k]=expected_ctrl_pipe[k-1];
            end
            expected_gray_pipe[0]=0;
            expected_edge_pipe[0]=0;
            expected_rgb_pipe[0]=0;
            expected_ctrl_pipe[0]={vs,hs,1'b0,v};

            if(vs==POL) begin x=0;y=0;end
            else if(v) begin
                gray=(77*r+150*g+29*b)/256;
                reference_image[y*W+x]=gray;
                reference_rgb[y*W+x]={r,g,b};
                window_ok=(x>=2 && y>=2);
                expected_edge=0;
                if(window_ok) begin
                    gx=reference_image[(y-2)*W+x]+2*reference_image[(y-1)*W+x]+gray
                       -reference_image[(y-2)*W+x-2]-2*reference_image[(y-1)*W+x-2]
                       -reference_image[y*W+x-2];
                    gy=reference_image[y*W+x-2]+2*reference_image[y*W+x-1]+gray
                       -reference_image[(y-2)*W+x-2]-2*reference_image[(y-2)*W+x-1]
                       -reference_image[(y-2)*W+x];
                    mag=(gx<0?-gx:gx)+(gy<0?-gy:gy);
                    if(mag>=128) expected_edge=255;
                end
                expected_gray_pipe[0]=window_ok?reference_image[(y-1)*W+x-1]:0;
                expected_edge_pipe[0]=expected_edge;
                expected_rgb_pipe[0]=window_ok?reference_rgb[(y-1)*W+x-1]:0;
                expected_ctrl_pipe[0]={vs,hs,window_ok,v};
                if(x==W-1) begin x=0;y=y+1;end
                else x=x+1;
            end
        end

        #1;cycles=cycles+1;
        if(ov) valid_count=valid_count+1;
        if(out_gray!==expected_gray_pipe[LATENCY-1] ||
           out_edge!==expected_edge_pipe[LATENCY-1] ||
           {out_red,out_green,out_blue}!==expected_rgb_pipe[LATENCY-1] ||
           {of,oh,ow,ov}!==expected_ctrl_pipe[LATENCY-1]) begin
            if(errors<8)
                $display("ERROR pipeline %0dx%0d cycle=%0d gray=%0d/%0d edge=%0d/%0d rgb=%h/%h ctrl=%b/%b",
                    W,H,cycles,out_gray,expected_gray_pipe[LATENCY-1],
                    out_edge,expected_edge_pipe[LATENCY-1],
                    {out_red,out_green,out_blue},expected_rgb_pipe[LATENCY-1],
                    {of,oh,ow,ov},expected_ctrl_pipe[LATENCY-1]);
            errors=errors+1;
        end
    end

    task blank;
        input integer count;
        input sync_level;
        integer j;
        begin
            for(j=0;j<count;j=j+1) begin
                @(negedge clk);#1;v=0;hs=j%2;vs=sync_level;
            end
        end
    endtask

    task sample;
        input integer xx,yy,ff;
        begin
            @(negedge clk);#1;
            color=scene(xx,yy,ff);
            r=color[23:16];g=color[15:8];b=color[7:0];
            v=1;hs=1;vs=!POL;
        end
    endtask

    task reset_check;
        begin
            @(negedge clk);#2;rst_n=0;v=0;#1;
            if({out_gray,out_edge,ov,ow,oh,of}!==0) errors=errors+1;
            repeat(4) @(negedge clk);rst_n=1;
        end
    endtask

    initial begin
        done=0;errors=0;cycles=0;valid_count=0;x=0;y=0;
        reset_check();
        for(frame=0;frame<FRAMES;frame=frame+1) begin
            blank(12,POL);blank(3,!POL);
            for(row=0;row<H;row=row+1) begin
                for(col=0;col<W;col=col+1) begin
                    sample(col,row,frame+1);
                    if(GAPS && col==W/2) blank(2,!POL);
                end
                blank(4,!POL);
            end
            blank(12,!POL);
            if(frame==0 && GAPS) begin
                blank(4,POL);blank(3,!POL);
                sample(0,0,0);sample(1,0,0);sample(2,0,0);
                blank(12,!POL);
            end
            if(frame==1 && GAPS) reset_check();
        end
        blank(15,!POL);
        if(valid_count != W*H*FRAMES + ((GAPS)?3:0)) begin
            $display("ERROR pipeline pixel count=%0d expected=%0d",
                     valid_count,W*H*FRAMES+((GAPS)?3:0));
            errors=errors+1;
        end
        $display("Pipeline %0dx%0d pol=%0d frames=%0d cycles=%0d pixels=%0d errors=%0d",
                 W,H,POL,FRAMES,cycles,valid_count,errors);
        done=1;
    end
endmodule

// 高级Canny整链检查：平坦图像必须无边缘，并检查31拍控制延迟和有效区大小。
module canny_pipeline_case(output reg done,output integer errors);
    localparam W=24,H=20,LATENCY=31;
    reg clk=0,rst_n=0,v=0,hs=0,vs=0;
    reg [7:0] r=100,g=100,b=100;
    wire [7:0] gray,edge_pixel,out_red,out_green,out_blue;wire ov,ow,oh,of;
    reg [3:0] ctrl[0:LATENCY-1];
    integer x,y,k,valid_count,window_count;
    always #5 clk=~clk;
    edge_video_pipeline #(.IMAGE_WIDTH(W),.ADDR_WIDTH($clog2(W)),.EDGE_MODE(1),.VSYNC_ACTIVE_LEVEL(0)) dut(
        .clk(clk),.rst_n(rst_n),.in_red(r),.in_green(g),.in_blue(b),
        .in_valid(v),.in_hsync(hs),.in_vsync(vs),
        .in_high_threshold(11'd80),.in_low_threshold(11'd40),
        .in_median_enable(1'b1),.in_canny_enable(1'b1),
        .out_red(out_red),.out_green(out_green),.out_blue(out_blue),
        .out_gray(gray),.out_edge(edge_pixel),.out_valid(ov),.out_window_valid(ow),
        .out_hsync(oh),.out_vsync(of));
    always @(posedge clk)begin
        if(!rst_n)for(k=0;k<LATENCY;k=k+1)ctrl[k]=0;
        else begin for(k=LATENCY-1;k>0;k=k-1)ctrl[k]=ctrl[k-1];ctrl[0]={vs,hs,1'b0,v};end
        #1;
        if({of,oh,ov}!=={ctrl[LATENCY-1][3:2],ctrl[LATENCY-1][0]})begin if(errors<8)$display("ERROR canny control");errors=errors+1;end
        if(ov)begin valid_count=valid_count+1;if(edge_pixel!==0)begin if(errors<8)$display("ERROR flat image edge=%0d",edge_pixel);errors=errors+1;end end
        if(ow)begin
            window_count=window_count+1;
            if(gray!==8'd100 || {out_red,out_green,out_blue}!==24'h646464)begin
                if(errors<8)$display("ERROR aligned gray/rgb=%0d/%h",gray,{out_red,out_green,out_blue});
                errors=errors+1;
            end
        end
    end
    initial begin done=0;errors=0;valid_count=0;window_count=0;repeat(5)@(negedge clk);rst_n=1;
        repeat(8)begin @(negedge clk);v=0;hs=0;vs=0;end
        repeat(3)begin @(negedge clk);vs=1;end
        for(y=0;y<H;y=y+1)begin for(x=0;x<W;x=x+1)begin @(negedge clk);v=1;hs=1;vs=1;end @(negedge clk);v=0;hs=0;end
        repeat(40)begin @(negedge clk);v=0;hs=0;vs=1;end
        if(valid_count!=W*H)begin $display("ERROR canny pixel count=%0d/%0d",valid_count,W*H);errors=errors+1;end
        if(window_count!=(W-12)*(H-12))begin $display("ERROR canny window count=%0d/%0d",window_count,(W-12)*(H-12));errors=errors+1;end
        done=1;
    end
endmodule

// 高级Canny彩色坐标检查：验证六级3×3窗口后RGB仍对应同一中心像素。
module canny_color_case(output reg done,output integer errors);
    localparam W=1920,H=1080,LATENCY=31;
    reg clk=0,rst_n=0,v=0,hs=0,vs=0;
    reg [7:0] r=0,g=0,b=0;
    wire [7:0] out_red,out_green,out_blue,gray,edge_pixel;
    wire ov,ow,oh,of;
    reg [23:0] reference_rgb[0:W*H-1];
    reg [23:0] expected_rgb[0:LATENCY-1];
    integer source_x,source_y,drive_x,drive_y,k;
    always #5 clk=~clk;

    edge_video_pipeline #(.IMAGE_WIDTH(W),.ADDR_WIDTH($clog2(W)),.EDGE_MODE(1),.VSYNC_ACTIVE_LEVEL(0)) dut(
        .clk(clk),.rst_n(rst_n),.in_red(r),.in_green(g),.in_blue(b),
        .in_valid(v),.in_hsync(hs),.in_vsync(vs),
        .in_high_threshold(11'd80),.in_low_threshold(11'd40),
        .in_median_enable(1'b1),.in_canny_enable(1'b1),
        .out_red(out_red),.out_green(out_green),.out_blue(out_blue),
        .out_gray(gray),.out_edge(edge_pixel),.out_valid(ov),.out_window_valid(ow),
        .out_hsync(oh),.out_vsync(of));

    always @(posedge clk) begin
        if(!rst_n) begin
            source_x=0;
            source_y=0;
            for(k=0;k<LATENCY;k=k+1) expected_rgb[k]=0;
        end else begin
            for(k=LATENCY-1;k>0;k=k-1) expected_rgb[k]=expected_rgb[k-1];
            expected_rgb[0]=0;
            if(v) begin
                reference_rgb[source_y*W+source_x]={r,g,b};
                if(source_x>=12 && source_y>=12)
                    expected_rgb[0]=reference_rgb[(source_y-6)*W+source_x-6];
                if(source_x==W-1) begin
                    source_x=0;
                    source_y=source_y+1;
                end else source_x=source_x+1;
            end
        end
        #1;
        if({out_red,out_green,out_blue}!==expected_rgb[LATENCY-1]) begin
            if(errors<8)
                $display("ERROR canny RGB alignment got=%h expected=%h",
                         {out_red,out_green,out_blue},expected_rgb[LATENCY-1]);
            errors=errors+1;
        end
    end

    initial begin
        done=0;errors=0;source_x=0;source_y=0;
        repeat(5)@(negedge clk);rst_n=1;
        repeat(8)begin @(negedge clk);v=0;hs=0;vs=0;end
        repeat(3)begin @(negedge clk);vs=1;end
        for(drive_y=0;drive_y<H;drive_y=drive_y+1)begin
            for(drive_x=0;drive_x<W;drive_x=drive_x+1)begin
                @(negedge clk);v=1;hs=1;vs=1;
                r=(drive_x*13+drive_y*5)&8'hff;
                g=(drive_x*3+drive_y*17)&8'hff;
                b=(drive_x*19+drive_y*7)&8'hff;
            end
            @(negedge clk);v=0;hs=0;
        end
        repeat(50)begin @(negedge clk);v=0;hs=0;vs=1;end
        done=1;
    end
endmodule

module full_hd_pipeline_tb;
    wire d0,d1,df,dc,drgb;
    wire [31:0] e0,e1,ef,ec,ergb;
    integer errors;
    pipeline_case #(8,6,0,3,1) a(d0,e0);
    pipeline_case #(8,6,1,3,1) b(d1,e1);
    pipeline_case #(1920,1080,0,1,0) full_frame(df,ef);
    canny_pipeline_case canny(dc,ec);
    canny_color_case canny_rgb(drgb,ergb);

    initial begin
        errors=0;
        wait(d0&&d1&&df&&dc&&drgb);#2;errors=e0+e1+ef+ec+ergb;
        if(errors==0) $display("TEST PASSED: full_hd_pipeline");
        else $display("TEST FAILED: full_hd_pipeline, %0d error(s)",errors);
        $finish;
    end
    initial begin
        #100000000;
        errors=errors+1;
        $display("TEST FAILED: full_hd_pipeline timeout");
        $finish;
    end
endmodule


