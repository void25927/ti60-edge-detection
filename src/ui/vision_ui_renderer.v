`timescale 1ns/1ps
`include "ui_assets.vh"
// 1920x1080 streaming OSD. Two synchronous ROM reads + one output register.
// The camera stream is never rescaled. Header/footer replace pixels; status text
// replaces only glyph/outline pixels and is otherwise completely transparent.
module vision_ui_renderer #(
    parameter WIDTH=1920, HEIGHT=1080,
    parameter VSYNC_ACTIVE_LEVEL=1'b0,
    parameter FONT_FILE="src/ui/ui_font16.mem",
    parameter STRING_FILE="src/ui/ui_strings.mem"
)(
    input wire clk,rst_n,
    input wire [23:0] in_rgb,
    input wire in_de,in_hsync,in_vsync,
    input wire [2:0] menu,
    input wire median_enable,canny_enable,replay_active,replay_paused,saving,
    input wire [15:0] threshold_bcd,
    input wire [23:0] fps_text,
    input wire background_ready,template_valid,learning,enabled,matched,fault,
    input wire ddr_error,video_error,
    input wire [1:0] result_status,
    input wire [2:0] object_count,
    input wire [31:0] frame_id,detection_id,
    input wire [7:0] diagnostic,
    output reg [23:0] out_rgb,
    output reg out_de,out_hsync,out_vsync
);
    localparam [23:0] NAVY=24'h08243c,WHITE=24'hf2f7fc,CYAN=24'h30d6ed,
                      GREEN=24'h65ef88,RED=24'hff6666,AMBER=24'hffcf66;
    localparam FOOTER_TOP=HEIGHT-152;
    reg [10:0] x,y;
    reg de_d,vs_d;
    wire frame_start=(in_vsync==VSYNC_ACTIVE_LEVEL)&&(vs_d!=VSYNC_ACTIVE_LEVEL);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin x<=0;y<=0;de_d<=0;vs_d<=VSYNC_ACTIVE_LEVEL;end
        else begin
            de_d<=in_de;vs_d<=in_vsync;
            if(in_vsync==VSYNC_ACTIVE_LEVEL)begin x<=0;y<=0;end
            else begin
                if(in_de)x<=(x==WIDTH-1)?0:x+1'b1;else x<=0;
                if(de_d&&!in_de)y<=(y==HEIGHT-1)?0:y+1'b1;
            end
        end
    end
    reg [2:0] menu_q;
    reg med_q,can_q,replay_q,pause_q,save_q;
    reg [5:0] inspect_string,result_string;
    reg [23:0] result_color;
    reg [7:0] diagnostic_q;
    // Algorithm configuration is stable for an entire display frame. Result
    // history is selected at the first DE; sample it at row 80, before status.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            menu_q<=4;med_q<=1;can_q<=1;replay_q<=0;pause_q<=0;save_q<=0;diagnostic_q<=0;
            inspect_string<=`UI_S_IDLE;result_string<=`UI_S_UNKNOWN;result_color<=AMBER;
        end else begin
            if(frame_start)begin
                diagnostic_q<=0;
                menu_q<=menu;med_q<=median_enable;can_q<=canny_enable;
                replay_q<=replay_active;pause_q<=replay_paused;save_q<=saving;
            end
            if(in_de && x==0 && y==80)begin
                diagnostic_q<=diagnostic;
                inspect_string<=learning?`UI_S_LEARNING:enabled?`UI_S_INSPECTING:
                                template_valid?`UI_S_TEMPLATE_READY:`UI_S_IDLE;
                result_color<=AMBER;
                if(video_error)begin result_string<=`UI_S_VIDEO_FAULT;result_color<=RED;end
                else if(ddr_error)begin result_string<=`UI_S_DDR_FAULT;result_color<=RED;end
                else if(fault || diagnostic!=0)begin result_string<=`UI_S_FAULT;result_color<=RED;end
                else if(!background_ready)result_string<=`UI_S_CALIBRATE;
                else if(learning || !template_valid || !enabled)result_string<=`UI_S_UNKNOWN;
                else if(!matched || frame_id!=detection_id)result_string<=`UI_S_WAIT;
                else if(object_count==0)result_string<=`UI_S_UNKNOWN;
                else if(result_status==1)begin result_string<=`UI_S_PASS;result_color<=GREEN;end
                else if(result_status==2)begin result_string<=`UI_S_FAIL;result_color<=RED;end
                else if(result_status==3)result_string<=`UI_S_PENDING;
                else result_string<=`UI_S_WAIT;
            end
        end
    end
    function [5:0] menu_label;
        input [2:0] slot;
        begin case(slot)
            0:menu_label=`UI_S_MENU_DISPLAY;
            1:menu_label=`UI_S_MENU_ALGORITHM;
            2:menu_label=`UI_S_MENU_MEDIAN;
            3:menu_label=`UI_S_MENU_THRESHOLD;
            4:menu_label=`UI_S_MENU_REPLAY;
            default:menu_label=`UI_S_MENU_INSPECT;
        endcase end
    endfunction
    function [2:0] menu_slot;
        input [2:0] index;
        begin case(index)
            4:menu_slot=0;3:menu_slot=1;0:menu_slot=2;
            1:menu_slot=3;2:menu_slot=4;default:menu_slot=5;
        endcase end
    endfunction
    function [5:0] hint;
        input [2:0] index;
        input [1:0] key;
        begin
            hint=0;
            case(key)
                0:hint=(index==2)?`UI_S_EXIT_REPLAY:`UI_S_NEXT_MENU;
                1:case(index)2:hint=`UI_S_START_REPLAY;default:hint=0;endcase
                2:case(index)
                    4:hint=`UI_S_TOGGLE_DISPLAY;3:hint=`UI_S_TOGGLE_ALGORITHM;0:hint=`UI_S_TOGGLE_MEDIAN;
                    1:hint=`UI_S_THRESHOLD_ADD;2:hint=`UI_S_PAUSE_REPLAY;
                    5:hint=`UI_S_TOGGLE_INSPECT;default:hint=0;
                endcase
                3:case(index)1:hint=`UI_S_THRESHOLD_SUB;2:hint=`UI_S_SAVE_REPLAY;
                    5:hint=`UI_S_LEARN_TEMPLATE;default:hint=0;endcase
            endcase
        end
    endfunction
    // Geometry produces a string ROM address and coordinates within its glyph.
    reg [5:0] g_string;
    reg [4:0] g_index;
    reg [3:0] g_row,g_col;
    reg g_text,g_transparent;
    reg [2:0] g_dynamic;
    reg [23:0] g_bg,g_fg;
    reg [10:0] local_x,local_y;
    reg [2:0] slot;
    reg [1:0] key;
    wire [1:0] threshold_skip=(threshold_bcd[15:12]!=0)?0:(threshold_bcd[11:8]!=0)?1:(threshold_bcd[7:4]!=0)?2:3;
    always @(*)begin
        g_string=0;g_index=0;g_row=0;g_col=0;g_text=0;g_dynamic=0;
        g_bg=in_rgb;g_fg=WHITE;g_transparent=0;local_x=0;local_y=0;slot=0;key=0;
        if(y<64)begin
            g_bg=NAVY;
            if(y>=16 && y<48)begin
                if(x>=32 && x<864)begin g_string=`UI_S_TITLE;local_x=x-32;g_text=1;end
                else if(x>=1056 && x<1504)begin g_string=`UI_S_RESOLUTION;local_x=x-1056;g_text=1;end
                else if(x>=1536 && x<1728)begin g_string=`UI_S_FPS;local_x=x-1536;g_text=1;end
                else if(x>=1728 && x<1776)begin local_x=x-1728;g_dynamic=2;g_text=1;g_fg=GREEN;end
                g_row=(y-16)>>1;g_col={1'b0,local_x[3:1]};g_index=local_x>>4;
            end
        end else if(y>=FOOTER_TOP)begin
            g_bg=NAVY;
            if(y==FOOTER_TOP || y==FOOTER_TOP+56)g_bg=24'h306078;
            if(y<FOOTER_TOP+56)begin
                if(x<320)begin slot=0;local_x=x;end
                else if(x<640)begin slot=1;local_x=x-320;end
                else if(x<960)begin slot=2;local_x=x-640;end
                else if(x<1280)begin slot=3;local_x=x-960;end
                else if(x<1600)begin slot=4;local_x=x-1280;end
                else begin slot=5;local_x=x-1600;end
                if(slot==menu_slot(menu_q) && local_x>=12 && local_x<308 &&
                   y>=FOOTER_TOP+4 && y<FOOTER_TOP+52)begin g_bg=CYAN;g_fg=NAVY;end
                if(local_x>=96 && local_x<224 && y>=FOOTER_TOP+12 && y<FOOTER_TOP+44)begin
                    g_string=menu_label(slot);g_text=1;local_x=local_x-96;
                    g_index=local_x>>4;g_col={1'b0,local_x[3:1]};g_row=(y-FOOTER_TOP-12)>>1;
                end
            end else begin
                if(x<480)begin key=0;local_x=x;end
                else if(x<960)begin key=1;local_x=x-480;end
                else if(x<1440)begin key=2;local_x=x-960;end
                else begin key=3;local_x=x-1440;end
                if(local_x==0)g_bg=24'h306078;
                if(local_x>=24 && local_x<456)begin
                    local_x=local_x-24;
                    if(y>=FOOTER_TOP+64 && y<FOOTER_TOP+96 && local_x<160)begin
                        g_string=`UI_S_KEY_FUNCTION_SHORT+key;g_text=1;
                        g_index=local_x>>4;g_col={1'b0,local_x[3:1]};g_row=(y-FOOTER_TOP-64)>>1;
                    end else if(y>=FOOTER_TOP+112 && y<FOOTER_TOP+144)begin
                        g_string=hint(menu_q,key);g_text=(g_string!=0);
                        g_index=local_x>>4;g_col={1'b0,local_x[3:1]};g_row=(y-FOOTER_TOP-112)>>1;
                        g_fg=24'hc3d9e9;
                    end
                end
            end
        end else if(x>=512 && x<560 && y>=296 && y<328 && diagnostic_q!=0)begin
            // 保留新版录入/容量/通路诊断码，不用泛化的“异常”掩盖原因。
            g_transparent=1;g_text=1;g_dynamic=3;g_fg=AMBER;
            local_x=x-512;g_index=local_x>>4;g_col={1'b0,local_x[3:1]};g_row=(y-296)>>1;
        end else if(x>=32 && x<480 && y>=96 && y<336)begin
            g_transparent=1;local_x=x-32;
            if(y<136)begin slot=0;local_y=y-96;end
            else if(y<176)begin slot=1;local_y=y-136;end
            else if(y<216)begin slot=2;local_y=y-176;end
            else if(y<256)begin slot=3;local_y=y-216;end
            else if(y<296)begin slot=4;local_y=y-256;end
            else begin slot=5;local_y=y-296;end
            if(local_y<32)begin
                g_row=local_y>>1;
                if(local_x<160)begin
                    g_string=`UI_S_LABEL_THRESHOLD+slot;g_text=1;
                    g_index=local_x>>4;g_col={1'b0,local_x[3:1]};
                end else if(local_x>=192)begin
                    local_x=local_x-192;g_text=1;g_index=local_x>>4;g_col={1'b0,local_x[3:1]};g_fg=CYAN;
                    case(slot)
                        0:begin g_dynamic=1;g_text=(g_index<(4-threshold_skip));end
                        1:begin g_string=med_q?`UI_S_ON:`UI_S_OFF;g_fg=med_q?GREEN:AMBER;end
                        2:g_string=can_q?`UI_S_CANNY:`UI_S_SOBEL;
                        3:g_string=save_q?`UI_S_SAVING:!replay_q?`UI_S_IDLE:pause_q?`UI_S_PAUSED:`UI_S_PLAYING;
                        4:g_string=inspect_string;
                        5:begin g_string=result_string;g_fg=result_color;end
                    endcase
                end
            end
        end
        if(g_dynamic==0 && local_x>=512)g_text=0;
    end
    // 每16屏幕像素一个布局单元：ASCII占一个，中文占左右两个。
    reg [8:0] strings[0:2047];
    reg [31:0] font[0:4095];
    initial begin $readmemh(STRING_FILE,strings);$readmemh(FONT_FILE,font);end
    reg [8:0] glyph_s1;
    reg [7:0] dynamic_s1;
    reg [2:0] dynamic_kind_s1;
    reg [3:0] row_s1,col_s1,col_s2;
    reg [31:0] font_s2;
    reg [23:0] bg_s1,bg_s2,fg_s1,fg_s2;
    reg text_s1,text_s2,transparent_s1,transparent_s2;
    reg [2:0] controls_s1,controls_s2;
    reg [3:0] digit;
    reg [7:0] ascii;
    always @(*)begin
        digit=0;ascii=8'h20;
        case(g_index+{3'd0,threshold_skip})0:digit=threshold_bcd[15:12];1:digit=threshold_bcd[11:8];
            2:digit=threshold_bcd[7:4];3:digit=threshold_bcd[3:0];default:digit=0;endcase
        case(g_index)0:ascii=fps_text[23:16];1:ascii=fps_text[15:8];2:ascii=fps_text[7:0];default:ascii=8'h20;endcase
    end
    wire [7:0] selected_glyph=(dynamic_kind_s1!=0)?dynamic_s1:glyph_s1[7:0];
    // ROM ports intentionally have no reset, allowing block RAM inference.
    always @(posedge clk)begin
        glyph_s1<=strings[{g_string,g_index}];
        font_s2<=font[{selected_glyph,row_s1}];
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            dynamic_s1<=0;dynamic_kind_s1<=0;row_s1<=0;col_s1<=0;col_s2<=0;
            bg_s1<=0;bg_s2<=0;fg_s1<=0;fg_s2<=0;
            text_s1<=0;text_s2<=0;transparent_s1<=0;transparent_s2<=0;
            controls_s1<={2'b00,VSYNC_ACTIVE_LEVEL};controls_s2<={2'b00,VSYNC_ACTIVE_LEVEL};
            out_rgb<=0;out_de<=0;out_hsync<=0;out_vsync<=VSYNC_ACTIVE_LEVEL;
        end else begin
            dynamic_kind_s1<=g_dynamic;
            if(g_dynamic==1)begin
                dynamic_s1<=`UI_G_DIGIT0+digit;
            end
            else if(g_dynamic==3)begin
                if(g_index==0)dynamic_s1<=8'd16;
                else if(g_index==1)dynamic_s1<=(diagnostic_q[7:4]<10)?`UI_G_DIGIT0+diagnostic_q[7:4]:8'd12+diagnostic_q[7:4]-10;
                else dynamic_s1<=(diagnostic_q[3:0]<10)?`UI_G_DIGIT0+diagnostic_q[3:0]:8'd12+diagnostic_q[3:0]-10;
            end else dynamic_s1<=(ascii==8'h2d)?`UI_G_DASH:(ascii>=8'h30 && ascii<=8'h39)?`UI_G_DIGIT0+ascii-8'h30:8'd0;
            row_s1<=g_row;col_s1<=g_col;col_s2<=(dynamic_kind_s1!=0)?col_s1:{glyph_s1[8],col_s1[2:0]};
            bg_s1<=g_bg;bg_s2<=bg_s1;fg_s1<=g_fg;fg_s2<=fg_s1;
            text_s1<=g_text;text_s2<=text_s1;transparent_s1<=g_transparent;transparent_s2<=transparent_s1;
            controls_s1<={in_de,in_hsync,in_vsync};controls_s2<=controls_s1;
            {out_de,out_hsync,out_vsync}<=controls_s2;
            if(!controls_s2[2])out_rgb<=0;
            else if(text_s2 && font_s2[31-col_s2])out_rgb<=fg_s2;
            else if(text_s2 && transparent_s2 && font_s2[15-col_s2])out_rgb<=24'h101010;
            else out_rgb<=bg_s2;
        end
    end
endmodule
