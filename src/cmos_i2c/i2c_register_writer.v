`timescale 1ns/1ps

// 16位寄存器地址、8位数据的I2C写主机；逐字节检查ACK，SDA只拉低或释放。
module i2c_register_writer #(
    parameter integer CLK_HZ = 96000000, // 系统时钟
    parameter integer I2C_HZ = 50000     // SC2210控制总线速率
)(
    input wire clk, rst_n,              // 系统时钟、低有效复位
    input wire start,                   // 空闲时接收单拍请求
    input wire [15:0] register_addr,    // 待写寄存器地址
    input wire [7:0] register_data,     // 待写数据
    input wire sda_in,                  // SDA引脚采样，ACK为低
    output reg scl,                     // SCL输出，不支持从机时钟拉伸
    output wire sda_out,                // 恒为0，配合使能实现开漏输出
    output reg sda_oe,                  // 1拉低SDA，0释放SDA
    output reg busy, done, error        // 事务进行中、完成脉冲、NACK标志
);
    localparam integer QUARTER = CLK_HZ/(I2C_HZ*4);
    localparam IDLE=0, START=1, SEND=2, ACK=3, STOP=4;
    reg [2:0] state;                    // 总线状态
    reg [1:0] phase, byte_index;        // 四分之一周期和当前字节
    reg [2:0] bit_index;                // MSB优先的位编号
    reg [31:0] shift_data;              // 0x60写地址、寄存器高低字节、数据
    reg [31:0] divider;                 // 分频计数，状态切换时重新计时
    reg [1:0] sda_sync;                 // SDA两级同步，采样前留半个SCL高周期
    assign sda_out=1'b0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; phase<=0; byte_index<=0; bit_index<=7;
            shift_data<=0; divider<=0; scl<=1; sda_oe<=0;
            busy<=0; done<=0; error<=0; sda_sync<=3;
        end else begin
            sda_sync<={sda_sync[0],sda_in}; done<=0;
            if (state==IDLE) begin
                scl<=1; sda_oe<=0; divider<=0; phase<=0;
                if (start) begin
                    shift_data<={8'h60,register_addr,register_data};
                    byte_index<=0; bit_index<=7; error<=0; busy<=1; state<=START;
                end
            end else if (divider==QUARTER-1) begin
                divider<=0; phase<=phase+1'b1;
                case(state)
                    START: begin
                        if (phase==1) sda_oe<=1;
                        if (phase==2) scl<=0;
                        if (phase==3) state<=SEND;
                    end
                    SEND: begin
                        if (phase==0) sda_oe<=!shift_data[31];
                        if (phase==1) scl<=1;
                        if (phase==3) begin
                            scl<=0; shift_data<={shift_data[30:0],1'b0};
                            if (bit_index==0) state<=ACK;
                            else bit_index<=bit_index-1'b1;
                        end
                    end
                    ACK: begin
                        if (phase==0) sda_oe<=0;
                        if (phase==1) scl<=1;
                        if (phase==2 && sda_sync[1]) error<=1;
                        if (phase==3) begin
                            scl<=0;
                            if (error || byte_index==3) state<=STOP;
                            else begin byte_index<=byte_index+1'b1; bit_index<=7; state<=SEND; end
                        end
                    end
                    STOP: begin
                        if (phase==0) begin scl<=0; sda_oe<=1; end
                        if (phase==1) scl<=1;
                        if (phase==2) sda_oe<=0;
                        if (phase==3) begin state<=IDLE; busy<=0; done<=1; end
                    end
                    default: begin state<=IDLE; busy<=0; error<=1; end
                endcase
            end else divider<=divider+1'b1;
        end
    end
endmodule
