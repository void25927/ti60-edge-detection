`timescale 1ns / 1ps

// 960×1080双完整图像显示自检，DDR和算法支路使用独立行为模型。
module full_hd_display_tb;
    localparam integer W = 1920;
    localparam integer H = 1080;
    localparam integer DW = 1920;

    reg clk=1'b0, rst_n=1'b0;
    reg lcd_de=1'b0, lcd_hsync=1'b0, lcd_vsync=1'b0;
    reg display_mode=1'b0;
    reg ddr_available=1'b1;
    reg request_allowed=1'b0;
    wire [7:0] ddr_data;
    wire ddr_valid = ddr_available;
    wire [12:0] ddr_count = ddr_available ? 13'd2048 : 13'd0;
    wire ddr_request;
    wire [7:0] source_raw;
    wire source_valid,source_hsync,source_vsync;
    wire [7:0] pixel;
    wire [23:0] rgb;
    wire out_valid,out_window_valid,out_region_edge,out_hsync,out_vsync;
    wire active_display_mode;
    wire underflow_seen,frame_sync_error;

    integer errors=0;
    integer source_x=0,source_y=0,source_frame=0;
    integer out_x=0,out_y=0,checked_pixels=0,checked_frames=0;
    integer row,x;
    reg out_valid_d=1'b0;
    reg expected_de=1'b0,expected_hsync=1'b0,expected_vsync=1'b0;

    always #5 clk=~clk;

    function [7:0] raw_value;
        input integer frame_id,y,xpos;
        begin raw_value=(frame_id*17+y*5+xpos*3)&8'hff; end
    endfunction
    function [7:0] gray_value;
        input integer frame_id,y,xpos;
        begin gray_value=(frame_id*29+y*7+xpos*3)&8'hff; end
    endfunction
    function [7:0] edge_value;
        input integer frame_id,y,xpos;
        begin
            if(y<2 || xpos<2) edge_value=8'd0;
            else edge_value=((frame_id+y+xpos)&1)?8'hff:8'h00;
        end
    endfunction
    function [23:0] overlay_value;
        input integer frame_id,y,xpos;
        begin
            if(edge_value(frame_id,y,xpos)!=0)
                overlay_value=24'hff0000;
            else
                overlay_value={raw_value(frame_id,y,xpos),
                               gray_value(frame_id,y,xpos),
                               raw_value(frame_id+1,y,xpos)};
        end
    endfunction

    assign ddr_data = raw_value(source_frame,source_y,source_x);

    // 白平衡两级延迟与原显示预取结构联合验证；本用例关闭自动调参。
    wire [7:0] wb_gray, wb_green, wb_blue;
    wire wb_valid, wb_hsync, wb_vsync;
    reg [7:0] edge_d0=0, edge_d1=0;
    reg [23:0] overlay_d0=0, overlay_d1=0;
    reg window_d0=0, window_d1=0;
    video_auto_levels wb (
        .clk(clk),.rst_n(rst_n),.auto_enable(1'b0),.ae_ack_toggle(1'b0),
        .in_red(gray_value(source_frame,source_y,source_x)),
        .in_green(gray_value(source_frame,source_y,source_x)),
        .in_blue(gray_value(source_frame,source_y,source_x)),
        .in_valid(source_valid),.in_hsync(source_hsync),.in_vsync(source_vsync),
        .out_red(wb_gray),.out_green(wb_green),.out_blue(wb_blue),
        .out_valid(wb_valid),.out_hsync(wb_hsync),.out_vsync(wb_vsync),
        .red_gain(),.blue_gain(),.exposure_lines(),.analog_gain_index(),
        .ae_request_toggle(),.frame_ok()
    );
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            edge_d0<=0;edge_d1<=0;overlay_d0<=0;overlay_d1<=0;window_d0<=0;window_d1<=0;
        end else begin
            edge_d0<=edge_value(source_frame,source_y,source_x); edge_d1<=edge_d0;
            overlay_d0<=overlay_value(source_frame,source_y,source_x);overlay_d1<=overlay_d0;
            window_d0<=source_valid && source_y>=2 && source_x>=2;window_d1<=window_d0;
        end
    end

    gray_edge_display #(.SOURCE_WIDTH(W),.FIFO_START_LEVEL(W)) dut (
        .clk(clk),.rst_n(rst_n),
        .in_lcd_de(lcd_de),.in_lcd_hsync(lcd_hsync),.in_lcd_vsync(lcd_vsync),
        .in_display_mode(display_mode),
        .in_ddr_data(ddr_data),.in_ddr_valid(ddr_valid),.in_ddr_count(ddr_count),
        .out_ddr_request(ddr_request),
        .out_source_raw(source_raw),.out_source_valid(source_valid),
        .out_source_hsync(source_hsync),.out_source_vsync(source_vsync),
        .in_gray(wb_gray),
        .in_edge(edge_d1),
        .in_overlay_rgb(overlay_d1),
        .in_alg_valid(wb_valid),
        .in_window_valid(window_d1),
        .out_pixel(pixel),.out_rgb(rgb),.out_valid(out_valid),
        .out_window_valid(out_window_valid),.out_region_edge(out_region_edge),
        .out_display_mode(active_display_mode),
        .out_hsync(out_hsync),.out_vsync(out_vsync),
        .underflow_seen(underflow_seen),.frame_sync_error(frame_sync_error)
    );

    // FWFT模型：请求上升沿接受当前队首像素，然后移动到下一个像素。
    always @(posedge clk) begin
        if(rst_n && ddr_request && !request_allowed) begin
            errors=errors+1;
            if(errors<12) $display("ERROR DDR request before new-frame FIFO flush");
        end
        if(!rst_n || !lcd_vsync) begin
            source_x<=0;
            source_y<=0;
        end else if(ddr_request) begin
            if(source_raw!==raw_value(source_frame,source_y,source_x)) begin
                errors=errors+1;
                if(errors<12) $display("ERROR source data y=%0d x=%0d",source_y,source_x);
            end
            if(source_x==W-1) begin
                source_x<=0;
                source_y<=source_y+1;
            end else source_x<=source_x+1;
        end
    end

    // 检查显示控制相对LCD输入恰好延迟一拍。
    always @(posedge clk) begin
        expected_de<=lcd_de;
        expected_hsync<=lcd_hsync;
        expected_vsync<=lcd_vsync;
    end

    always @(negedge clk) begin : output_checker
        integer source_col;
        reg [7:0] expected_pixel;
        reg [23:0] expected_rgb;
        reg expected_window;
        if(rst_n) begin
            if({out_valid,out_hsync,out_vsync}!==
               {expected_de,expected_hsync,expected_vsync}) begin
                errors=errors+1;
                if(errors<12) $display("ERROR sync alignment y=%0d x=%0d",out_y,out_x);
            end

            if(out_valid) begin
                source_col=out_x;
                if(ddr_available) begin
                    if(active_display_mode) begin
                        expected_pixel=gray_value(source_frame,out_y,source_col);
                        expected_rgb=overlay_value(source_frame,out_y,source_col);
                        expected_window=(out_y>=2)&&(source_col>=2);
                    end else begin
                        expected_pixel=(out_x<DW/2)?
                            gray_value(source_frame,out_y,source_col):
                            edge_value(source_frame,out_y,source_col);
                        expected_rgb=(out_x<DW/2)?
                            {3{gray_value(source_frame,out_y,source_col)}}:
                            {3{edge_value(source_frame,out_y,source_col)}};
                        expected_window=(out_y>=2)&&(source_col>=2);
                    end
                end else begin
                    // 欠数时必须安全输出黑色，不能显示旧缓存内容。
                    expected_pixel=8'd0;
                    expected_rgb=24'd0;
                    expected_window=1'b0;
                end

                if(pixel!==expected_pixel || rgb!==expected_rgb ||
                   out_region_edge!==(!active_display_mode && out_x>=DW/2) ||
                   out_window_valid!==expected_window) begin
                    errors=errors+1;
                    if(errors<12)
                        $display("ERROR pixel frame=%0d y=%0d x=%0d got=%0d/%h exp=%0d/%h region=%b win=%b/%b",
                                 source_frame,out_y,out_x,pixel,rgb,expected_pixel,expected_rgb,
                                 out_region_edge,out_window_valid,expected_window);
                end
                if(ddr_available)
                    checked_pixels=checked_pixels+1;
                if(out_x==DW-1) begin
                    out_x=0;
                    if(out_y==H-1) begin
                        out_y=0;
                        checked_frames=checked_frames+1;
                    end else out_y=out_y+1;
                end else out_x=out_x+1;
            end
        end
        out_valid_d=out_valid;
    end

    task pulse_frame_sync;
        input integer next_frame;
        input integer provide_new_data;
        begin
            // 场同步开始时保留旧FIFO数据，模拟真实硬件的延迟复位。
            @(negedge clk);lcd_de=0;lcd_hsync=0;lcd_vsync=0;
            ddr_available=1;
            request_allowed=0;
            repeat(264) @(posedge clk);
            source_frame=next_frame;
            out_x=0;out_y=0;
            @(negedge clk);lcd_vsync=1;lcd_hsync=1;
            // axi4_ctrl在场同步结束后才清空读FIFO。
            repeat(4) @(posedge clk);
            ddr_available=0;
            repeat(40) @(posedge clk);
            if(provide_new_data) begin
                ddr_available=1;
                request_allowed=1;
            end
            // 模拟垂直后沿；此期间模块完成第0行预取。
            repeat(2300) @(posedge clk);
        end
    endtask

    task send_active_frame;
        input integer frame_id;
        input integer requested_display_mode;
        begin
            display_mode=requested_display_mode;
            pulse_frame_sync(frame_id,1);
            for(row=0;row<H;row=row+1) begin
                @(negedge clk);lcd_hsync=1;lcd_de=1;
                for(x=0;x<DW;x=x+1) @(posedge clk);
                @(negedge clk);lcd_de=0;
                repeat(12) @(posedge clk);
                @(negedge clk);lcd_hsync=0;
                repeat(4) @(posedge clk);
                @(negedge clk);lcd_hsync=1;
            end
            repeat(4) @(posedge clk);
            if(source_y!=H || source_x!=0) begin
                errors=errors+1;
                $display("ERROR source count frame=%0d y=%0d x=%0d",frame_id,source_y,source_x);
            end
            if(underflow_seen || frame_sync_error) begin
                errors=errors+1;
                $display("ERROR unexpected diagnostic frame=%0d underflow=%b sync=%b",
                         frame_id,underflow_seen,frame_sync_error);
            end
        end
    endtask

    initial begin
        repeat(5) @(posedge clk);
        rst_n=1;
        send_active_frame(1,0);
        send_active_frame(2,1);

        // 制造FIFO欠数，确认不会弹出无效数据且会锁存诊断。
        ddr_available=0;
        pulse_frame_sync(3,0);
        @(negedge clk);lcd_de=1;
        repeat(3) @(posedge clk);
        if(!underflow_seen || ddr_request) begin
            errors=errors+1;
            $display("ERROR underflow diagnostic missing");
        end
        @(negedge clk);lcd_de=0;

        // 异步复位清零后，重新运行一个完整帧。
        #2 rst_n=0;
        #1;
        if(out_valid || pixel!==0 || rgb!==0 || underflow_seen || frame_sync_error)
            errors=errors+1;
        repeat(5) @(posedge clk);
        @(negedge clk);rst_n=1;ddr_available=1;request_allowed=0;
        send_active_frame(4,0);

        if(checked_frames!=3 || checked_pixels!=3*DW*H) begin
            errors=errors+1;
            $display("ERROR totals frames=%0d pixels=%0d",checked_frames,checked_pixels);
        end

        if(errors==0)
            $display("TEST PASSED: full_hd_display, pixels=%0d",checked_pixels);
        else
            $display("TEST FAILED: full_hd_display, %0d error(s)",errors);
        $finish;
    end

    initial begin
        #200000000;
        errors=errors+1;
        $display("TEST FAILED: full_hd_display timeout");
        $finish;
    end
endmodule




