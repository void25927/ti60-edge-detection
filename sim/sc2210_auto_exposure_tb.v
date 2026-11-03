`timescale 1ns/1ps
// 从引脚解码真实I2C位序，验证8条group hold写入及NACK重试。
module sc2210_auto_exposure_tb;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, init_done=0, frame=0, request=0, nack=0;
    reg [15:0] exposure=16'h0454;
    reg [6:0] gain=0;
    wire scl,sda_out,oe,owned,ack,fault,done;
    reg slave_low=0, active=0;
    wire sda = !(oe || slave_low);
    integer bits=0, byte_number=0, words=0, errors=0, checks=0, i;
    reg [31:0] word_data=0;
    reg [31:0] recorded[0:63];
    sc2210_auto_exposure #(.CLK_HZ(1000000),.I2C_HZ(100000),.GUARD_CYCLES(10)) dut(
        .clk(clk),.rst_n(rst_n),.init_done(init_done),.sensor_vsync(frame),
        .request_toggle(request),.exposure_lines(exposure),.gain_index(gain),.sda_in(sda),
        .scl(scl),.sda_out(sda_out),.sda_oe(oe),.bus_owned(owned),.ack_toggle(ack),
        .fault(fault),.update_done(done));
    always @(negedge sda) if (scl && rst_n) begin active=1;bits=0;byte_number=0;word_data=0; end
    always @(posedge sda) if (scl && rst_n) active=0;
    always @(posedge scl) if(active) begin
        if(bits<8) begin word_data={word_data[30:0],sda}; bits=bits+1; end
        else bits=9;
    end
    always @(negedge scl) if(active) begin
        if(bits==8) slave_low=!nack;
        else if(bits==9) begin
            slave_low=0;bits=0;
            if(byte_number==3) begin recorded[words]=word_data;words=words+1; end
            byte_number=byte_number+1;
        end
    end
    task frame_pulse;
        begin frame=0;repeat(10) @(negedge clk);frame=1;repeat(10) @(negedge clk);frame=0; end
    endtask
    task expect_word;
        input integer number;
        input [31:0] value;
        begin checks=checks+1; if(recorded[number]!==value) begin
            errors=errors+1;$display("ERROR: word %0d got %h expected %h",number,recorded[number],value);end end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        request=1; repeat(30) @(negedge clk);
        if(owned || words) errors=errors+1;
        init_done=1;repeat(20) @(negedge clk); frame_pulse;
        wait(ack==1); repeat(5) @(negedge clk);
        expect_word(0,32'h60380000);expect_word(1,32'h603e0000);
        expect_word(2,32'h603e0145);expect_word(3,32'h603e0240);
        expect_word(4,32'h603e0803);expect_word(5,32'h603e0940);
        expect_word(6,32'h60380010);expect_word(7,32'h60380040);
        exposure=16'h0341;gain=7'd96;request=0;
        repeat(10) @(negedge clk);frame_pulse;wait(ack==0);
        expect_word(10,32'h603e0134);expect_word(11,32'h603e0210);
        expect_word(12,32'h603e0807);expect_word(13,32'h603e0960);
        // 无应答时不确认邮箱，最多重试三组并锁定故障。
        nack=1;request=1;
        for(i=0;i<4;i=i+1) begin frame_pulse;repeat(500) @(negedge clk); end
        checks=checks+1;
        if(!fault || ack!=0 || words!=16) begin errors=errors+1;$display("ERROR: NACK fault/ack");end
        rst_n=0;#1;checks=checks+1;if(fault || owned || oe || !scl) errors=errors+1;
        slave_low=0;active=0;request=0;frame=0;nack=0;
        repeat(3) @(negedge clk);rst_n=1;repeat(20) @(negedge clk);
        exposure=16'h0454;gain=0;request=1;repeat(10) @(negedge clk);frame_pulse;wait(ack==1);
        checks=checks+1;if(words!=24 || fault) errors=errors+1;
        if(errors==0) $display("TEST PASSED: sc2210_auto_exposure, %0d checks",checks);
        else $display("TEST FAILED: sc2210_auto_exposure, %0d error(s)",errors);
        $finish;
    end
    initial begin #2000000; errors=errors+1;$display("TEST FAILED: sc2210_auto_exposure timeout, words=%0d",words);$finish;end
endmodule
