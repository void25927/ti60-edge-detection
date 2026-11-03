`timescale 1ns / 1ps

// 流式Canny流水线。
// 中值去噪→高斯平滑→Sobel→NMS→双阈值→两级局部滞后连接。
module canny_edge_pipeline #(
    parameter integer IMAGE_WIDTH = 960,
    parameter integer ADDR_WIDTH = 10,
    parameter VSYNC_ACTIVE_LEVEL = 1'b0,
    parameter RUNTIME_MEDIAN = 0,
    parameter RUNTIME_CANNY = 0,
    parameter REPAIR_SHORT_GAP = 1,
    parameter MORPH_MODE = 0, MORPH_KERNEL_SHAPE = 1
)(
    input  wire clk,
    input  wire rst_n,
    input  wire in_median_enable, // 同时钟域请求；帧开始时采样，默认启用
    input  wire in_canny_enable, // 关闭时旁路NMS和连接，使用Sobel单阈值
    input  wire [7:0] in_gray,
    input  wire [23:0] in_rgb,
    input  wire in_valid,
    input  wire in_hsync,
    input  wire in_vsync,
    input  wire [10:0] in_high_threshold,
    input  wire [10:0] in_low_threshold,
    output wire [7:0] out_red,
    output wire [7:0] out_green,
    output wire [7:0] out_blue,
    output wire [7:0] out_gray,
    output wire [7:0] out_edge,
    output wire out_valid,
    output wire out_window_valid,
    output wire out_hsync,
    output wire out_vsync
);
    // A：原始灰度窗口和中值滤波。
    wire [31:0] a11,a12,a13,a21,a22,a23,a31,a32,a33;
    wire av,aw,ah,af;
    wire [7:0] median_pixel;
    wire mv,mw,mh,mf;
    reg [7:0] median_gray_delay [0:2];
    reg [23:0] median_rgb_delay [0:2];
    reg median_enable_frame;
    reg canny_enable_frame;
    reg vsync_previous;
    reg [2:0] median_select_delay;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            median_enable_frame <= 1'b1;
            canny_enable_frame <= 1'b1;
            vsync_previous <= ~VSYNC_ACTIVE_LEVEL;
            median_select_delay <= 3'b111;
        end else begin
            vsync_previous <= in_vsync;
            if (in_vsync == VSYNC_ACTIVE_LEVEL && vsync_previous != VSYNC_ACTIVE_LEVEL) begin
                median_enable_frame <= RUNTIME_MEDIAN ? in_median_enable : 1'b1;
                canny_enable_frame <= RUNTIME_CANNY ? in_canny_enable : 1'b1;
            end
            median_select_delay <= {median_select_delay[1:0], median_enable_frame};
        end
    end
    // 旁路选同一个窗口中心像素，延迟与中值运算同为三拍。
    wire [7:0] selected_median = median_select_delay[2] ? median_pixel : median_gray_delay[2];

    gray_3x3_window #(
        .PIXEL_WIDTH(32), .IMAGE_WIDTH(IMAGE_WIDTH), .ADDR_WIDTH(ADDR_WIDTH),
        .VSYNC_ACTIVE_LEVEL(VSYNC_ACTIVE_LEVEL)
    ) u_window_median (
        .clk(clk), .rst_n(rst_n), .in_pixel({in_rgb,in_gray}),
        .in_valid(in_valid), .in_hsync(in_hsync), .in_vsync(in_vsync),
        .out_p11(a11),.out_p12(a12),.out_p13(a13),
        .out_p21(a21),.out_p22(a22),.out_p23(a23),
        .out_p31(a31),.out_p32(a32),.out_p33(a33),
        .out_valid(av),.out_window_valid(aw),.out_hsync(ah),.out_vsync(af)
    );

    median_3x3 u_median (
        .clk(clk),.rst_n(rst_n),
        .in_p11(a11[7:0]),.in_p12(a12[7:0]),.in_p13(a13[7:0]),
        .in_p21(a21[7:0]),.in_p22(a22[7:0]),.in_p23(a23[7:0]),
        .in_p31(a31[7:0]),.in_p32(a32[7:0]),.in_p33(a33[7:0]),
        .in_valid(av),.in_window_valid(aw),.in_hsync(ah),.in_vsync(af),
        .out_pixel(median_pixel),.out_valid(mv),.out_window_valid(mw),
        .out_hsync(mh),.out_vsync(mf)
    );

    // B：保存“有效标志、原始灰度、中值结果”，生成高斯窗口。
    wire [40:0] b11,b12,b13,b21,b22,b23,b31,b32,b33;
    wire bv,bw,bh,bf;
    wire b_all_valid;
    wire [7:0] gaussian_pixel;
    wire gv,gw,gh,gf;
    reg [7:0] gaussian_gray_delay [0:1];
    reg [23:0] gaussian_rgb_delay [0:1];

    gray_3x3_window #(
        .PIXEL_WIDTH(41), .IMAGE_WIDTH(IMAGE_WIDTH), .ADDR_WIDTH(ADDR_WIDTH),
        .VSYNC_ACTIVE_LEVEL(VSYNC_ACTIVE_LEVEL)
    ) u_window_gaussian (
        .clk(clk),.rst_n(rst_n),
        .in_pixel({mw,median_rgb_delay[2],median_gray_delay[2],selected_median}),
        .in_valid(mv),.in_hsync(mh),.in_vsync(mf),
        .out_p11(b11),.out_p12(b12),.out_p13(b13),
        .out_p21(b21),.out_p22(b22),.out_p23(b23),
        .out_p31(b31),.out_p32(b32),.out_p33(b33),
        .out_valid(bv),.out_window_valid(bw),.out_hsync(bh),.out_vsync(bf)
    );
    assign b_all_valid = bw && b11[40] && b12[40] && b13[40] &&
                         b21[40] && b22[40] && b23[40] &&
                         b31[40] && b32[40] && b33[40];

    gaussian_3x3 u_gaussian (
        .clk(clk),.rst_n(rst_n),
        .in_p11(b11[7:0]),.in_p12(b12[7:0]),.in_p13(b13[7:0]),
        .in_p21(b21[7:0]),.in_p22(b22[7:0]),.in_p23(b23[7:0]),
        .in_p31(b31[7:0]),.in_p32(b32[7:0]),.in_p33(b33[7:0]),
        .in_valid(bv),.in_window_valid(b_all_valid),.in_hsync(bh),.in_vsync(bf),
        .out_pixel(gaussian_pixel),.out_valid(gv),.out_window_valid(gw),
        .out_hsync(gh),.out_vsync(gf)
    );

    // C：高斯结果窗口和Sobel梯度方向。
    wire [40:0] c11,c12,c13,c21,c22,c23,c31,c32,c33;
    wire cv,cw,ch,cf;
    wire c_all_valid;
    wire signed [10:0] sobel_gx,sobel_gy;
    wire [10:0] sobel_gradient;
    wire [1:0] sobel_direction;
    wire sv,sw,sh,sf;
    reg [7:0] sobel_gray_delay [0:2];
    reg [23:0] sobel_rgb_delay [0:2];

    gray_3x3_window #(
        .PIXEL_WIDTH(41), .IMAGE_WIDTH(IMAGE_WIDTH), .ADDR_WIDTH(ADDR_WIDTH),
        .VSYNC_ACTIVE_LEVEL(VSYNC_ACTIVE_LEVEL)
    ) u_window_sobel (
        .clk(clk),.rst_n(rst_n),
        .in_pixel({gw,gaussian_rgb_delay[1],gaussian_gray_delay[1],gaussian_pixel}),
        .in_valid(gv),.in_hsync(gh),.in_vsync(gf),
        .out_p11(c11),.out_p12(c12),.out_p13(c13),
        .out_p21(c21),.out_p22(c22),.out_p23(c23),
        .out_p31(c31),.out_p32(c32),.out_p33(c33),
        .out_valid(cv),.out_window_valid(cw),.out_hsync(ch),.out_vsync(cf)
    );
    assign c_all_valid = cw && c11[40] && c12[40] && c13[40] &&
                         c21[40] && c22[40] && c23[40] &&
                         c31[40] && c32[40] && c33[40];

    sobel_3x3 u_sobel (
        .clk(clk),.rst_n(rst_n),
        .in_p11(c11[7:0]),.in_p12(c12[7:0]),.in_p13(c13[7:0]),
        .in_p21(c21[7:0]),.in_p22(c22[7:0]),.in_p23(c23[7:0]),
        .in_p31(c31[7:0]),.in_p32(c32[7:0]),.in_p33(c33[7:0]),
        .in_valid(cv),.in_window_valid(c_all_valid),.in_hsync(ch),.in_vsync(cf),
        .out_gx(sobel_gx),.out_gy(sobel_gy),.out_gradient(sobel_gradient),
        .out_direction(sobel_direction),.out_valid(sv),.out_window_valid(sw),
        .out_hsync(sh),.out_vsync(sf)
    );

    // D：梯度窗口和非极大值抑制。
    wire [45:0] d11,d12,d13,d21,d22,d23,d31,d32,d33;
    wire dv,dw,dh,df;
    wire d_all_valid;
    wire [10:0] nms_gradient;
    wire nv,nw,nh,nf;
    reg [7:0] nms_gray_delay;
    reg [23:0] nms_rgb_delay;
    reg [10:0] sobel_bypass_magnitude; // 与NMS输出同坐标、同拍
    reg [1:0] sobel_bypass_class;
    reg sobel_bypass_edge;

    gray_3x3_window #(
        .PIXEL_WIDTH(46), .IMAGE_WIDTH(IMAGE_WIDTH), .ADDR_WIDTH(ADDR_WIDTH),
        .VSYNC_ACTIVE_LEVEL(VSYNC_ACTIVE_LEVEL)
    ) u_window_nms (
        .clk(clk),.rst_n(rst_n),
        .in_pixel({sw,sobel_rgb_delay[2],sobel_gray_delay[2],sobel_direction,sobel_gradient}),
        .in_valid(sv),.in_hsync(sh),.in_vsync(sf),
        .out_p11(d11),.out_p12(d12),.out_p13(d13),
        .out_p21(d21),.out_p22(d22),.out_p23(d23),
        .out_p31(d31),.out_p32(d32),.out_p33(d33),
        .out_valid(dv),.out_window_valid(dw),.out_hsync(dh),.out_vsync(df)
    );
    assign d_all_valid = dw && d11[45] && d12[45] && d13[45] &&
                         d21[45] && d22[45] && d23[45] &&
                         d31[45] && d32[45] && d33[45];

    canny_nms u_nms (
        .clk(clk),.rst_n(rst_n),.in_g_mag(d22[10:0]),.in_direction(d22[12:11]),
        .in_g_n(d12[10:0]),.in_g_s(d32[10:0]),
        .in_g_w(d21[10:0]),.in_g_e(d23[10:0]),
        .in_g_nw(d11[10:0]),.in_g_ne(d13[10:0]),
        .in_g_sw(d31[10:0]),.in_g_se(d33[10:0]),
        .in_valid(dv),.in_window_valid(d_all_valid),.in_hsync(dh),.in_vsync(df),
        .out_nms(nms_gradient),.out_valid(nv),.out_window_valid(nw),
        .out_hsync(nh),.out_vsync(nf)
    );

    // 双阈值分类。
    wire [1:0] threshold_class;
    wire [1:0] selected_class = canny_enable_frame ? threshold_class : sobel_bypass_class;
    wire tv,tw,th,tf;
    reg [7:0] threshold_gray_delay;
    reg [23:0] threshold_rgb_delay;

    canny_double_threshold u_double_threshold (
        .clk(clk),.rst_n(rst_n),.in_nms(nms_gradient),
        .in_high_threshold(in_high_threshold),.in_low_threshold(in_low_threshold),
        .in_valid(nv),.in_window_valid(nw),.in_hsync(nh),.in_vsync(nf),
        .out_class(threshold_class),.out_valid(tv),.out_window_valid(tw),
        .out_hsync(th),.out_vsync(tf)
    );

    // E/F：两级3×3局部滞后连接，弱边缘最多向外传播两个像素。
    wire [34:0] e11,e12,e13,e21,e22,e23,e31,e32,e33;
    wire ev,ew,eh,ef;
    wire e_all_valid;
    wire [1:0] hysteresis1_class;
    wire hysteresis1_edge,h1v,h1w,h1h,h1f;
    reg [7:0] hysteresis1_gray_delay;
    reg [23:0] hysteresis1_rgb_delay;

    gray_3x3_window #(
        .PIXEL_WIDTH(35), .IMAGE_WIDTH(IMAGE_WIDTH), .ADDR_WIDTH(ADDR_WIDTH),
        .VSYNC_ACTIVE_LEVEL(VSYNC_ACTIVE_LEVEL)
    ) u_window_hysteresis1 (
        .clk(clk),.rst_n(rst_n),
        .in_pixel({tw,threshold_rgb_delay,threshold_gray_delay,selected_class}),
        .in_valid(tv),.in_hsync(th),.in_vsync(tf),
        .out_p11(e11),.out_p12(e12),.out_p13(e13),
        .out_p21(e21),.out_p22(e22),.out_p23(e23),
        .out_p31(e31),.out_p32(e32),.out_p33(e33),
        .out_valid(ev),.out_window_valid(ew),.out_hsync(eh),.out_vsync(ef)
    );
    assign e_all_valid = ew && e11[34] && e12[34] && e13[34] &&
                         e21[34] && e22[34] && e23[34] &&
                         e31[34] && e32[34] && e33[34];

    canny_hysteresis u_hysteresis1 (
        .clk(clk),.rst_n(rst_n),
        .in_c11(e11[1:0]),.in_c12(e12[1:0]),.in_c13(e13[1:0]),
        .in_c21(e21[1:0]),.in_c22(e22[1:0]),.in_c23(e23[1:0]),
        .in_c31(e31[1:0]),.in_c32(e32[1:0]),.in_c33(e33[1:0]),
        .in_valid(ev),.in_window_valid(e_all_valid),.in_hsync(eh),.in_vsync(ef),
        .out_class(hysteresis1_class),.out_edge(hysteresis1_edge),
        .out_valid(h1v),.out_window_valid(h1w),.out_hsync(h1h),.out_vsync(h1f)
    );

    wire [34:0] f11,f12,f13,f21,f22,f23,f31,f32,f33;
    wire fv,fw,fh,ff;
    wire f_all_valid;
    wire [1:0] hysteresis2_class;
    wire hysteresis2_edge,h2v,h2w,h2h,h2f;
    reg [7:0] hysteresis2_gray_delay;
    reg [23:0] hysteresis2_rgb_delay;

    gray_3x3_window #(
        .PIXEL_WIDTH(35), .IMAGE_WIDTH(IMAGE_WIDTH), .ADDR_WIDTH(ADDR_WIDTH),
        .VSYNC_ACTIVE_LEVEL(VSYNC_ACTIVE_LEVEL)
    ) u_window_hysteresis2 (
        .clk(clk),.rst_n(rst_n),
        .in_pixel({h1w,hysteresis1_rgb_delay,hysteresis1_gray_delay,hysteresis1_class}),
        .in_valid(h1v),.in_hsync(h1h),.in_vsync(h1f),
        .out_p11(f11),.out_p12(f12),.out_p13(f13),
        .out_p21(f21),.out_p22(f22),.out_p23(f23),
        .out_p31(f31),.out_p32(f32),.out_p33(f33),
        .out_valid(fv),.out_window_valid(fw),.out_hsync(fh),.out_vsync(ff)
    );
    assign f_all_valid = fw && f11[34] && f12[34] && f13[34] &&
                         f21[34] && f22[34] && f23[34] &&
                         f31[34] && f32[34] && f33[34];

    canny_hysteresis #(.REPAIR_SHORT_GAP(REPAIR_SHORT_GAP)) u_hysteresis2 (
        .clk(clk),.rst_n(rst_n),
        .in_c11(f11[1:0]),.in_c12(f12[1:0]),.in_c13(f13[1:0]),
        .in_c21(f21[1:0]),.in_c22(f22[1:0]),.in_c23(f23[1:0]),
        .in_c31(f31[1:0]),.in_c32(f32[1:0]),.in_c33(f33[1:0]),
        .in_valid(fv),.in_window_valid(f_all_valid),.in_hsync(fh),.in_vsync(ff),
        .out_class(hysteresis2_class),.out_edge(hysteresis2_edge),
        .out_valid(h2v),.out_window_valid(h2w),.out_hsync(h2h),.out_vsync(h2f)
    );

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i=0;i<3;i=i+1) begin
                median_gray_delay[i] <= 0;
                median_rgb_delay[i] <= 0;
                sobel_gray_delay[i] <= 0;
                sobel_rgb_delay[i] <= 0;
            end
            for (i=0;i<2;i=i+1) begin
                gaussian_gray_delay[i] <= 0;
                gaussian_rgb_delay[i] <= 0;
            end
            nms_gray_delay <= 0;
            sobel_bypass_magnitude <= 0;
            sobel_bypass_class <= 0;
            sobel_bypass_edge <= 0;
            nms_rgb_delay <= 0;
            threshold_gray_delay <= 0;
            threshold_rgb_delay <= 0;
            hysteresis1_gray_delay <= 0;
            hysteresis1_rgb_delay <= 0;
            hysteresis2_gray_delay <= 0;
            hysteresis2_rgb_delay <= 0;
        end else begin
            median_gray_delay[0] <= (av && aw) ? a22[7:0] : 0;
            median_rgb_delay[0] <= (av && aw) ? a22[31:8] : 0;
            median_gray_delay[1] <= median_gray_delay[0];
            median_gray_delay[2] <= median_gray_delay[1];
            median_rgb_delay[1] <= median_rgb_delay[0];
            median_rgb_delay[2] <= median_rgb_delay[1];
            gaussian_gray_delay[0] <= (bv && b_all_valid) ? b22[15:8] : 0;
            gaussian_rgb_delay[0] <= (bv && b_all_valid) ? b22[39:16] : 0;
            gaussian_gray_delay[1] <= gaussian_gray_delay[0];
            gaussian_rgb_delay[1] <= gaussian_rgb_delay[0];
            sobel_gray_delay[0] <= (cv && c_all_valid) ? c22[15:8] : 0;
            sobel_rgb_delay[0] <= (cv && c_all_valid) ? c22[39:16] : 0;
            sobel_gray_delay[1] <= sobel_gray_delay[0];
            sobel_gray_delay[2] <= sobel_gray_delay[1];
            sobel_rgb_delay[1] <= sobel_rgb_delay[0];
            sobel_rgb_delay[2] <= sobel_rgb_delay[1];
            nms_gray_delay <= (dv && d_all_valid) ? d22[20:13] : 0;
            sobel_bypass_magnitude <= (dv && d_all_valid) ? d22[10:0] : 0;
            sobel_bypass_class <= (nv && nw && sobel_bypass_magnitude >= in_high_threshold) ? 2'd2 : 2'd0;
            sobel_bypass_edge <= fv && f_all_valid && (f22[1:0] == 2'd2);
            nms_rgb_delay <= (dv && d_all_valid) ? d22[44:21] : 0;
            threshold_gray_delay <= nw ? nms_gray_delay : 0;
            threshold_rgb_delay <= nw ? nms_rgb_delay : 0;
            hysteresis1_gray_delay <= (ev && e_all_valid) ? e22[9:2] : 0;
            hysteresis1_rgb_delay <= (ev && e_all_valid) ? e22[33:10] : 0;
            hysteresis2_gray_delay <= (fv && f_all_valid) ? f22[9:2] : 0;
            hysteresis2_rgb_delay <= (fv && f_all_valid) ? f22[33:10] : 0;
        end
    end

    // 仅后处理显示边缘；轮廓尺寸测量仍从独立原图分支取得，不用膨胀结果测量。
    wire morph_edge;
    assign out_edge = morph_edge ? 8'hff : 8'h00;
    edge_morphology_pipeline #(
        .IMAGE_WIDTH(IMAGE_WIDTH),.ADDR_WIDTH(ADDR_WIDTH),
        .MODE(MORPH_MODE),.KERNEL_SHAPE(MORPH_KERNEL_SHAPE),
        .VSYNC_ACTIVE_LEVEL(VSYNC_ACTIVE_LEVEL)
    ) u_morphology (
        .clk(clk),.rst_n(rst_n),.in_red(hysteresis2_rgb_delay[23:16]),
        .in_green(hysteresis2_rgb_delay[15:8]),.in_blue(hysteresis2_rgb_delay[7:0]),
        .in_gray(hysteresis2_gray_delay),
        .in_edge(canny_enable_frame ? hysteresis2_edge : sobel_bypass_edge),
        .in_valid(h2v),.in_window_valid(h2w),.in_hsync(h2h),.in_vsync(h2f),
        .out_red(out_red),.out_green(out_green),.out_blue(out_blue),
        .out_gray(out_gray),.out_edge(morph_edge),.out_valid(out_valid),
        .out_window_valid(out_window_valid),.out_hsync(out_hsync),.out_vsync(out_vsync)
    );
endmodule
