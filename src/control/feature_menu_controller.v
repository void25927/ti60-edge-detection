`timescale 1ns/1ps
// MODERN_MENU只选择显示优先的菜单顺序；显示切换统一使用确认键短按。
// 默认参数兼容旧菜单。短按在释放时触发，长按仅触发一次。
module feature_menu_controller #(
    parameter REPLAY_HOLD_FRAMES=15, INSPECTION_MENU=0, HISTORY_FRAMES=4, MODERN_MENU=0,
    parameter OFFSET_BITS=(HISTORY_FRAMES<=2)?1:$clog2(HISTORY_FRAMES),
    parameter COUNT_BITS=$clog2(HISTORY_FRAMES+1)
)(
    input wire clk, rst_n, frame_start,
    input wire function_press, confirm_press, function_long_press, confirm_long_press,
    input wire [COUNT_BITS-1:0] history_count, // 已同步且完整提交的历史帧数量
    input wire snapshot_busy, snapshot_done, snapshot_error,
    output reg [2:0] menu_index, // 0中值，1阈值，2回放，3Canny，4显示，5轮廓
    output reg median_enable, canny_enable, display_mode,
    output wire threshold_enable,
    output wire threshold_add, threshold_sub,
    output wire [1:0] ddr_mode, // 0实时，1冻结，2回放
    output reg [OFFSET_BITS-1:0] replay_offset,
    output reg replay_active, replay_paused,
    output reg snapshot_request, snapshot_cancel,
    output wire saving
);
    localparam CW=(REPLAY_HOLD_FRAMES<=1)?1:$clog2(REPLAY_HOLD_FRAMES);
    reg [CW-1:0] hold_count;
    reg save_pending;
    wire [OFFSET_BITS-1:0] oldest=(history_count>=HISTORY_FRAMES)?HISTORY_FRAMES-1:
                              (history_count==0)?0:history_count-1'b1;
    assign threshold_enable=(menu_index==1);
    assign threshold_add=threshold_enable && confirm_press && !confirm_long_press && !function_press;
    assign threshold_sub=threshold_enable && confirm_long_press && !confirm_press && !function_press;
    assign saving=save_pending || snapshot_busy;
    assign ddr_mode=!replay_active ? 2'd0 : (replay_paused || saving) ? 2'd1 : 2'd2;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            menu_index<=MODERN_MENU?4:0;median_enable<=1;canny_enable<=1;display_mode<=0;
            replay_active<=0;replay_paused<=0;replay_offset<=0;hold_count<=0;
            save_pending<=0;snapshot_request<=0;snapshot_cancel<=0;
        end else begin
            snapshot_request<=0;snapshot_cancel<=0;
            if(snapshot_done || snapshot_error)save_pending<=0;
            // 切换功能优先，禁止同拍事件改变旧菜单状态。
            if(function_press)begin
                if(MODERN_MENU)case(menu_index)
                    4:menu_index<=3;3:menu_index<=0;0:menu_index<=1;
                    1:menu_index<=2;2:menu_index<=INSPECTION_MENU?5:4;default:menu_index<=4;
                endcase
                else menu_index<=(menu_index==(INSPECTION_MENU?5:4))?0:menu_index+1'b1;
                replay_active<=0;replay_paused<=0;hold_count<=0;
                snapshot_cancel<=save_pending || snapshot_busy;
                save_pending<=0;
            end else begin
                if(confirm_press)begin
                    case(menu_index)
                        0:median_enable<=~median_enable;
                        3:canny_enable<=~canny_enable;
                        4:display_mode<=~display_mode;
                        default:begin end
                    endcase
                end
                // 回放菜单的功能键长按启动回放，不切换菜单。
                if(menu_index==2 && function_long_press && !replay_active &&
                   history_count!=0 && !saving)begin
                    replay_active<=1;replay_paused<=0;replay_offset<=oldest;hold_count<=0;
                end
                if(menu_index==2 && replay_active && !saving)begin
                    if(confirm_press && !confirm_long_press)begin
                        replay_paused<=~replay_paused;hold_count<=0;
                    end else if(confirm_long_press && !confirm_press)begin
                        save_pending<=1;snapshot_request<=1;hold_count<=0;
                    end else if(frame_start && !replay_paused)begin
                        if(hold_count==REPLAY_HOLD_FRAMES-1)begin
                            hold_count<=0;
                            replay_offset<=(replay_offset==0)?oldest:replay_offset-1'b1;
                        end else hold_count<=hold_count+1'b1;
                    end
                end
            end
        end
    end
endmodule
