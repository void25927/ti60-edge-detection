`timescale 1ns/1ps
// 原始矩转换为Q8质心和Q8角度；方向是主轴，180度歧义由模板比对消除。
module inspection_geometry(
    input wire clk,rst_n,in_valid,
    output wire in_ready,
    input wire [31:0] in_frame_id,
    input wire [2:0] in_object_id,
    input wire [21:0] in_area,
    input wire [31:0] in_sum_x,in_sum_y,
    input wire [43:0] in_sum_xx,in_sum_yy,in_sum_xy,
    output reg out_valid,
    input wire out_ready,
    output reg [31:0] out_frame_id,
    output reg [2:0] out_object_id,
    output reg [18:0] center_x_q8,center_y_q8,
    output reg signed [15:0] axis_angle_q8,
    output reg axis_unreliable,invalid_moments
);
    localparam IDLE=0,PRODUCT=1,COVARIANCE=2,DIVIDE=3,DIV_END=4,ANGLE_INIT=5,ANGLE=6,OUTPUT=7;
    reg [3:0] state;
    reg [21:0] a;
    reg [31:0] sx,sy;
    reg [43:0] sxx,syy,sxy;
    reg [65:0] axx,ayy,axy,xx,yy,xy;
    reg signed [65:0] cxx,cyy,cxy,vx,vy;
    reg signed [18:0] angle;
    reg [4:0] iteration;
    reg rotation_phase;
    reg signed [65:0] next_vy;
    // 先算Y再算X，使用同一组旧向量；每次66位加减再拆成低/高33位两拍。
    wire signed [65:0] rotation_input=rotation_phase?vy:vx;
    wire signed [65:0] rotation_base=rotation_phase?vx:vy;
    wire signed [65:0] rotation_shift=rotation_input>>>iteration;
    wire rotation_subtract=rotation_phase?(vy<0):(vy>0);
    wire [65:0] rotation_operand=rotation_shift ^ {66{rotation_subtract}};
    reg rotation_half;
    reg [32:0] rotation_low,rotation_high_base,rotation_high_operand;
    reg rotation_carry;
    wire [33:0] rotation_low_sum={1'b0,rotation_base[32:0]}+{1'b0,rotation_operand[32:0]}+rotation_subtract;
    wire [32:0] rotation_high_sum=rotation_high_base+rotation_high_operand+rotation_carry;
    wire [65:0] rotation_result={rotation_high_sum,rotation_low};
    // 高位存尚未消费的被除数，低位存已生成商；有效位互补，无需两份64位寄存器。
    reg [63:0] division_shift;
    reg [64:0] remainder;
    reg [6:0] bits_left;
    reg second_div;
    wire [64:0] shifted_remainder={remainder[63:0],division_shift[63]};
    wire subtract_ok=(shifted_remainder>={43'd0,a});
    wire [65:0] trace_cov=$unsigned(cxx)+$unsigned(cyy);
    wire signed [65:0] axis_x=cxx-cyy;
    wire signed [65:0] axis_y=cxy<<<1;
    // 复用质心除法的空闲拍；vx/vy在角度迭代前暂存轴向差，不增加任务周期。
    // 原66位无符号加法按模2^66截断，不能扩成67位改变边界判定。
    reg [65:0] trace_q,abs_axis_x,abs_axis_y,axis_strength;
    reg axis_bad;
    assign in_ready=(state==IDLE);
    function signed [18:0] atan_q8;
        input [4:0] i;
        begin
            case(i)
                0:atan_q8=11520;1:atan_q8=6801;2:atan_q8=3593;3:atan_q8=1824;
                4:atan_q8=916;5:atan_q8=458;6:atan_q8=229;7:atan_q8=115;
                8:atan_q8=57;9:atan_q8=29;10:atan_q8=14;11:atan_q8=7;
                12:atan_q8=4;13:atan_q8=2;14:atan_q8=1;default:atan_q8=0;
            endcase
        end
    endfunction
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;out_valid<=0;out_frame_id<=0;out_object_id<=0;
            center_x_q8<=0;center_y_q8<=0;axis_angle_q8<=0;axis_unreliable<=0;invalid_moments<=0;
            a<=0;sx<=0;sy<=0;sxx<=0;syy<=0;sxy<=0;axx<=0;ayy<=0;axy<=0;xx<=0;yy<=0;xy<=0;
            cxx<=0;cyy<=0;cxy<=0;vx<=0;vy<=0;angle<=0;iteration<=0;rotation_phase<=0;next_vy<=0;
            rotation_half<=0;rotation_low<=0;rotation_high_base<=0;rotation_high_operand<=0;rotation_carry<=0;
            division_shift<=0;remainder<=0;bits_left<=0;second_div<=0;
            trace_q<=0;abs_axis_x<=0;abs_axis_y<=0;axis_strength<=0;axis_bad<=0;
        end else case(state)
            IDLE:if(in_valid)begin
                out_frame_id<=in_frame_id;out_object_id<=in_object_id;
                a<=in_area;sx<=in_sum_x;sy<=in_sum_y;sxx<=in_sum_xx;syy<=in_sum_yy;sxy<=in_sum_xy;
                invalid_moments<=0;axis_unreliable<=0;out_valid<=0;
                center_x_q8<=0;center_y_q8<=0;axis_angle_q8<=0;
                if(in_area==0)begin invalid_moments<=1;axis_unreliable<=1;state<=OUTPUT;end
                else state<=PRODUCT;
            end
            PRODUCT:begin
                axx<=a*sxx;ayy<=a*syy;axy<=a*sxy;xx<=sx*sx;yy<=sy*sy;xy<=sx*sy;
                state<=COVARIANCE;
            end
            COVARIANCE:begin
                cxx<=$signed(axx)-$signed(xx);cyy<=$signed(ayy)-$signed(yy);cxy<=$signed(axy)-$signed(xy);
                if(axx<xx || ayy<yy)begin invalid_moments<=1;axis_unreliable<=1;state<=OUTPUT;end
                else begin
                    division_shift<={24'd0,sx,8'd0};remainder<=0;bits_left<=64;second_div<=0;state<=DIVIDE;
                end
            end
            DIVIDE:begin
                if(!second_div)case(bits_left)
                    64:begin vx<=axis_x;vy<=axis_y;trace_q<=trace_cov;end
                    63:begin abs_axis_x<=vx[65] ? -vx : vx;abs_axis_y<=vy[65] ? -vy : vy;end
                    62:axis_strength<=abs_axis_x+abs_axis_y;
                    61:axis_bad<=(trace_q==0 || axis_strength<(trace_q>>4));
                    default:begin end
                endcase
                division_shift<={division_shift[62:0],subtract_ok};
                remainder<=subtract_ok ? shifted_remainder-a : shifted_remainder;
                bits_left<=bits_left-1'b1;
                if(bits_left==1)state<=DIV_END;
            end
            DIV_END:begin
                if(division_shift>=(second_div?64'd276480:64'd491520))invalid_moments<=1;
                if(!second_div)begin
                    center_x_q8<=division_shift[18:0];division_shift<={24'd0,sy,8'd0};remainder<=0;
                    bits_left<=64;second_div<=1;state<=DIVIDE;
                end else begin center_y_q8<=division_shift[18:0];state<=ANGLE_INIT;end
            end
            ANGLE_INIT:begin
                axis_unreliable<=axis_bad;
                iteration<=0;rotation_phase<=0;rotation_half<=0;
                if(vx<0)begin
                    vx<=-vx;vy<=-vy;angle<=(vy<0)?-19'sd46080:19'sd46080;
                end else begin angle<=0;end
                state<=ANGLE;
            end
            ANGLE:begin
                if(!rotation_half && !rotation_phase && (iteration==16 || vy==0))begin
                    axis_angle_q8<=axis_unreliable ? 16'sd0 : (angle>>>1);state<=OUTPUT;
                end else if(!rotation_half)begin
                    rotation_low<=rotation_low_sum[32:0];rotation_carry<=rotation_low_sum[33];
                    rotation_high_base<=rotation_base[65:33];rotation_high_operand<=rotation_operand[65:33];
                    rotation_half<=1;
                end else if(!rotation_phase)begin
                    rotation_half<=0;
                    next_vy<=rotation_result;rotation_phase<=1;
                end else begin
                    rotation_half<=0;
                    vx<=rotation_result;vy<=next_vy;rotation_phase<=0;
                    if(vy>0)begin
                        angle<=angle+atan_q8(iteration);
                    end else begin
                        angle<=angle-atan_q8(iteration);
                    end
                    iteration<=iteration+1'b1;
                end
            end
            OUTPUT:begin
                out_valid<=1;
                if(out_valid && out_ready)begin out_valid<=0;state<=IDLE;end
            end
            default:state<=IDLE;
        endcase
    end
endmodule
