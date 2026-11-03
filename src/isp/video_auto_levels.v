`timescale 1ns/1ps

// RGB白平衡、整帧亮度统计与慢速曝光反馈；灰度世界法不保证单色场景色彩准确。
module video_auto_levels #(
    parameter integer FRAME_PIXELS = 960*1080, // 完整源图像像素数，正式实例设为1920*1080
    parameter [9:0] INITIAL_RED_GAIN = 10'd256, // 红通道启动增益，256为1倍
    parameter [9:0] INITIAL_BLUE_GAIN = 10'd256,// 蓝通道启动增益
    parameter [7:0] WB_MIN_CHANNEL = 8'd4,     // 接纳较弱R/B，但排除接近零的样本
    parameter [7:0] WB_MAX_CHANNEL = 8'd250,   // 排除原始饱和通道
    parameter integer UPDATE_FRAMES = 8,      // 曝光调节间隔，给传感器和DDR留出反馈时间
    parameter integer MIN_WB_SAMPLES = 256,   // 白平衡最少有效样本
    parameter integer LUMA_LOW = 80,          // 目标亮度下界，非赛题规定值
    parameter integer LUMA_HIGH = 112,        // 目标亮度上界
    parameter [15:0] EXP_MAX = 16'd1108,      // SC2210当前帧长1112减4
    parameter [15:0] EXP_MIN = 16'd64,        // 应用曝光下限，单位：行
    parameter [15:0] EXP_STEP = 16'd64,       // 每次曝光调节步长
    parameter [6:0] GAIN_MAX = 7'd96         // 模拟增益索引上限96，对应3倍
)(
    input wire clk, rst_n,                   // 像素时钟，低电平异步复位
    input wire auto_enable,                 // 实时模式允许更新，冻结/回放时关闭
    input wire [7:0] in_red, in_green, in_blue, // 去马赛克后的RGB888
    input wire in_valid, in_hsync, in_vsync,  // 像素有效；行同步原样传递，场同步低有效
    input wire ae_ack_toggle,                // I2C域完成请求的翻转应答
    output reg [7:0] out_red, out_green, out_blue, // 饱和到0~255的白平衡结果
    output reg out_valid, out_hsync, out_vsync, // 与RGB一致延迟两级寄存器
    output reg [9:0] red_gain, blue_gain,     // Q8增益，256为1倍，范围128~768
    output reg [15:0] exposure_lines,        // 邮箱曝光值：应答前保持不变
    output reg [6:0] analog_gain_index,      // 0~63为1~1.984倍，64~96为2~3倍
    output reg ae_request_toggle,           // 邮箱请求，每个新命令翻转一次
    output reg frame_ok                     // 最近一帧像素数量正确，高有效
);
    reg [17:0] product_r, product_b;         // 8位像素乘10位Q8增益
    reg [7:0] green_d, luma_d, luma_q;       // 绿色和原始亮度对齐寄存器
    reg valid_d, hsync_d, vsync_d;           // 第一级控制寄存器
    reg eligible_d, eligible_q;             // 排除过暗或原始饱和像素
    reg previous_vsync, frame_enabled;      // 场沿检测及整帧统计许可
    reg [1:0] ack_sync;                     // 翻转应答两级同步
    reg [31:0] sum_luma, sum_r, sum_g, sum_b; // 完整帧累加值
    reg [20:0] pixel_count, sample_count;    // 总像素及白平衡样本数量
    reg [7:0] update_count;                 // 曝光反馈间隔计数
    wire frame_start = previous_vsync && !out_vsync;
    wire mailbox_idle = ack_sync[1] == ae_request_toggle;
    wire [18:0] rounded_r = {1'b0,product_r} + 19'd128;
    wire [18:0] rounded_b = {1'b0,product_b} + 19'd128;
    wire [9:0] raw_luma = {2'b0,in_red} + {1'b0,in_green,1'b0} + {2'b0,in_blue};
    wire [16:0] increased_exposure = {1'b0,exposure_lines}+{1'b0,EXP_STEP};
    wire [7:0] increased_gain = {1'b0,analog_gain_index}+8'd4;

    // 数据每拍推进，不因消隐停顿而改变同步延迟；定点结果四舍五入并限幅。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_r<=0; product_b<=0; green_d<=0; luma_d<=0; luma_q<=0;
            valid_d<=0; hsync_d<=0; vsync_d<=1; eligible_d<=0; eligible_q<=0;
            out_red<=0; out_green<=0; out_blue<=0;
            out_valid<=0; out_hsync<=0; out_vsync<=1;
        end else begin
            product_r <= in_red * red_gain;
            product_b <= in_blue * blue_gain;
            green_d <= in_green;
            luma_d <= raw_luma[9:2];
            valid_d<=in_valid; hsync_d<=in_hsync; vsync_d<=in_vsync;
            eligible_d <= (in_red>=WB_MIN_CHANNEL && in_red<=WB_MAX_CHANNEL && in_green>=32 &&
                           in_green<=224 && in_blue>=WB_MIN_CHANNEL && in_blue<=WB_MAX_CHANNEL);
            out_red <= !valid_d ? 8'd0 : ((rounded_r>>8)>255 ? 8'd255 : rounded_r[15:8]);
            out_blue <= !valid_d ? 8'd0 : ((rounded_b>>8)>255 ? 8'd255 : rounded_b[15:8]);
            out_green <= valid_d ? green_d : 8'd0;
            out_valid<=valid_d; out_hsync<=hsync_d; out_vsync<=vsync_d;
            luma_q<=luma_d; eligible_q<=eligible_d;
        end
    end

    // 帧边界更新增益；有效帧且整帧处于实时模式时才参与反馈。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            red_gain<=INITIAL_RED_GAIN; blue_gain<=INITIAL_BLUE_GAIN; exposure_lines<=EXP_MAX;
            analog_gain_index<=0; ae_request_toggle<=0; ack_sync<=0;
            sum_luma<=0; sum_r<=0; sum_g<=0; sum_b<=0;
            pixel_count<=0; sample_count<=0; previous_vsync<=1;
            frame_enabled<=0; update_count<=0; frame_ok<=0;
        end else begin
            ack_sync <= {ack_sync[0],ae_ack_toggle};
            previous_vsync <= out_vsync;
            if (!auto_enable) frame_enabled<=0;
            if (frame_start) begin
                frame_ok <= (pixel_count == FRAME_PIXELS);
                if (pixel_count == FRAME_PIXELS && frame_enabled && auto_enable) begin
                    // 用校正后R/B均值追随G；±约3%死区避免反复跳变。
                    if (sample_count >= MIN_WB_SAMPLES && sum_g != 0) begin
                        if (sum_r < sum_g-(sum_g>>5) && red_gain<10'd768) red_gain<=red_gain+10'd4;
                        else if (sum_r > sum_g+(sum_g>>5) && red_gain>10'd128) red_gain<=red_gain-10'd4;
                        if (sum_b < sum_g-(sum_g>>5) && blue_gain<10'd768) blue_gain<=blue_gain+10'd4;
                        else if (sum_b > sum_g+(sum_g>>5) && blue_gain>10'd128) blue_gain<=blue_gain-10'd4;
                    end
                    if (update_count == UPDATE_FRAMES-1 && mailbox_idle) begin
                        update_count<=0;
                        if (sum_luma < FRAME_PIXELS*LUMA_LOW) begin
                            if (exposure_lines < EXP_MAX) begin
                                exposure_lines <= (increased_exposure>{1'b0,EXP_MAX}) ? EXP_MAX : increased_exposure[15:0];
                                ae_request_toggle<=~ae_request_toggle;
                            end else if (analog_gain_index < GAIN_MAX) begin
                                analog_gain_index <= (increased_gain>{1'b0,GAIN_MAX}) ? GAIN_MAX : increased_gain[6:0];
                                ae_request_toggle<=~ae_request_toggle;
                            end
                        end else if (sum_luma > FRAME_PIXELS*LUMA_HIGH) begin
                            if (analog_gain_index != 0) begin
                                analog_gain_index <= (analog_gain_index<7'd4) ? 7'd0 : analog_gain_index-7'd4;
                                ae_request_toggle<=~ae_request_toggle;
                            end else if (exposure_lines > EXP_MIN) begin
                                exposure_lines <= (exposure_lines<EXP_MIN+EXP_STEP) ? EXP_MIN : exposure_lines-EXP_STEP;
                                ae_request_toggle<=~ae_request_toggle;
                            end
                        end
                    end else if (update_count < UPDATE_FRAMES-1) update_count<=update_count+1'b1;
                end else update_count<=0;
                sum_luma<=0; sum_r<=0; sum_g<=0; sum_b<=0;
                pixel_count<=0; sample_count<=0; frame_enabled<=auto_enable;
            end else if (out_valid) begin
                // 数量饱和防止异常视频流绕回成“完整帧”。
                if (pixel_count<FRAME_PIXELS+1) pixel_count<=pixel_count+1'b1;
                if (pixel_count<FRAME_PIXELS) begin
                    sum_luma<=sum_luma+luma_q;
                    if (eligible_q) begin
                        sum_r<=sum_r+out_red; sum_g<=sum_g+out_green; sum_b<=sum_b+out_blue;
                        sample_count<=sample_count+1'b1;
                    end
                end
            end
        end
    end
endmodule
