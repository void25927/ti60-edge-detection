`timescale 1ns/1ps
// Q8角度转Q14正余弦。24拍移位加减旋转，无缩放或三角函数厂商IP。
module inspection_angle_sincos(
    input wire clk,rst_n,in_valid,
    output wire in_ready,
    input wire [31:0] frame_id,template_frame_id,
    input wire [2:0] object_id,
    input wire signed [16:0] angle_q8,
    output reg out_valid,
    input wire out_ready,
    output reg [31:0] out_frame_id,out_template_id,
    output reg [2:0] out_object_id,
    output reg signed [15:0] cosine_q14,sine_q14,
    output reg invalid_angle
);
    localparam IDLE=0,ROTATE=1,ROUND=2,OUTPUT=3;
    reg [1:0] state;
    reg [4:0] iteration;
    reg signed [31:0] x,y;
    reg signed [34:0] z;
    wire signed [34:0] extended_angle={{18{angle_q8[16]}},angle_q8};
    wire signed [34:0] reduced_angle=(angle_q8>17'sd23040)?extended_angle-35'sd46080:
        (angle_q8< -17'sd23040)?extended_angle+35'sd46080:extended_angle;
    function signed [34:0] atan_table;
        input [4:0] i;
        begin case(i)
            0:atan_table=35'sd754974720;1:atan_table=35'sd445687602;
            2:atan_table=35'sd235489088;3:atan_table=35'sd119537938;
            4:atan_table=35'sd60000934;5:atan_table=35'sd30029717;
            6:atan_table=35'sd15018523;7:atan_table=35'sd7509720;
            8:atan_table=35'sd3754917;9:atan_table=35'sd1877466;
            10:atan_table=35'sd938734;11:atan_table=35'sd469367;
            12:atan_table=35'sd234684;13:atan_table=35'sd117342;
            14:atan_table=35'sd58671;15:atan_table=35'sd29335;
            16:atan_table=35'sd14668;17:atan_table=35'sd7334;
            18:atan_table=35'sd3667;19:atan_table=35'sd1833;
            20:atan_table=35'sd917;21:atan_table=35'sd458;
            22:atan_table=35'sd229;default:atan_table=35'sd115;
        endcase end
    endfunction
    assign in_ready=state==IDLE;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;iteration<=0;x<=0;y<=0;z<=0;out_valid<=0;
            out_frame_id<=0;out_template_id<=0;out_object_id<=0;
            cosine_q14<=0;sine_q14<=0;invalid_angle<=0;
        end else case(state)
            IDLE:if(in_valid)begin
                out_frame_id<=frame_id;out_template_id<=template_frame_id;out_object_id<=object_id;
                invalid_angle<=angle_q8< -17'sd46080 || angle_q8>17'sd46080;
                cosine_q14<=0;sine_q14<=0;iteration<=0;y<=0;
                x<=(angle_q8>17'sd23040 || angle_q8< -17'sd23040)?-32'sd652032874:32'sd652032874;
                z<=reduced_angle<<<16;
                state<=(angle_q8< -17'sd46080 || angle_q8>17'sd46080)?OUTPUT:ROTATE;
            end
            ROTATE:begin
                if(z>=0)begin x<=x-(y>>>iteration);y<=y+(x>>>iteration);z<=z-atan_table(iteration);end
                else begin x<=x+(y>>>iteration);y<=y-(x>>>iteration);z<=z+atan_table(iteration);end
                if(iteration==23)state<=ROUND;else iteration<=iteration+1'b1;
            end
            ROUND:begin cosine_q14<=(x+32'sd32768)>>>16;sine_q14<=(y+32'sd32768)>>>16;state<=OUTPUT;end
            OUTPUT:begin out_valid<=1;if(out_valid && out_ready)begin out_valid<=0;state<=IDLE;end end
            default:state<=IDLE;
        endcase
    end
endmodule
