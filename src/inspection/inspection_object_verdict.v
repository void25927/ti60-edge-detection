`timescale 1ns/1ps
// 单件累计判定：一次有效PASS即锁定通过；中央区退出后结束本件判定。
// 0=不确定，1=通过，2=未通过，3=待确认。不是单帧轮廓评分的替代品。
module inspection_object_verdict #(
    parameter IMAGE_WIDTH=1920, IMAGE_HEIGHT=1080, EXIT_MARGIN=32
)(
    input wire clk,rst_n,clear,enabled,
    input wire observation_valid,identity_valid,
    input wire [31:0] frame_id,
    input wire [15:0] track_id,
    input wire [10:0] center_x,center_y,
    input wire [1:0] raw_status,
    output reg [1:0] verdict
);
    localparam X0=IMAGE_WIDTH/4, X1=IMAGE_WIDTH*3/4-1;
    localparam Y0=IMAGE_HEIGHT/4,Y1=IMAGE_HEIGHT*3/4-1;
    reg active,accepted,entered,closed;
    reg [15:0] saved_track;
    reg [31:0] saved_frame;
    reg [1:0] outside_count,last_verdict;
    wire usable=identity_valid && track_id!=0 && (raw_status==1 || raw_status==2);
    wire repeated=active && track_id==saved_track && frame_id==saved_frame;
    // 帧号跳变或身份切换不继承前件通过。32位自然回绕仍连续。
    wire continuing=active && track_id==saved_track && frame_id==saved_frame+32'd1;
    wire in_center=center_x>=X0 && center_x<=X1 && center_y>=Y0 && center_y<=Y1;
    wire outside=center_x+EXIT_MARGIN<X0 || center_x>X1+EXIT_MARGIN ||
                 center_y+EXIT_MARGIN<Y0 || center_y>Y1+EXIT_MARGIN;
    wire was_closed=continuing && closed;
    wire passed=(continuing && accepted) || (!was_closed && raw_status==1);
    wire seen_center=(continuing && entered) || in_center;
    wire exit_now=continuing && entered && outside && outside_count==2;
    always @(*)begin
        verdict=0;
        if(enabled && !clear && usable)begin
            if(repeated)verdict=last_verdict;
            else if(passed)verdict=1;
            else if(was_closed || exit_now)verdict=2;
            else verdict=3;
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            active<=0;accepted<=0;entered<=0;closed<=0;saved_track<=0;saved_frame<=0;
            outside_count<=0;last_verdict<=0;
        end else if(clear || !enabled)begin
            active<=0;accepted<=0;entered<=0;closed<=0;outside_count<=0;last_verdict<=0;
        end else if(observation_valid)begin
            if(!usable)begin
                active<=0;accepted<=0;entered<=0;closed<=0;outside_count<=0;last_verdict<=0;
            end else if(!repeated)begin
                active<=1;saved_frame<=frame_id;saved_track<=track_id;
                accepted<=passed;entered<=seen_center;closed<=was_closed || exit_now;
                if(continuing && entered && outside)begin
                    if(outside_count<3)outside_count<=outside_count+1'b1;
                end else outside_count<=0;
                last_verdict<=verdict;
            end
        end
    end
endmodule
