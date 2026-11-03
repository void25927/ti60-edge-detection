`timescale 1ns/1ps
// 扩展按键调阈值；绿灯为时钟心跳，红灯锁存系统故障，复位清除。
module exboard_control #(
    parameter CLK_FREQ_HZ=148800000,
    parameter DEBOUNCE_MS=20,
    parameter RUN_HALF_PERIOD=CLK_FREQ_HZ/2,
    parameter ALARM_HALF_PERIOD=CLK_FREQ_HZ/4
)(
    input wire clk,input wire async_rst_n,
    input wire key_up_n,input wire key_down_n,
    input wire fault_level, // 持续故障电平；短脉冲须先由源域锁存
    output wire add_pulse,output wire sub_pulse,
    output reg led_run,output reg led_alarm,output reg alarm_active
);
    (* ASYNC_REG="TRUE" *) reg [2:0] reset_pipe;
    always @(posedge clk or negedge async_rst_n)begin
        if(!async_rst_n)reset_pipe<=0;else reset_pipe<={reset_pipe[1:0],1'b1};
    end
    wire rst_n=reset_pipe[2];
    wire [1:0] pressed,press;
    key_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DELAY_MS(DEBOUNCE_MS)) keys(
        clk,rst_n,{key_up_n,key_down_n},,pressed,press);
    // 同时按下不改变阈值；按键释放不产生调节事件。
    assign add_pulse=press[1] && !pressed[0];
    assign sub_pulse=press[0] && !pressed[1];
    (* ASYNC_REG="TRUE" *) reg fault_meta,fault_sync;
    localparam RW=RUN_HALF_PERIOD<=1 ? 1 : $clog2(RUN_HALF_PERIOD);
    localparam AW=ALARM_HALF_PERIOD<=1 ? 1 : $clog2(ALARM_HALF_PERIOD);
    reg [RW-1:0] run_count;
    reg [AW-1:0] alarm_count;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            fault_meta<=0;fault_sync<=0;alarm_active<=0;
            run_count<=0;alarm_count<=0;led_run<=0;led_alarm<=0;
        end else begin
            fault_meta<=fault_level;fault_sync<=fault_meta;
            if(fault_sync)alarm_active<=1;
            if(run_count==RUN_HALF_PERIOD-1)begin run_count<=0;led_run<=!led_run;end
            else run_count<=run_count+1'b1;
            if(!alarm_active)begin alarm_count<=0;led_alarm<=0;end
            else if(alarm_count==ALARM_HALF_PERIOD-1)begin alarm_count<=0;led_alarm<=!led_alarm;end
            else alarm_count<=alarm_count+1'b1;
        end
    end
endmodule
