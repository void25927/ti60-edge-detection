`timescale 1ns / 1ps

// MODERN_UI=1: 中文上边栏、透明状态区和底部菜单，统一延迟4拍。
// MODERN_UI=0: 保留原64像素信息栏与1拍接口，供既有单元测试兼容。
module video_ui_overlay #(
    parameter integer DISPLAY_WIDTH = 1920,
    parameter integer DISPLAY_HEIGHT = 1080,
    parameter         VSYNC_ACTIVE_LEVEL = 1'b0,
    parameter         FEATURE_MENU = 0,
    parameter         INSPECTION_UI = 0,
    parameter         EDGE_DIAGNOSTICS = 0,
    parameter integer CLK_FREQ_HZ=148800000,
    parameter REPLAY_BITS=2,
    parameter MODERN_UI=0
)(
    input  wire        clk,              // HDMI像素时钟
    input  wire        rst_n,            // 低电平异步复位
    input  wire [23:0] in_rgb,           // 原RGB888显示像素
    input  wire        in_de,            // 输入数据有效
    input  wire        in_hsync,         // 输入行同步
    input  wire        in_vsync,         // 输入场同步
    input  wire [1:0]  in_mode,          // 0实时，1冻结，2回放，3参数
    input  wire        in_display_mode,  // 0灰度/边缘分屏，1彩色边缘叠加
    input  wire [10:0] in_high_threshold,// 当前高阈值
    input  wire [10:0] in_low_threshold, // 当前低阈值
    input  wire [REPLAY_BITS-1:0] in_replay_offset, // 当前历史帧位置
    input  wire        in_ddr_error,      // DDR欠数错误锁存
    input  wire        in_video_error,    // 视频帧同步错误锁存
    input  wire [2:0]  in_menu,
    input  wire        in_median_enable,in_canny_enable,
    input  wire        in_saving,
    input  wire [2:0]  in_saved_valid,
    input  wire        inspection_background_ready,inspection_template_valid,
    input  wire        inspection_learning,inspection_enabled,inspection_matched,
    input  wire        inspection_fault,
    input  wire [1:0]  inspection_status,
    input  wire [31:0] inspection_frame_id,inspection_detection_id,
    input  wire [15:0] inspection_track_id,
    input  wire [2:0]  inspection_count,
    input  wire [7:0]  inspection_diagnostic,

    output reg  [23:0] out_rgb,           // 叠加后的RGB888像素
    output reg         out_de,            // 与RGB相同延迟的数据有效
    output reg         out_hsync,         // 与RGB相同延迟的行同步
    output reg         out_vsync          // 与RGB相同延迟的场同步
);

    localparam [23:0] COLOR_BACKGROUND = 24'h102840;
    localparam [23:0] COLOR_TEXT       = 24'hFFFFFF;
    localparam [23:0] COLOR_PARAM      = 24'hFFD040;
    localparam [23:0] COLOR_ERROR      = 24'hFF4040;
    localparam [23:0] COLOR_SEPARATOR  = 24'h40C0FF;

    reg [10:0] pixel_x; // 当前输入有效区横坐标
    reg [10:0] pixel_y; // 当前输入有效区纵坐标
    reg        de_d;
    reg        vsync_d;
    wire       de_fall = de_d && !in_de;
    wire       vsync_active = (in_vsync == VSYNC_ACTIVE_LEVEL);
    wire       vsync_start = vsync_active && (vsync_d != VSYNC_ACTIVE_LEVEL);
    wire [7:0] fps_hundreds,fps_tens,fps_units;
    reg [23:0] fps_text;
    wire [19:0] frame_bcd;
    video_ui_metrics #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) u_metrics(
        .clk(clk),.rst_n(rst_n),.frame_start(vsync_start),
        .fps_bcd(),.frame_bcd(frame_bcd));
    hdmi_fps_counter #(.CLK_HZ(CLK_FREQ_HZ),.VSYNC_ACTIVE_LEVEL(VSYNC_ACTIVE_LEVEL)) u_fps(
        .clk(clk),.rst_n(rst_n),.vsync(in_vsync),
        .fps_bcd(),.fps_valid(),.fps_update(),
        .char_hundreds(fps_hundreds),.char_tens(fps_tens),.char_units(fps_units));
    // Latch all display digits at the frame boundary to prevent mid-frame changes.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)fps_text<=24'h2d2d2d;
        else if(vsync_start)fps_text<={fps_hundreds,fps_tens,fps_units};
    end

    // 阈值十进制转换在场消隐期串行完成，避免长组合除法路径。
    reg [26:0] high_shift;
    reg [26:0] low_shift;
    reg [3:0]  bcd_count;
    reg [15:0] high_bcd;
    reg [15:0] low_bcd;

    function [26:0] add3_bcd;
        input [26:0] value;
        reg [26:0] temp;
        begin
            temp = value;
            if (temp[14:11] >= 4'd5) temp[14:11] = temp[14:11] + 4'd3;
            if (temp[18:15] >= 4'd5) temp[18:15] = temp[18:15] + 4'd3;
            if (temp[22:19] >= 4'd5) temp[22:19] = temp[22:19] + 4'd3;
            if (temp[26:23] >= 4'd5) temp[26:23] = temp[26:23] + 4'd3;
            add3_bcd = temp;
        end
    endfunction

    wire [26:0] high_adjusted = add3_bcd(high_shift);
    wire [26:0] low_adjusted  = add3_bcd(low_shift);

    wire [23:0] modern_rgb;
    wire modern_de,modern_hs,modern_vs;
    generate if(MODERN_UI)begin:g_modern
        vision_ui_renderer #(.WIDTH(DISPLAY_WIDTH),.HEIGHT(DISPLAY_HEIGHT),
            .VSYNC_ACTIVE_LEVEL(VSYNC_ACTIVE_LEVEL)) renderer(
            .clk(clk),.rst_n(rst_n),.in_rgb(in_rgb),.in_de(in_de),
            .in_hsync(in_hsync),.in_vsync(in_vsync),.menu(in_menu),
            .median_enable(in_median_enable),.canny_enable(in_canny_enable),
            .replay_active(in_mode==1 || in_mode==2),.replay_paused(in_mode==1),.saving(in_saving),
            .threshold_bcd(high_bcd),.fps_text(fps_text),
            .background_ready(inspection_background_ready),.template_valid(inspection_template_valid),
            .learning(inspection_learning),.enabled(inspection_enabled),.matched(inspection_matched),
            .fault(inspection_fault),.ddr_error(in_ddr_error),.video_error(in_video_error),
            .result_status(inspection_status),.object_count(inspection_count),
            .frame_id(inspection_frame_id),.detection_id(inspection_detection_id),
            .diagnostic(EDGE_DIAGNOSTICS?inspection_diagnostic:8'd0),
            .out_rgb(modern_rgb),.out_de(modern_de),.out_hsync(modern_hs),.out_vsync(modern_vs));
    end else begin:g_legacy
        assign modern_rgb=0;assign modern_de=0;assign modern_hs=0;assign modern_vs=VSYNC_ACTIVE_LEVEL;
    end endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            high_shift <= 27'd0;
            low_shift  <= 27'd0;
            bcd_count  <= 4'd0;
            high_bcd   <= 16'h0000;
            low_bcd    <= 16'h0000;
        end else if (vsync_start) begin
            high_shift <= {16'd0, in_high_threshold};
            low_shift  <= {16'd0, in_low_threshold};
            bcd_count  <= 4'd11;
        end else if (bcd_count != 0) begin
            high_shift <= high_adjusted << 1;
            low_shift  <= low_adjusted << 1;
            bcd_count  <= bcd_count - 1'b1;
            if (bcd_count == 1) begin
                high_bcd <= (high_adjusted << 1) >> 11;
                low_bcd  <= (low_adjusted << 1) >> 11;
            end
        end
    end

    // 生成当前字符。每个字符宽8像素，信息栏包含两行文字。
    // 行坐标只在消隐边界改变，同行状态同拍更新，避免Y比较串入字符/字体/RGB长链。
    // 不增加视频延迟；即使行间只有1拍DE低电平，下一行首像素也使用新状态。
    reg row0_q,row1_q,header_q,separator_q;
    reg [3:0] font0_q,font1_q;
    wire [10:0] following_y=(pixel_y==DISPLAY_HEIGHT-1)?11'd0:pixel_y+11'd1;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            row0_q<=0;row1_q<=0;header_q<=1;separator_q<=0;font0_q<=4'd8;font1_q<=4'd12;
        end else if(vsync_active)begin
            row0_q<=0;row1_q<=0;header_q<=1;separator_q<=0;font0_q<=4'd8;font1_q<=4'd12;
        end else if(de_fall)begin
            row0_q<=following_y>=8 && following_y<24;
            row1_q<=following_y>=36 && following_y<52;
            header_q<=following_y<64;separator_q<=following_y==63;
            font0_q<=following_y[3:0]-4'd8;font1_q<=following_y[3:0]-4'd4;
        end
    end
    // 与像素计数同步的字符列，等于(pixel_x[10:3]-2)模256。
    // 仅8位控制暂存，不缓存动态UI内容，也不增加视频输出延迟。
    reg [7:0] text_column;
    wire in_text_row0 = row0_q && text_column < 8'd254;
    wire in_text_row1 = row1_q && text_column < 8'd254;
    wire [3:0] font_row = in_text_row0 ? font0_q : font1_q;

    function [7:0] digit_ascii;
        input [3:0] digit;
        begin digit_ascii = 8'h30 + digit; end
    endfunction

    reg [7:0] current_char;
    reg [71:0] menu_text;
    always @(*)begin
        case(in_menu)
            0:menu_text="MEDIAN   ";
            1:menu_text="THRESHOLD";
            2:menu_text="REPLAY   ";
            3:menu_text="CANNY    ";
            4:menu_text="DISPLAY  ";
            5:menu_text="INSPECT  ";
            default:menu_text="UNKNOWN  ";
        endcase
    end
    function [7:0] hex_ascii;
        input [3:0] value;
        // 固定16项字码，避免字符选择后再串接比较、加减链。
        begin
            case(value)
                0:hex_ascii="0";1:hex_ascii="1";2:hex_ascii="2";3:hex_ascii="3";
                4:hex_ascii="4";5:hex_ascii="5";6:hex_ascii="6";7:hex_ascii="7";
                8:hex_ascii="8";9:hex_ascii="9";10:hex_ascii="A";11:hex_ascii="B";
                12:hex_ascii="C";13:hex_ascii="D";14:hex_ascii="E";15:hex_ascii="F";
                default:hex_ascii=(value<10)?(8'h30+value):(8'h41+value-10);
            endcase
        end
    endfunction
    reg [31:0] inspection_word;
    always @(*)begin
        if(!inspection_background_ready)inspection_word="CAL ";
        else if(inspection_learning)inspection_word="LRN ";
        else if(inspection_fault)inspection_word=EDGE_DIAGNOSTICS?{8'h45,hex_ascii(inspection_diagnostic[7:4]),hex_ascii(inspection_diagnostic[3:0]),8'h20}:"ERR ";
        else if(!inspection_template_valid)inspection_word=(EDGE_DIAGNOSTICS && inspection_diagnostic==8'h40)?"CONF":"NONE";
        else if(!inspection_enabled)inspection_word="RDY ";
        else if(!inspection_matched || inspection_status==0)inspection_word="WAIT";
        else if(inspection_status==1)inspection_word="PASS";
        else if(inspection_status==3)inspection_word="PEND";
        else inspection_word="FAIL";
    end
    always @(*) begin
        current_char = 8'h20;
        if (in_text_row0) begin
            case (text_column)
                1: current_char=8'h4D; 2: current_char=8'h4F;
                3: current_char=8'h44; 4: current_char=8'h45;
                5: current_char=8'h3A;
                7: begin
                    case(in_mode) 2'd0:current_char=8'h4C; 2'd1:current_char=8'h46;
                                  2'd2:current_char=8'h52; default:current_char=8'h50; endcase
                   end
                8: begin
                    case(in_mode) 2'd0:current_char=8'h49; 2'd1:current_char=8'h52;
                                  2'd2:current_char=8'h45; default:current_char=8'h41; endcase
                   end
                9: begin
                    case(in_mode) 2'd0:current_char=8'h56; 2'd1:current_char=8'h45;
                                  2'd2:current_char=8'h50; default:current_char=8'h52; endcase
                   end
                10: begin
                    case(in_mode) 2'd0:current_char=8'h45; 2'd1:current_char=8'h45;
                                  2'd2:current_char=8'h4C; default:current_char=8'h41; endcase
                    end
                11: begin
                    case(in_mode) 2'd1:current_char=8'h5A; 2'd2:current_char=8'h41;
                                  2'd3:current_char=8'h4D; default:current_char=8'h20; endcase
                    end
                12: begin
                    case(in_mode) 2'd1:current_char=8'h45; 2'd2:current_char=8'h59;
                                  default:current_char=8'h20; endcase
                    end
                16: current_char=8'h41; 17: current_char=8'h4C;
                18: current_char=8'h47; 19: current_char=8'h3A;
                21: current_char=8'h43; 22: current_char=8'h41;
                23: current_char=8'h4E; 24: current_char=8'h4E;
                25: current_char=8'h59;
                30: current_char=8'h44; 31: current_char=8'h44;
                32: current_char=8'h52; 33: current_char=8'h3A;
                35: current_char=in_ddr_error ? 8'h45 : 8'h4F;
                36: current_char=in_ddr_error ? 8'h52 : 8'h4B;
                37: current_char=in_ddr_error ? 8'h52 : 8'h20;
                42: current_char=8'h56; 43: current_char=8'h49;
                44: current_char=8'h44; 45: current_char=8'h45;
                46: current_char=8'h4F; 47: current_char=8'h3A;
                49: current_char=in_video_error ? 8'h45 : 8'h4F;
                50: current_char=in_video_error ? 8'h52 : 8'h4B;
                51: current_char=in_video_error ? 8'h52 : 8'h20;
                54: current_char=8'h56; 55: current_char=8'h49;
                56: current_char=8'h45; 57: current_char=8'h57;
                58: current_char=8'h3A;
                60: current_char=in_display_mode ? 8'h4F : 8'h53;
                61: current_char=in_display_mode ? 8'h56 : 8'h50;
                62: current_char=in_display_mode ? 8'h4C : 8'h4C;
                63: current_char=in_display_mode ? 8'h59 : 8'h54;
                default: current_char=8'h20;
            endcase
        end else if (in_text_row1) begin
            case (text_column)
                1: current_char=8'h48; 2: current_char=8'h49;
                3: current_char=8'h47; 4: current_char=8'h48;
                5: current_char=8'h3A;
                7: current_char=digit_ascii(high_bcd[15:12]);
                8: current_char=digit_ascii(high_bcd[11:8]);
                9: current_char=digit_ascii(high_bcd[7:4]);
                10:current_char=digit_ascii(high_bcd[3:0]);
                13:current_char=8'h4C; 14:current_char=8'h4F;
                15:current_char=8'h57; 16:current_char=8'h3A;
                18:current_char=digit_ascii(low_bcd[15:12]);
                19:current_char=digit_ascii(low_bcd[11:8]);
                20:current_char=digit_ascii(low_bcd[7:4]);
                21:current_char=digit_ascii(low_bcd[3:0]);
                24:current_char=8'h46; 25:current_char=8'h52;
                26:current_char=8'h41; 27:current_char=8'h4D;
                28:current_char=8'h45; 29:current_char=8'h3A;
                31:current_char=digit_ascii(in_replay_offset);
                35:current_char=8'h52; 36:current_char=8'h45;
                37:current_char=8'h53; 38:current_char=8'h55;
                39:current_char=8'h4C; 40:current_char=8'h54;
                41:current_char=8'h3A;
                43,44,45,46: current_char=8'h2D;
                default: current_char=8'h20;
            endcase
        end
        if(FEATURE_MENU)begin
            if(in_text_row0)begin
                if(!in_canny_enable)case(text_column)
                    21:current_char="S";22:current_char="O";23:current_char="B";
                    24:current_char="E";25:current_char="L";
                    default:begin end
                endcase
                case(text_column)
                    68:current_char="M";69:current_char="E";70:current_char="N";
                    71:current_char="U";72:current_char=":";
                    74:current_char=menu_text[71:64];75:current_char=menu_text[63:56];
                    76:current_char=menu_text[55:48];77:current_char=menu_text[47:40];
                    78:current_char=menu_text[39:32];79:current_char=menu_text[31:24];
                    80:current_char=menu_text[23:16];81:current_char=menu_text[15:8];82:current_char=menu_text[7:0];
                    86:current_char="M";87:current_char="E";88:current_char="D";89:current_char=":";
                    91:current_char="O";92:current_char=in_median_enable?"N":"F";
                    93:current_char=in_median_enable?" ":"F";
                    default:begin end
                endcase
            end
            if(in_text_row1)case(text_column)
                50:current_char="S";51:current_char="A";52:current_char="V";
                53:current_char="E";54:current_char=":";
                56:current_char=in_saving?"B":"R";57:current_char=in_saving?"U":"E";
                58:current_char=in_saving?"S":"A";59:current_char=in_saving?"Y":"D";
                60:current_char=in_saving?" ":"Y";
                64:current_char="P";65:current_char="I";66:current_char="C";67:current_char=":";
                69:current_char=in_saved_valid[0]?"1":"-";
                71:current_char=in_saved_valid[1]?"2":"-";
                73:current_char=in_saved_valid[2]?"3":"-";
                default:begin end
            endcase
        end
        // 保留原RESULT位置；右方空闲区域显示完整帧号、首目标ID和完整检测来源帧。
        if(INSPECTION_UI && in_text_row1)begin
            case(text_column)
                43:current_char=inspection_word[31:24];44:current_char=inspection_word[23:16];
                45:current_char=inspection_word[15:8];46:current_char=inspection_word[7:0];
                78:current_char="F";79:current_char=":";
                80:current_char=hex_ascii(inspection_frame_id[31:28]);81:current_char=hex_ascii(inspection_frame_id[27:24]);
                82:current_char=hex_ascii(inspection_frame_id[23:20]);83:current_char=hex_ascii(inspection_frame_id[19:16]);
                84:current_char=hex_ascii(inspection_frame_id[15:12]);85:current_char=hex_ascii(inspection_frame_id[11:8]);
                86:current_char=hex_ascii(inspection_frame_id[7:4]);87:current_char=hex_ascii(inspection_frame_id[3:0]);
                90:current_char="I";91:current_char="D";92:current_char=":";
                93:current_char=hex_ascii(inspection_track_id[15:12]);94:current_char=hex_ascii(inspection_track_id[11:8]);
                95:current_char=hex_ascii(inspection_track_id[7:4]);96:current_char=hex_ascii(inspection_track_id[3:0]);
                99:current_char="D";100:current_char=":";
                101:current_char=hex_ascii(inspection_detection_id[31:28]);102:current_char=hex_ascii(inspection_detection_id[27:24]);
                103:current_char=hex_ascii(inspection_detection_id[23:20]);104:current_char=hex_ascii(inspection_detection_id[19:16]);
                105:current_char=hex_ascii(inspection_detection_id[15:12]);106:current_char=hex_ascii(inspection_detection_id[11:8]);
                107:current_char=hex_ascii(inspection_detection_id[7:4]);108:current_char=hex_ascii(inspection_detection_id[3:0]);
                111:current_char="N";112:current_char=":";
                113:current_char=digit_ascii({1'b0,inspection_count});
                default:begin end
            endcase
        end
        // 独立空闲区，避开轮廓F/ID/D/N字段；H表示HDMI刷新而非识别吞吐。
        if(FEATURE_MENU && in_text_row0)case(text_column)
            145:current_char="H";146:current_char="F";147:current_char="P";
            148:current_char="S";149:current_char=":";
            151:current_char=fps_text[23:16];
            152:current_char=fps_text[15:8];
            153:current_char=fps_text[7:0];
            154:current_char=" ";155:current_char=" ";
            default:begin end
        endcase
        if(FEATURE_MENU && in_text_row1)case(text_column)
            145:current_char="H";146:current_char="F";147:current_char="R";
            148:current_char="M";149:current_char=":";
            151:current_char=digit_ascii(frame_bcd[19:16]);
            152:current_char=digit_ascii(frame_bcd[15:12]);
            153:current_char=digit_ascii(frame_bcd[11:8]);
            154:current_char=digit_ascii(frame_bcd[7:4]);
            155:current_char=digit_ascii(frame_bcd[3:0]);
            default:begin end
        endcase
    end

    wire [7:0] font_bits;
    font_rom_8x16 u_font_rom (
        .char_code(current_char),
        .row_index(font_row),
        .row_bits(font_bits)
    );
    wire font_pixel = (in_text_row0 || in_text_row1) &&
                      font_bits[7 - pixel_x[2:0]];

    reg [23:0] composed_rgb;
    always @(*) begin
        if (!in_de)
            composed_rgb = 24'h000000;
        else if (separator_q)
            composed_rgb = COLOR_SEPARATOR;
        else if (header_q) begin
            if (font_pixel) begin
                if ((in_ddr_error && text_column >= 35 && text_column <= 37) ||
                    (in_video_error && text_column >= 49 && text_column <= 51))
                    composed_rgb = COLOR_ERROR;
                else if (in_mode == 2'd3 && text_column >= 7 && text_column <= 12)
                    composed_rgb = COLOR_PARAM;
                else if (FEATURE_MENU && text_column>=151 && text_column<=155)
                    composed_rgb = 24'h50ff90;
                else
                    composed_rgb = COLOR_TEXT;
            end else begin
                composed_rgb = COLOR_BACKGROUND;
            end
        end else begin
            composed_rgb = in_rgb;
        end
    end

    // 最后一拍输出；现代UI含内部3拍，共4拍，四种信号始终对齐。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_rgb   <= 24'h000000;
            out_de    <= 1'b0;
            out_hsync <= 1'b0;
            out_vsync <= VSYNC_ACTIVE_LEVEL;
        end else begin
            out_rgb   <= MODERN_UI?modern_rgb:composed_rgb;
            out_de    <= MODERN_UI?modern_de:in_de;
            out_hsync <= MODERN_UI?modern_hs:in_hsync;
            out_vsync <= MODERN_UI?modern_vs:in_vsync;
        end
    end

    // 坐标以输入DE为准，场同步有效时回到第0行。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_x <= 11'd0;
            text_column <= 8'hfe;
            pixel_y <= 11'd0;
            de_d    <= 1'b0;
            vsync_d <= VSYNC_ACTIVE_LEVEL;
        end else begin
            de_d    <= in_de;
            vsync_d <= in_vsync;
            if (vsync_active) begin
                pixel_x <= 11'd0;
                text_column <= 8'hfe;
                pixel_y <= 11'd0;
            end else begin
                if (in_de) begin
                    if (pixel_x == DISPLAY_WIDTH - 1)begin
                        pixel_x <= 11'd0;
                        text_column <= 8'hfe;
                    end else begin
                        pixel_x <= pixel_x + 1'b1;
                        if(pixel_x[2:0]==3'd7)text_column<=text_column+1'b1;
                    end
                end else begin
                    pixel_x <= 11'd0;
                    text_column <= 8'hfe;
                end

                if (de_fall) begin
                    if (pixel_y == DISPLAY_HEIGHT - 1)
                        pixel_y <= 11'd0;
                    else
                        pixel_y <= pixel_y + 1'b1;
                end
            end
        end
    end

endmodule
