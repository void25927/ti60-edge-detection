`timescale 1ns/1ps
// 固定像素尺度轮廓比较；只尝试主轴正反向及相邻一箱的中心舍入补偿。
module inspection_axial_compare #(
    parameter AREA_TOLERANCE=100,LENGTH_TOLERANCE=4,WIDTH_TOLERANCE=3,
    parameter PROFILE_TOLERANCE=720,WIDTH_SUM_TOLERANCE=42
)(
    input wire clk,rst_n,start_valid,
    output wire start_ready,
    input wire [31:0] frame_id,
    input wire [15:0] track_id,
    input wire [1837:0] scene_descriptor,template_descriptor,
    input wire template_valid,data_invalid,
    output wire result_valid,
    input wire result_ready,
    output reg [31:0] result_frame_id,
    output reg [15:0] result_track_id,
    output reg [1:0] status,
    output reg [7:0] reasons,
    output reg [31:0] cycles,
    output reg [21:0] count_difference,width_difference
);
    localparam IDLE=0,SCAN=1,REDUCE=2,DECIDE=3,OUTPUT=4;
    reg [2:0] state;
    reg [45:0] b_geometry;
    // 顺序轮转代替每拍六组1838位可变索引，保留全部64箱、六候选及原415拍时序。
    reg [1903:0] a_ring;
    reg [1959:0] b_ring;
    reg [45:0] a_geometry;
    reg [15:0] ap1,ap2,bp1,bp2;
    reg [11:0] aw1,bw1;
    reg [2:0] candidate;
    reg [6:0] i;
    reg [21:0] sum_count,sum_width,best_count,best_width;
    reg bad,tv;
    function [1903:0] make_a;
        input [1837:0] d;
        integer k;
        begin
            make_a=0;
            for(k=0;k<64;k=k+1)make_a[(k+1)*28+:28]={d[1024+k*12+:12],d[k*16+:16]};
        end
    endfunction
    function [1959:0] make_b;
        input [1837:0] d;
        input reverse;
        input [1:0] skip;
        reg [1959:0] t;
        integer k,j;
        begin
            t=0;
            for(k=0;k<64;k=k+1)begin
                j=reverse?63-k:k;
                t[(k+2)*28+:28]={d[1024+j*12+:12],d[j*16+:16]};
            end
            case(skip)
                1:make_b={t[27:0],t[1959:28]};
                2:make_b={t[55:0],t[1959:56]};
                default:make_b=t;
            endcase
        end
    endfunction
    // 68拍扫描后，正向第三候选恰好回到原始70箱布局。
    // 反转64个有效箱并保留六个补零箱，得到反向偏移2的候选。
    function [1959:0] reverse_after_scan;
        input [1959:0] ring_data;
        integer k;
        begin
            reverse_after_scan=0;
            for(k=0;k<64;k=k+1)
                reverse_after_scan[k*28+:28]=ring_data[(65-k)*28+:28];
        end
    endfunction
    wire [21:0] aa=a_geometry[45:24],ba=b_geometry[45:24];
    wire [11:0] al=a_geometry[23:12],bl=b_geometry[23:12],ah=a_geometry[11:0],bh=b_geometry[11:0];
    wire [11:0] half_a=(ah+12'd1)>>1,half_b=(bh+12'd1)>>1;
    wire [15:0] an=(a_ring[27:16]>=half_a)?a_ring[15:0]:16'd0;
    wire [15:0] bn=(b_ring[27:16]>=half_b)?b_ring[15:0]:16'd0;
    wire [17:0] ac={2'b0,ap2}+{1'b0,ap1,1'b0}+{2'b0,an};
    wire [17:0] bc={2'b0,bp2}+{1'b0,bp1,1'b0}+{2'b0,bn};
    wire [11:0] aw=aw1,bw=bw1;
    wire [11:0] width_delta=aw>bw?aw-bw:bw-aw;
    wire [11:0] height_delta=ah>bh?ah-bh:bh-ah;
    wire global_bad=(aa>ba?aa-ba:ba-aa)>AREA_TOLERANCE || (al>bl?al-bl:bl-al)>LENGTH_TOLERANCE ||
                    height_delta>WIDTH_TOLERANCE || best_count>PROFILE_TOLERANCE || best_width>WIDTH_SUM_TOLERANCE;
    assign start_ready=state==IDLE;
    assign result_valid=state==OUTPUT;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin state<=IDLE;a_ring<=0;b_ring<=0;a_geometry<=0;b_geometry<=0;ap1<=0;ap2<=0;bp1<=0;bp2<=0;aw1<=0;bw1<=0;candidate<=0;i<=0;sum_count<=0;sum_width<=0;best_count<=0;best_width<=0;
            bad<=0;tv<=0;result_frame_id<=0;result_track_id<=0;status<=0;reasons<=0;cycles<=0;count_difference<=0;width_difference<=0;end
        else begin
            if(state!=IDLE && state!=OUTPUT)cycles<=cycles+1'b1;
            case(state)
                IDLE:if(start_valid)begin
                    a_ring<=make_a(scene_descriptor);b_ring<=make_b(template_descriptor,1'b0,2'd0);
                    a_geometry<=scene_descriptor[1837:1792];b_geometry<=template_descriptor[1837:1792];
                    ap1<=0;ap2<=0;bp1<=0;bp2<=0;aw1<=0;bw1<=0;bad<=data_invalid;tv<=template_valid;
                    result_frame_id<=frame_id;result_track_id<=track_id;status<=0;reasons<=0;cycles<=0;candidate<=0;i<=0;
                    sum_count<=0;sum_width<=0;best_count<=22'h3fffff;best_width<=22'h3fffff;count_difference<=0;width_difference<=0;
                    state<=data_invalid || !template_valid?DECIDE:SCAN;
                end
                SCAN:begin
                    a_ring<={a_ring[27:0],a_ring[1903:28]};
                    b_ring<={b_ring[27:0],b_ring[1959:28]};
                    ap2<=ap1;ap1<=an;bp2<=bp1;bp1<=bn;
                    aw1<=a_ring[27:16];bw1<=b_ring[27:16];
                    sum_count<=sum_count+(ac>bc?ac-bc:bc-ac);
                    sum_width<=sum_width+((aw>bw?aw-bw:bw-aw)>1?(aw>bw?aw-bw:bw-aw)-1:0);
                    if(i==67)state<=REDUCE;else i<=i+1'b1;
                end
                REDUCE:begin
                    if(sum_count<best_count || (sum_count==best_count && sum_width<best_width))begin best_count<=sum_count;best_width<=sum_width;end
                    if(candidate==5)state<=DECIDE;
                    else begin
                        case(candidate)
                            // 正向偏移0→1→2：抵消扫描的68箱轮转后再前移一箱。
                            0,1:b_ring<={b_ring[83:0],b_ring[1959:84]};
                            2:b_ring<=reverse_after_scan(b_ring);
                            // 反向偏移2→1→0：扫描后只需再轮转一箱。
                            default:b_ring<={b_ring[27:0],b_ring[1959:28]};
                        endcase
                        ap1<=0;ap2<=0;bp1<=0;bp2<=0;aw1<=0;bw1<=0;
                        candidate<=candidate+1'b1;i<=0;sum_count<=0;sum_width<=0;state<=SCAN;
                    end
                end
                DECIDE:begin
                    count_difference<=best_count;width_difference<=best_width;
                    if(bad || !tv)begin status<=0;reasons<=bad?8'h80:8'h40;end
                    else begin
                        reasons[0]<=(aa>ba?aa-ba:ba-aa)>AREA_TOLERANCE;
                        reasons[1]<=(al>bl?al-bl:bl-al)>LENGTH_TOLERANCE;
                        reasons[2]<=(ah>bh?ah-bh:bh-ah)>WIDTH_TOLERANCE;
                        reasons[3]<=best_count>PROFILE_TOLERANCE;
                        reasons[4]<=best_width>WIDTH_SUM_TOLERANCE;
                        // 微小局部边缘起伏由原全局容差吸收，不另设像素级风险评分。
                        status<=global_bad?2:1;
                    end
                    state<=OUTPUT;
                end
                OUTPUT:if(result_ready)state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
endmodule
