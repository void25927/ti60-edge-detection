`timescale 1ns/1ps
// 各按键独立同步、消抖；电平变化产生flag，按下另给单拍脉冲。
module key_debounce #(
    parameter KEY_WIDTH=2,
    parameter CLK_FREQ_HZ=100_000_000,
    parameter DELAY_MS=20
)(
    input wire clk,input wire rst_n,
    input wire [KEY_WIDTH-1:0] key_data, // 低电平按下
    output wire key_flag,
    output reg [KEY_WIDTH-1:0] key_value,
    output reg [KEY_WIDTH-1:0] key_press // 仅按下，不含释放
);
    localparam integer LIMIT_RAW=(CLK_FREQ_HZ/1000)*DELAY_MS;
    localparam integer LIMIT=LIMIT_RAW<1 ? 1 : LIMIT_RAW;
    localparam integer BITS=LIMIT<=1 ? 1 : $clog2(LIMIT);
    (* ASYNC_REG="TRUE" *) reg [KEY_WIDTH-1:0] meta,sync_data;
    reg [KEY_WIDTH-1:0] changed;
    assign key_flag=|changed;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin meta<={KEY_WIDTH{1'b1}};sync_data<={KEY_WIDTH{1'b1}};end
        else begin meta<=key_data;sync_data<=meta;end
    end
    genvar k;
    generate for(k=0;k<KEY_WIDTH;k=k+1)begin: keys
        reg [BITS-1:0] count; // 只需计到LIMIT-1
        always @(posedge clk or negedge rst_n)begin
            if(!rst_n)begin count<=0;key_value[k]<=0;changed[k]<=0;key_press[k]<=0;end
            else begin
                changed[k]<=0;key_press[k]<=0;
                if(!sync_data[k]==key_value[k])count<=0;
                else if(count==LIMIT-1)begin
                    count<=0;key_value[k]<=!sync_data[k];
                    changed[k]<=1;key_press[k]<=!sync_data[k];
                end else count<=count+1'b1;
            end
        end
    end endgenerate
endmodule
