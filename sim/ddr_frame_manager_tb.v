`timescale 1ns / 1ps

module ddr_frame_manager_tb;
    reg clk=0;
    reg rst=1;
    reg [1:0] requested_mode=0;
    reg [1:0] replay_offset=0;
    reg source_boundary=0;
    reg write_done=0;
    reg read_boundary=0;
    wire capture_enable;
    wire [1:0] write_index,read_index,active_mode;
    wire [2:0] history_count;
    integer errors=0;
    integer i;

    always #5 clk=~clk;
    ddr_frame_manager dut(
        .clk(clk),.rst(rst),.requested_mode_async(requested_mode),
        .replay_offset_async(replay_offset),
        .source_frame_boundary(source_boundary),.write_frame_done(write_done),
        .read_frame_boundary(read_boundary),.capture_enable(capture_enable),
        .write_index(write_index),.read_index(read_index),
        .active_mode(active_mode),.history_valid_count(history_count)
    );

    task pulse_write_and_read;
        begin
            @(negedge clk); write_done=1; read_boundary=1;
            @(negedge clk); write_done=0; read_boundary=0; #1;
        end
    endtask
    task pulse_read;
        begin @(negedge clk); read_boundary=1; @(negedge clk); read_boundary=0; #1; end
    endtask
    task pulse_source;
        begin @(negedge clk); source_boundary=1; @(negedge clk); source_boundary=0; #1; end
    endtask
    task check_read;
        input [1:0] expected;
        begin
            if(read_index!==expected) begin
                $display("ERROR read_index=%0d expected=%0d",read_index,expected);
                errors=errors+1;
            end
        end
    endtask

    initial begin
        repeat(3) @(posedge clk); @(negedge clk); rst=0;
        // 正常实时运行，建立4帧历史0、1、2、3。
        for(i=0;i<4;i=i+1) pulse_write_and_read();
        if(history_count!==4 || !capture_enable) begin
            $display("ERROR live history"); errors=errors+1;
        end

        // 请求回放，等待下一完整帧0写完后停止采集。
        requested_mode=2;
        repeat(3) @(posedge clk);
        pulse_write_and_read();
        if(capture_enable || active_mode!==2) begin
            $display("ERROR enter replay"); errors=errors+1;
        end

        replay_offset=0; repeat(3) @(posedge clk); pulse_read(); check_read(0);
        replay_offset=1; repeat(3) @(posedge clk); pulse_read(); check_read(3);
        replay_offset=2; repeat(3) @(posedge clk); pulse_read(); check_read(2);
        replay_offset=3; repeat(3) @(posedge clk); pulse_read(); check_read(1);

        // 回放中请求冻结，应保持当前显示帧。
        requested_mode=1; repeat(3) @(posedge clk); pulse_read();
        if(active_mode!==1) begin $display("ERROR replay to freeze"); errors=errors+1; end
        check_read(1);

        // 返回实时模式只在摄像头帧边界恢复采集。
        requested_mode=0; repeat(3) @(posedge clk);
        if(capture_enable) begin $display("ERROR early resume"); errors=errors+1; end
        pulse_source();
        if(!capture_enable || active_mode!==0) begin
            $display("ERROR live resume"); errors=errors+1;
        end

        if(errors==0) $display("TEST PASSED: ddr_frame_manager");
        else $display("TEST FAILED: ddr_frame_manager, %0d error(s)",errors);
        $finish;
    end
endmodule
