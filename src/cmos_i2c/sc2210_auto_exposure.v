`timescale 1ns/1ps

// 上电配置结束后接管I2C；帧开始时更新曝光/模拟增益，group 0下一帧提交。
module sc2210_auto_exposure #(
    parameter integer CLK_HZ=96000000, // 系统时钟
    parameter integer I2C_HZ=50000,    // I2C速率
    parameter integer GUARD_CYCLES=CLK_HZ/500 // 初始化后等待2ms，保证原控制器STOP完成
)(
    input wire clk, rst_n, init_done, // 系统时钟、低有效复位、原初始化完成
    input wire sensor_vsync,         // MIPI帧有效，高有效，经两级同步检测上升沿
    input wire request_toggle,       // 像素域请求翻转位
    input wire [15:0] exposure_lines, // 握手邮箱，收到应答前不得改变
    input wire [6:0] gain_index,      // 增益索引0~96，对应1~3倍
    input wire sda_in,               // 引脚SDA采样
    output wire scl, sda_out, sda_oe, // 运行时I2C输出
    output reg bus_owned,            // 初始化保护时间结束后接管总线
    output reg ack_toggle,           // 全组写成功后翻转应答
    output reg fault,                // 连续三次NACK后锁定，复位恢复
    output reg update_done           // 完成一次曝光更新的单周期脉冲
);
    localparam IDLE=0, FRAME=1, ISSUE=2, WAIT=3;
    reg [1:0] state, retries;        // 事务状态及整组重试次数
    reg [1:0] request_sync, frame_sync; // 两级同步；多位邮箱在握手期间保持稳定
    reg previous_frame, token;      // 帧沿检测及当前请求编号
    reg [15:0] exposure_latched;    // 锁存曝光值
    reg [6:0] gain_latched;         // 锁存增益索引
    reg [3:0] write_index;          // 8次寄存器写入序号
    reg [31:0] guard_count;         // 原初始化完成后的等待周期
    reg start;                     // I2C启动脉冲
    reg [15:0] addr;               // 当前寄存器地址
    reg [7:0] data;                // 当前寄存器数据
    wire busy, done, error;
    wire frame_start=frame_sync[1] && !previous_frame;
    always @* begin
        addr=16'h3800; data=8'h00;
        case(write_index)
            0: begin addr=16'h3800; data=8'h00; end
            1: begin addr=16'h3e00; data={4'b0,exposure_latched[15:12]}; end
            2: begin addr=16'h3e01; data=exposure_latched[11:4]; end
            3: begin addr=16'h3e02; data={exposure_latched[3:0],4'b0}; end
            4: begin addr=16'h3e08; data=gain_latched[6] ? 8'h07 : 8'h03; end
            5: begin addr=16'h3e09; data={2'b01,gain_latched[5:0]}; end
            6: begin addr=16'h3800; data=8'h10; end
            7: begin addr=16'h3800; data=8'h40; end
            default: begin addr=16'h3800; data=0; end
        endcase
    end
    i2c_register_writer #(.CLK_HZ(CLK_HZ),.I2C_HZ(I2C_HZ)) writer(
        .clk(clk),.rst_n(rst_n),.start(start),.register_addr(addr),.register_data(data),
        .sda_in(sda_in),.scl(scl),.sda_out(sda_out),.sda_oe(sda_oe),
        .busy(busy),.done(done),.error(error));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; retries<=0; request_sync<=0; frame_sync<=0; previous_frame<=0;
            token<=0; exposure_latched<=1108; gain_latched<=0; write_index<=0;
            guard_count<=0; bus_owned<=0; ack_toggle<=0; fault<=0; update_done<=0; start<=0;
        end else begin
            request_sync<={request_sync[0],request_toggle};
            frame_sync<={frame_sync[0],sensor_vsync}; previous_frame<=frame_sync[1];
            start<=0; update_done<=0;
            if (!bus_owned && init_done) begin
                if (guard_count==GUARD_CYCLES-1) bus_owned<=1;
                else guard_count<=guard_count+1'b1;
            end
            if (bus_owned && !fault) case(state)
                IDLE: if (request_sync[1]!=ack_toggle) begin
                    exposure_latched<=exposure_lines; gain_latched<=gain_index;
                    token<=request_sync[1]; retries<=0; write_index<=0; state<=FRAME;
                end
                FRAME: if (frame_start) state<=ISSUE;
                ISSUE: if (!busy) begin start<=1; state<=WAIT; end
                WAIT: if (done) begin
                    if (error) begin
                        if (retries==2) begin fault<=1; state<=IDLE; end
                        else begin retries<=retries+1'b1; write_index<=0; state<=FRAME; end
                    end else if (write_index==7) begin
                        ack_toggle<=token; update_done<=1; state<=IDLE;
                    end else begin write_index<=write_index+1'b1; state<=ISSUE; end
                end
            endcase
        end
    end
endmodule
