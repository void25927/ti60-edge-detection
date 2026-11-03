`timescale 1ns/1ps

// Ti60图像边缘检测系统顶层
// 文件前部保留厂家 Demo 底层代码，负责时钟、DDR3、SC2210、MIPI和HDMI。
// 文件后部为项目新增代码。
module Ti60_top
(
	// 系统时钟
	input 			clk_24m,
	output 			sys_pll_rstn_o,
	input 			clk_sys,			// 96 MHz系统时钟
	input 			clk_pixel_2x,		// 148.5 MHz像素时钟
	input 			clk_pixel_10x,		// 742.5 MHz HDMI串行时钟
	input 			sys_pll_lock,

	// DDR3时钟
	output 			ddr_pll_rstn_o, 
	input 			tdqss_clk,			
	input 			core_clk,
	input 			tac_clk,			
	input 			twd_clk,			
	input 			ddr_pll_lock,

	// DDR3 PLL相移控制
	output 	[2:0] 	shift,
	output 	[4:0] 	shift_sel,
	output 			shift_ena,

	// DDR3存储器接口
	output 	[15:0] 	addr,
	output 	[2:0] 	ba,
	output 			we,
	output 			reset,
	output 			ras,
	output 			cas,
	output 			odt,
	output 			cke,
	output 			cs,
	
	// DDR3数据接口
	input 	[15:0] 	i_dq_hi,
	input 	[15:0] 	i_dq_lo,
	
	output 	[15:0] 	o_dq_hi,
	output 	[15:0] 	o_dq_lo,
	output 	[15:0] 	o_dq_oe,
	
	// DDR3数据掩码
	output 	[1:0] 	o_dm_hi,
	output 	[1:0] 	o_dm_lo,
	
	// DDR3数据选通信号
	input 	[1:0] 	i_dqs_hi,
	input 	[1:0] 	i_dqs_lo,
	
//	input 	[1:0] 	i_dqs_n_hi,
//	input 	[1:0] 	i_dqs_n_lo,
	
	output 	[1:0] 	o_dqs_hi,
	output 	[1:0] 	o_dqs_lo,
	
//	output 	[1:0] 	o_dqs_n_hi,
//	output 	[1:0] 	o_dqs_n_lo,
	
	output 	[1:0] 	o_dqs_oe,
	output 	[1:0] 	o_dqs_n_oe,
	
	// DDR3差分时钟
	output 			clk_p_hi, 
	output 			clk_p_lo, 
	output 			clk_n_hi, 
	output 			clk_n_lo, 

	// SC2210控制与I2C
	output 			csi_ctl0_o,
	output 			csi_ctl0_oe,
	input 			csi_ctl0_i,
	
	output 			csi_ctl1_o,
	output 			csi_ctl1_oe,
	input 			csi_ctl1_i,
	
	output 			csi_scl_o,
	output 			csi_scl_oe,
	input 			csi_scl_i,
	
	output 			csi_sda_o,
	output 			csi_sda_oe,
	input 			csi_sda_i,

	// MIPI CSI-2时钟通道
	input 			csi_rxc_lp_p_i,
	input 			csi_rxc_lp_n_i,
	output 			csi_rxc_hs_en_o,
	output 			csi_rxc_hs_term_en_o,
	input 			csi_rxc_i,

	// MIPI CSI-2数据通道0
	output 			csi_rxd0_rst_o,
	output 			csi_rxd0_hs_en_o,
	output 			csi_rxd0_hs_term_en_o,
	
	input 			csi_rxd0_lp_p_i,
	input 			csi_rxd0_lp_n_i,
	input 	[7:0] 	csi_rxd0_hs_i,

	// MIPI CSI-2数据通道1
	output 			csi_rxd1_rst_o,
	output 			csi_rxd1_hs_en_o,
	output 			csi_rxd1_hs_term_en_o,
	
	input 			csi_rxd1_lp_n_i,
	input 			csi_rxd1_lp_p_i,
	input 	[7:0] 	csi_rxd1_hs_i,

	// MIPI CSI-2数据通道2
	output 			csi_rxd2_rst_o,
	output 			csi_rxd2_hs_en_o,
	output 			csi_rxd2_hs_term_en_o,
	
	input 			csi_rxd2_lp_p_i,
	input 			csi_rxd2_lp_n_i,
	input 	[7:0] 	csi_rxd2_hs_i,

	// MIPI CSI-2数据通道3
	output 			csi_rxd3_rst_o,
	output 			csi_rxd3_hs_en_o,
	output 			csi_rxd3_hs_term_en_o,
	
	input 			csi_rxd3_lp_p_i,
	input 			csi_rxd3_lp_n_i,
	input 	[7:0] 	csi_rxd3_hs_i,

	// 板载独立按键，低电平按下
	input   [1:0]   key_data,

    // 扩展板两键、两灯；P4-39/40输入，P4-37/38输出。
    input wire ex_key_up_n, input wire ex_key_down_n,
    output wire ex_led_run, output wire ex_led_alarm,

	// 板载状态指示灯
	output 	[5:0] 	led_o,

	// HDMI TMDS接口
	output 			hdmi_txc_oe,
	output 			hdmi_txd0_oe,
	output 			hdmi_txd1_oe,
	output 			hdmi_txd2_oe,
	
	output 			hdmi_txc_rst_o,
	output 			hdmi_txd0_rst_o,
	output 			hdmi_txd1_rst_o,
	output 			hdmi_txd2_rst_o,
	
	output 	[9:0] 	hdmi_txc_o,
	output 	[9:0] 	hdmi_txd0_o,
	output 	[9:0] 	hdmi_txd1_o,
	output 	[9:0] 	hdmi_txd2_o
);

	//==========================================================================
	// 顶层内部信号声明
	// 先声明DDR3内部信号，再声明厂家底层与项目模块之间的视频流信号。
	//==========================================================================
	
	wire 	[1:0] 	i_dqs_n_hi;
	wire 	[1:0] 	i_dqs_n_lo;
	wire 	[1:0] 	o_dqs_n_hi;
	wire 	[1:0] 	o_dqs_n_lo;

	// 项目视频流接口信号，具体处理逻辑位于文件后部
    wire w_csi_rx_vsync0,w_csi_rx_hsync0,w_csi_rx_dvalid;
    wire [63:0] w_csi_rx_data;
    wire w_rgb_vsync,w_rgb_hsync,w_rgb_href;
    wire [31:0] snapshot_freeze_id,display_frame_id;
    wire display_frame_valid,history_fault;
	reg  [1:0]  rstn_csi_sync = 2'b00;
	wire        rstn_csi = rstn_csi_sync[1];
	wire        csi_frame_vsync = w_csi_rx_vsync0;
	wire        csi_frame_valid = w_csi_rx_hsync0 && w_csi_rx_dvalid;
	wire [63:0] csi_frame_raw8 = {w_csi_rx_data[7:0], w_csi_rx_data[15:8], w_csi_rx_data[23:16], w_csi_rx_data[31:24], w_csi_rx_data[39:32], w_csi_rx_data[47:40], w_csi_rx_data[55:48], w_csi_rx_data[63:56]};
	wire [31:0] crop_frame_raw8;
	wire        crop_frame_valid;
	wire        crop_frame_hsync;
	wire        crop_frame_vsync;
	wire [7:0]  ddr_raw8;
	wire        ddr_raw8_valid;
	wire [12:0] ddr_raw8_count;
	wire        ddr_raw8_request;
	wire [7:0]  w_source_raw;
	wire        w_source_valid, w_source_hsync, w_source_vsync;
	wire [7:0]  w_alg_gray, w_alg_edge;
	wire [7:0]  w_alg_red, w_alg_green, w_alg_blue;
	wire        w_alg_valid, w_alg_window_valid, w_alg_hsync, w_alg_vsync;
	wire [7:0]  w_overlay_red, w_overlay_green, w_overlay_blue;
	wire        w_overlay_valid, w_overlay_hsync, w_overlay_vsync;
	reg  [7:0]  r_alg_gray_d, r_alg_edge_d;
	reg         r_alg_window_valid_d;
	wire [7:0]  w_display_pixel;
	wire [23:0] w_display_rgb;
	wire        w_display_valid;
	wire        w_display_hsync;
	wire        w_display_vsync;
	wire        w_display_window_valid;
	wire        w_display_region_edge;
	wire        w_display_underflow;
	wire        w_display_frame_error;
	wire        w_function_pressed;
	wire        w_function_down_pulse;
	wire        w_function_up_pulse;
	wire        w_function_short_pulse;
	wire        w_function_long_pulse;
	wire        w_adjust_pressed;
	wire        w_adjust_down_pulse;
	wire        w_adjust_up_pulse;
	wire        w_adjust_short_pulse;
	wire        w_adjust_long_pulse;
	wire [10:0] w_high_threshold;
	wire [10:0] w_low_threshold;
	wire [10:0] w_pending_high_threshold;
	wire [1:0]  w_system_mode;
	wire        w_display_mode_request;
	wire        w_display_mode_active;
	wire [1:0]  w_ddr_mode_request;
	wire [2:0]  w_replay_offset;
	wire        w_threshold_adjust_enable;
	wire        w_threshold_add_pulse;
	wire        w_threshold_sub_pulse;
	wire [1:0]  w_ddr_mode_active;
	wire [3:0]  w_ddr_write_index;
	wire [3:0]  w_ddr_read_index;
	wire [3:0]  w_ddr_history_count;
	wire [23:0] w_ui_rgb;
	wire        w_ui_valid;
	wire        w_ui_hsync;
	wire        w_ui_vsync;
	reg         r_rgb_vsync_d = 1'b1;
	wire        w_frame_start = r_rgb_vsync_d && !w_rgb_vsync;
	// 自动曝光邮箱和白平衡视频接口。
	wire [7:0] w_wb_r, w_wb_g, w_wb_b;
	wire w_wb_valid, w_wb_hsync, w_wb_vsync;
	wire [9:0] w_wb_red_gain, w_wb_blue_gain;
	wire [15:0] w_ae_exposure;
	wire [6:0] w_ae_gain;
	wire w_ae_request, w_ae_ack, w_ae_owned, w_ae_fault, w_ae_done, w_auto_frame_ok;
	wire w_init_scl, w_init_sda, w_init_oe;
	wire w_ae_scl, w_ae_sda, w_ae_oe;
	reg [1:0] r_ae_fault_sync;
	//==========================================================================
	// 第一部分：厂家 Demo 底层代码（一般不修改）
	// 包含时钟复位、DDR3、SC2210配置、MIPI接收、帧存取和HDMI输出。
	//==========================================================================

	// DDR3差分时钟和系统复位
	assign clk_p_hi = 1'b0;	// DDR3时钟需要180度相移
	assign clk_p_lo = 1'b1;
	assign clk_n_hi = 1'b1;
	assign clk_n_lo = 1'b0; 
	
	// 系统与DDR3 PLL复位控制
	assign sys_pll_rstn_o = 1'b1;
	assign ddr_pll_rstn_o = sys_pll_lock; 
	wire 			w_pll_lock = sys_pll_lock && ddr_pll_lock;
	
	// 分别产生系统时钟域和像素时钟域复位
	reg 			rstn_sys = 0, rstn_pixel = 0; 
	wire 			rst_sys = ~rstn_sys, rst_pixel = ~rstn_pixel; 

	always @(posedge clk_sys or negedge w_pll_lock) begin if(~w_pll_lock) rstn_sys <= 0; else rstn_sys <= 1; end
	always @(posedge clk_pixel_2x or negedge w_pll_lock) begin if(~w_pll_lock) rstn_pixel <= 0; else rstn_pixel <= 1; end
	
	localparam 	CLOCK_MAIN 	= 96000000;
	//-------------------------------------------------------------------------
	// DDR3控制器与AXI总线
	//-------------------------------------------------------------------------
	wire			w_ddr3_ui_clk = clk_sys;
	wire			w_ddr3_ui_rst = rst_sys;
	wire			w_ddr3_ui_areset = rst_sys;
	wire			w_ddr3_ui_aresetn = rstn_sys;
	

	// DDR3控制器AXI通道
	wire	[3:0] 	w_ddr3_awid;
	wire	[31:0]	w_ddr3_awaddr;
	wire	[7:0]		w_ddr3_awlen;
	wire			w_ddr3_awvalid;
	wire			w_ddr3_awready;
	
	wire 	[3:0]  	w_ddr3_wid;
	wire 	[127:0] 	w_ddr3_wdata;
	wire 	[15:0]	w_ddr3_wstrb;
	wire			w_ddr3_wlast;
	wire			w_ddr3_wvalid;
	wire			w_ddr3_wready;
	
	wire 	[3:0] 	w_ddr3_bid;
	wire 	[1:0] 	w_ddr3_bresp;
	wire			w_ddr3_bvalid;
	wire			w_ddr3_bready;
	
	wire	[3:0] 	w_ddr3_arid;
	wire	[31:0]	w_ddr3_araddr;
	wire	[7:0]		w_ddr3_arlen;
	wire			w_ddr3_arvalid;
	wire			w_ddr3_arready;
	
	wire 	[3:0] 	w_ddr3_rid;
	wire 	[127:0] 	w_ddr3_rdata;
	wire			w_ddr3_rlast;
	wire			w_ddr3_rvalid;
	wire			w_ddr3_rready;
	wire 	[1:0] 	w_ddr3_rresp;
	
	
	// AXI读写命令通道
	wire 	[3:0] 	w_ddr3_aid;
	wire 	[31:0] 	w_ddr3_aaddr;
	wire 	[7:0]  	w_ddr3_alen;
	wire 	[2:0]  	w_ddr3_asize;
	wire 	[1:0]  	w_ddr3_aburst;
	wire 	[1:0]  	w_ddr3_alock;
	wire			w_ddr3_avalid;
	wire			w_ddr3_aready;
	wire			w_ddr3_atype;
	
	wire 			w_ddr3_cal_done, w_ddr3_cal_pass; 
	
	// DDR3校准完成前禁止发起读写
	reg 			r_ddr_unlock = 0; 
	always @(posedge w_ddr3_ui_clk or negedge w_ddr3_ui_aresetn) begin
		if(~w_ddr3_ui_aresetn)
			r_ddr_unlock <= 0; 
		else
			r_ddr_unlock <= w_ddr3_cal_done; 
	end
	
	DdrCtrl ddr3_ctl_axi (	
		.core_clk		(core_clk),
		.tac_clk		(tac_clk),
		.twd_clk		(twd_clk),	
		.tdqss_clk		(tdqss_clk),
		
		.reset		(reset),
		.cs			(cs),
		.ras			(ras),
		.cas			(cas),
		.we			(we),
		.cke			(cke),    
		.addr			(addr),
		.ba			(ba),
		.odt			(odt),
		
		.o_dm_hi		(o_dm_hi),
		.o_dm_lo		(o_dm_lo),
		
		.i_dq_hi		(i_dq_hi),
		.i_dq_lo		(i_dq_lo),
		.o_dq_hi		(o_dq_hi),
		.o_dq_lo		(o_dq_lo),
		.o_dq_oe		(o_dq_oe),
		
		.i_dqs_hi		(i_dqs_hi),
		.i_dqs_lo		(i_dqs_lo),
		.i_dqs_n_hi		(i_dqs_n_hi),
		.i_dqs_n_lo		(i_dqs_n_lo),
		.o_dqs_hi		(o_dqs_hi),
		.o_dqs_lo		(o_dqs_lo),
		.o_dqs_n_hi		(o_dqs_n_hi),
		.o_dqs_n_lo		(o_dqs_n_lo),
		.o_dqs_oe		(o_dqs_oe),
		.o_dqs_n_oe		(),				// 负端输出使能由下方统一连接
		
		.clk			(w_ddr3_ui_clk),
		.reset_n		(w_ddr3_ui_aresetn),
		
		.axi_avalid		(w_ddr3_avalid),		// DDR3解锁后才允许命令进入
		.axi_aready		(w_ddr3_aready),
		.axi_aaddr		(w_ddr3_aaddr),
		.axi_aid		(w_ddr3_aid),
		.axi_alen		(w_ddr3_alen),
		.axi_asize		(w_ddr3_asize),
		.axi_aburst		(w_ddr3_aburst),
		.axi_alock		(w_ddr3_alock),
		.axi_atype		(w_ddr3_atype),
		
		.axi_wid		(w_ddr3_wid),
		.axi_wvalid		(w_ddr3_wvalid),
		.axi_wready		(w_ddr3_wready),
		.axi_wdata		(w_ddr3_wdata),
		.axi_wstrb		(w_ddr3_wstrb),
		.axi_wlast		(w_ddr3_wlast),
		
		.axi_bvalid		(w_ddr3_bvalid),
		.axi_bready		(w_ddr3_bready),
		.axi_bid		(w_ddr3_bid),
		.axi_bresp		(w_ddr3_bresp),
		
		.axi_rvalid		(w_ddr3_rvalid),
		.axi_rready		(w_ddr3_rready),
		.axi_rdata		(w_ddr3_rdata),
		.axi_rid		(w_ddr3_rid),
		.axi_rresp		(w_ddr3_rresp),
		.axi_rlast		(w_ddr3_rlast),
		
		.shift		(shift),
		.shift_sel		(),
		.shift_ena		(shift_ena),
		
		.cal_ena		(1'b1),
		.cal_done		(w_ddr3_cal_done),
		.cal_pass		(w_ddr3_cal_pass)
	);
	// 负端DQS输出使能与正端保持一致
	assign o_dqs_n_oe = o_dqs_oe; 
	
	assign shift_sel = 5'b00100; 		// DDR采样时钟固定选择PLLOUT[2]
	
	
    // 视频与截图共用DDR，命令、数据和真实应答由同一事务所有权路由。
    wire [31:0] snap_awaddr,snap_araddr;
    wire [7:0] snap_awlen,snap_arlen;
    wire snap_awvalid,snap_arvalid,snap_wvalid,snap_wlast,snap_bready,snap_rready;
    wire [127:0] snap_wdata,video_wdata,client_rdata;
    wire [15:0] snap_wstrb,video_wstrb;
    wire video_wvalid,video_wlast;
    wire [5:0] client_ready;
    wire [2:0] client_wready,client_bvalid,client_rvalid;
    wire [1:0] client_bresp,client_rresp;
    wire pair_awvalid,pair_arvalid,pair_wvalid,pair_wlast,pair_bready,pair_rready;
    wire [31:0] pair_awaddr,pair_araddr;
    wire [7:0] pair_awlen,pair_arlen;
    wire [127:0] pair_wdata;
    wire [10:0] pair_write_level;
    wire [9:0] pair_read_level;
    wire client_rlast,arbiter_fault;
    assign w_ddr3_awready=client_ready[0];
    assign w_ddr3_arready=client_ready[1];
    paired_video_arbiter u_video_snapshot_arbiter(
      .clk(w_ddr3_ui_clk),.rst_n(!w_ddr3_ui_rst),
      .request_valid({pair_arvalid,pair_awvalid,snap_arvalid,snap_awvalid,w_ddr3_arvalid,w_ddr3_awvalid}&{6{r_ddr_unlock}}),
      .urgent({pair_read_level<10'd256,pair_write_level>=11'd512,2'b00,2'b11}),
      .request_ready(client_ready),
      .request_address({pair_araddr,pair_awaddr,snap_araddr,snap_awaddr,w_ddr3_araddr,w_ddr3_awaddr}),
      .request_length({pair_arlen,pair_awlen,snap_arlen,snap_awlen,w_ddr3_arlen,w_ddr3_awlen}),
      .write_valid({pair_wvalid,snap_wvalid,video_wvalid}),.write_ready(client_wready),
      .write_data({pair_wdata,snap_wdata,video_wdata}),.write_strobe({16'hffff,snap_wstrb,video_wstrb}),
      .write_last({pair_wlast,snap_wlast,video_wlast}),.response_valid(client_bvalid),
      .response_ready({pair_bready,snap_bready,1'b1}),.read_valid(client_rvalid),.read_ready({pair_rready,snap_rready,1'b1}),
      .read_data(client_rdata),.read_last(client_rlast),.response_code(client_bresp),.read_code(client_rresp),
      .avalid(w_ddr3_avalid),.aready(w_ddr3_aready),.aaddr(w_ddr3_aaddr),
      .alen(w_ddr3_alen),.aid(w_ddr3_aid),.atype(w_ddr3_atype),
      .wvalid(w_ddr3_wvalid),.wready(w_ddr3_wready),.wdata(w_ddr3_wdata),
      .wstrb(w_ddr3_wstrb),.wlast(w_ddr3_wlast),.wid(w_ddr3_wid),
      .bvalid(w_ddr3_bvalid),.bready(w_ddr3_bready),.bid(w_ddr3_bid),.bresp(w_ddr3_bresp),
      .rvalid(w_ddr3_rvalid),.rready(w_ddr3_rready),.rdata(w_ddr3_rdata),
      .rid(w_ddr3_rid),.rresp(w_ddr3_rresp),.rlast(w_ddr3_rlast),.fault(arbiter_fault));
	
	assign w_ddr3_asize = 4; 		// 固定128位，即16字节
	assign w_ddr3_aburst = 1; 
	assign w_ddr3_alock = 0; 
	
	assign led_o[1:0] = {w_ddr3_cal_pass, w_ddr3_cal_done}; 
	
	//-------------------------------------------------------------------------
	// SC2210上电寄存器配置
	//-------------------------------------------------------------------------
	// I2C控制器按配置表写入SC2210寄存器
	wire            [ 8:0]          sc2210_i2c_config_index;
	wire            [23:0]          sc2210_i2c_config_data;
	wire            [ 8:0]          sc2210_i2c_config_size;
	wire                            sc2210_i2c_config_done;
	
	i2c_timing_ctrl_reg16_dat8_wronly
	#(
	    .CLK_FREQ           (CLOCK_MAIN),                              // 96 MHz系统时钟
	    .I2C_FREQ           (50_000    )                               // 50 kHz I2C时钟
	) u_i2c_timing_ctrl_16bit (
	    // 全局时钟与复位
	    .clk                (clk_sys                 ),                          // 96 MHz
	    .rst_n              (rstn_sys                ),                          // 低电平复位

	    // I2C接口
	    .i2c_sclk           (w_init_scl              ),                          // 初始化I2C时钟
	    .i2c_sdat_IN        (csi_sda_i               ),
	    .i2c_sdat_OUT       (w_init_sda              ),
	    .i2c_sdat_OE        (w_init_oe               ),

	    // SC2210配置表接口
	    .i2c_config_index   (sc2210_i2c_config_index        ),                     // 当前配置项索引
	    .i2c_config_data    ({8'h60, sc2210_i2c_config_data}),                     // 器件地址和寄存器数据
	    .i2c_config_size    (sc2210_i2c_config_size         ),                     // 配置项总数
	    .i2c_config_done    (sc2210_i2c_config_done         )                      // 配置完成
	);
	assign csi_scl_oe = 1; 
	// 初始化结束并等待STOP完成后，运行时主机独占I2C总线。
	assign csi_scl_o = w_ae_owned ? w_ae_scl : w_init_scl;
	assign csi_sda_o = w_ae_owned ? w_ae_sda : w_init_sda;
	assign csi_sda_oe = w_ae_owned ? w_ae_oe : w_init_oe;

	// SC2210 1920×1080、4 Lane配置表
	I2C_SC2210_19201080_4Lanes_Config u_I2C_SC2210_19201080_4Lanes_Config
	(
	    .LUT_INDEX  (sc2210_i2c_config_index   ),
	    .LUT_DATA   (sc2210_i2c_config_data    ),
	    .LUT_SIZE   (sc2210_i2c_config_size    )
	);

	// SC2210控制脚保持输入状态
	assign csi_ctl0_oe = 1'b0;
	assign csi_ctl1_oe = 1'b0;

	//-------------------------------------------------------------------------
	// MIPI CSI-2四通道RAW8接收
	//-------------------------------------------------------------------------
	// 时钟通道不反相；数据通道通过LP交换和HS位翻转实现反相
	localparam 	CSI_RXD_INV 	= 4'b1111; 
	localparam 	CSI_DATA_WIDTH 	= 32; 			

	// 接收模块输出RAW8像素和视频同步信号
	wire 			w_csi_rx_clk; 
	wire 	[47:0] 	w_csi_rx_data_rel_raw; 

	wire 	[7:0] 	w_mipi_d0 = (CSI_RXD_INV[0] ? 8'hFF : 8'h00) ^ csi_rxd0_hs_i; 
	wire 	[7:0] 	w_mipi_d1 = (CSI_RXD_INV[1] ? 8'hFF : 8'h00) ^ csi_rxd1_hs_i; 
	wire 	[7:0] 	w_mipi_d2 = (CSI_RXD_INV[2] ? 8'hFF : 8'h00) ^ csi_rxd2_hs_i; 
	wire 	[7:0] 	w_mipi_d3 = (CSI_RXD_INV[3] ? 8'hFF : 8'h00) ^ csi_rxd3_hs_i; 
	MIPIRx4LaneFre mipi0_rx (
		.sclk_i			(clk_sys), 
		.srst_i			(rst_sys), 
		
		.mipi_rx_byteclk_i	(csi_rxc_i), 
		.mipi_rx_d0_i		({w_mipi_d0[0], w_mipi_d0[1], w_mipi_d0[2], w_mipi_d0[3], w_mipi_d0[4], w_mipi_d0[5], w_mipi_d0[6], w_mipi_d0[7]}), 
		.mipi_rx_d1_i		({w_mipi_d1[0], w_mipi_d1[1], w_mipi_d1[2], w_mipi_d1[3], w_mipi_d1[4], w_mipi_d1[5], w_mipi_d1[6], w_mipi_d1[7]}), 
		.mipi_rx_d2_i		({w_mipi_d2[0], w_mipi_d2[1], w_mipi_d2[2], w_mipi_d2[3], w_mipi_d2[4], w_mipi_d2[5], w_mipi_d2[6], w_mipi_d2[7]}), 
		.mipi_rx_d3_i		({w_mipi_d3[0], w_mipi_d3[1], w_mipi_d3[2], w_mipi_d3[3], w_mipi_d3[4], w_mipi_d3[5], w_mipi_d3[6], w_mipi_d3[7]}), 
		.mipi_rx_clk_lp_p_i	(csi_rxc_lp_p_i), 
		.mipi_rx_clk_lp_n_i	(csi_rxc_lp_n_i), 
		.mipi_rx_d0_lp_p_i	(CSI_RXD_INV[0] ? csi_rxd0_lp_n_i : csi_rxd0_lp_p_i), 
		.mipi_rx_d0_lp_n_i	(CSI_RXD_INV[0] ? csi_rxd0_lp_p_i : csi_rxd0_lp_n_i), 
		.mipi_rx_rst_o		(), 
		.mipi_rx_rst_n_o		(), 
		.mipi_rx_clk_hs_en_o	(csi_rxc_hs_en_o), 
		.mipi_rx_dat_hs_en_o	(csi_rxd0_hs_en_o), 
		.mipi_rx_clk_term_en_o	(csi_rxc_hs_term_en_o), 
		.mipi_rx_dat_term_en_o	(csi_rxd0_hs_term_en_o), 
		
		.CLK				(w_csi_rx_clk), 
		.VSYNC			(w_csi_rx_vsync0), 
		.HSYNC			(w_csi_rx_hsync0), 
		.DE				(w_csi_rx_dvalid), 
		.DAT				(w_csi_rx_data_rel_raw)
	);
	assign w_csi_rx_data = {2{w_csi_rx_data_rel_raw[47:40], w_csi_rx_data_rel_raw[35:28], w_csi_rx_data_rel_raw[23:16], w_csi_rx_data_rel_raw[11:4]}}; 
	assign {csi_rxd3_hs_en_o, csi_rxd2_hs_en_o, csi_rxd1_hs_en_o} = {3{csi_rxd0_hs_en_o}}; 
	assign {csi_rxd3_hs_term_en_o, csi_rxd2_hs_term_en_o, csi_rxd1_hs_term_en_o} = {3{csi_rxd0_hs_term_en_o}}; 
	
	
	// MIPI帧计数与状态指示
	reg 	[5:0]		r_csi_fv_o = 0; 
	reg 	[1:0] 	r_csi_rx_vsync0_in = 0; 
	always @(posedge w_csi_rx_clk) begin
		r_csi_rx_vsync0_in <= {r_csi_rx_vsync0_in, w_csi_rx_vsync0}; 
		r_csi_fv_o <= r_csi_fv_o + ((r_csi_rx_vsync0_in == 2'b01) ? 1 : 0); 
	end
	assign led_o[4] = r_csi_fv_o[5];
	assign led_o[5] = 1'b1; // 并行CMOS接口未使用，保持指示灯关闭

	//-------------------------------------------------------------------------
	// DDR3视频帧读写控制
	//-------------------------------------------------------------------------
	wire                            lcd_de;
	wire                            lcd_hs;      
	wire                            lcd_vs;
	wire 					  lcd_request;

	assign w_ddr3_awid = 0; 
	
	wire 	[7:0] 	w_axi_tp; 
	
    // 12个2MiB原图槽共24MiB；快照区仍从32MiB开始，互不重叠。
	axi4_ctrl #(.C_RD_END_ADDR(1920 * 1080),.C_BUF_SIZE(21),.HISTORY_FRAMES(8),.FRAME_SLOTS(12), .C_W_WIDTH(CSI_DATA_WIDTH), .C_R_WIDTH(8), .C_ID_LEN(4)) u_axi4_ctrl (

		.axi_clk        (w_ddr3_ui_clk            ),
		.axi_reset      (w_ddr3_ui_rst            ),

		.axi_awaddr     (w_ddr3_awaddr       ),
		.axi_awlen      (w_ddr3_awlen        ),
		.axi_awvalid    (w_ddr3_awvalid      ),
		.axi_awready    (w_ddr3_awready      ),

		.axi_wdata      (video_wdata        ),
		.axi_wstrb      (video_wstrb        ),
		.axi_wlast      (video_wlast        ),
		.axi_wvalid     (video_wvalid       ),
		.axi_wready     (client_wready[0]   ),

		.axi_bid        (4'd0),
		.axi_bresp      (client_bresp),
		.axi_bvalid     (client_bvalid[0]),

		.axi_arid       (w_ddr3_arid         ),
		.axi_araddr     (w_ddr3_araddr       ),
		.axi_arlen      (w_ddr3_arlen        ),
		.axi_arvalid    (w_ddr3_arvalid      ),
		.axi_arready    (w_ddr3_arready      ),

		.axi_rid        (w_ddr3_rid          ),
		.axi_rdata      (client_rdata),
		.axi_rresp      (client_rresp),
		.axi_rlast      (client_rlast),
		.axi_rvalid     (client_rvalid[0]),
		.axi_rready     (),

		.wframe_pclk    (w_csi_rx_clk          ),
		.wframe_vsync   (crop_frame_vsync),
		.wframe_data_en (crop_frame_valid),
		.wframe_data    (crop_frame_raw8),
		
		.rframe_pclk    (clk_pixel_2x            ),
		.rframe_vsync   (~lcd_vs             ),		// 上升沿刷新读帧FIFO
		.rframe_data_en (ddr_raw8_request        ),
		.rframe_data    (ddr_raw8                ),
		.rframe_data_valid(ddr_raw8_valid         ),
		.rframe_data_count(ddr_raw8_count         ),

		.frame_mode_request(w_ddr_mode_request     ),
		.replay_frame_offset(w_replay_offset       ),
		.frame_mode_active(w_ddr_mode_active       ),
		.frame_write_index(w_ddr_write_index       ),
		.frame_read_index (w_ddr_read_index        ),
		.frame_history_count(w_ddr_history_count   ),
        .freeze_frame_id(snapshot_freeze_id),
        .display_frame_id(display_frame_id),.display_frame_valid(display_frame_valid),.frame_fault(history_fault),
		
		.tp_o 		(w_axi_tp)
	);
	assign led_o[2] = 1'b1;
	assign led_o[3] = ~w_ae_fault; // 自动曝光连续I2C失败时点亮故障灯

	//-------------------------------------------------------------------------
	// HDMI 1920×1080显示时序
	//-------------------------------------------------------------------------
	
	lcd_driver u_lcd_driver
	(
	    // 全局时钟与复位
	    .clk        (clk_pixel_2x   ),
	    .rst_n      (rstn_pixel), 
	    
	    // 显示时序接口
	    .lcd_dclk   (               ),
	    .lcd_blank  (               ),
	    .lcd_sync   (               ),
	    .lcd_request(lcd_request    ), 	// 提前一个时钟请求像素
	    .lcd_hs     (lcd_hs         ),
	    .lcd_vs     (lcd_vs         ),
	    .lcd_en     (lcd_de         ),
	    .lcd_rgb    (),
	    
	    // 用户像素接口
	    .lcd_data   (48'd0)
	);

	// RAW8去马赛克并输出RGB888
	wire 	[7:0] 	w_rgb_r, w_rgb_g, w_rgb_b; 

	VIP_RAW8_RGB888 #(.IMG_HDISP(1920), .IMG_VDISP(1080)) bayer2rgb (
		.clk				(clk_pixel_2x),                // 像素时钟
		.rst_n			(rstn_pixel),                  // 低电平复位
	    
		.mirror			(0),

		// RAW8输入
		.per_frame_vsync		(w_source_vsync),
		.per_frame_href		(w_source_valid),
		.per_frame_hsync		(w_source_hsync),
		.per_img_RAW		(w_source_raw),

		.post_frame_vsync		(w_rgb_vsync),   // RGB场同步
		.post_frame_href		(w_rgb_href),    // RGB像素有效
		.post_frame_hsync		(w_rgb_hsync),   // RGB行同步
		.post_img_red		(w_rgb_r),          // 红色分量
		.post_img_green		(w_rgb_g),        // 绿色分量
		.post_img_blue		(w_rgb_b)          // 蓝色分量
	);

	//-------------------------------------------------------------------------
	// HDMI TMDS编码与输出
	//-------------------------------------------------------------------------
	// 将项目输出的8位灰度像素复制到RGB三个通道
	
	assign hdmi_txd0_rst_o = rst_pixel; 
	assign hdmi_txd1_rst_o = rst_pixel; 
	assign hdmi_txd2_rst_o = rst_pixel; 
	assign hdmi_txc_rst_o = rst_pixel; 
	
	assign hdmi_txd0_oe = 1'b1; 
	assign hdmi_txd1_oe = 1'b1; 
	assign hdmi_txd2_oe = 1'b1; 
	assign hdmi_txc_oe = 1'b1; 
	
	// HDMI发送模块
	rgb2dvi #(.ENABLE_OSERDES(0)) u_rgb2dvi 
	(
		.oe_i 		(1), 			// 始终使能输出
		.bitflip_i 		(4'b0000), 		// 不翻转时钟和数据通道
		
		.aRst			(1'b0), 
		.aRst_n		(1'b1), 
		
		.PixelClk		(clk_pixel_2x        ), // 148.5 MHz像素时钟
		.SerialClk		(     ),                // 本设计未使用外部串行时钟输入
		
		.vid_pVSync (w_ui_vsync),
		.vid_pHSync (w_ui_hsync),
		.vid_pVDE   (w_ui_valid),
		.vid_pData  (w_ui_rgb),
		
		.txc_o		(hdmi_txc_o), 
		.txd0_o		(hdmi_txd0_o), 
		.txd1_o		(hdmi_txd1_o), 
		.txd2_o		(hdmi_txd2_o)
	); 


	//==========================================================================
	// 第二部分：项目新增图像处理代码
	//==========================================================================

	// 白平衡在去马赛克后处理，数据及同步均延迟两级；冻结/回放时保持参数。
	video_auto_levels #(.FRAME_PIXELS(1920*1080),
		.INITIAL_RED_GAIN(10'd320), .INITIAL_BLUE_GAIN(10'd320)) u_video_auto_levels (
		.clk(clk_pixel_2x), .rst_n(rstn_pixel),
		.auto_enable(w_ddr_mode_active == 2'd0 && w_ddr_mode_request == 2'd0),
		.in_red(w_rgb_r), .in_green(w_rgb_g), .in_blue(w_rgb_b),
		.in_valid(w_rgb_href), .in_hsync(w_rgb_hsync), .in_vsync(w_rgb_vsync),
		.ae_ack_toggle(w_ae_ack),
		.out_red(w_wb_r), .out_green(w_wb_g), .out_blue(w_wb_b),
		.out_valid(w_wb_valid), .out_hsync(w_wb_hsync), .out_vsync(w_wb_vsync),
		.red_gain(w_wb_red_gain), .blue_gain(w_wb_blue_gain),
		.exposure_lines(w_ae_exposure), .analog_gain_index(w_ae_gain),
		.ae_request_toggle(w_ae_request), .frame_ok(w_auto_frame_ok)
	);

	// 曝光/增益按SC2210手册进行group hold写入，不改变原分辨率配置表。
	sc2210_auto_exposure #(.CLK_HZ(CLOCK_MAIN)) u_sc2210_auto_exposure (
		.clk(clk_sys), .rst_n(rstn_sys), .init_done(sc2210_i2c_config_done),
		.sensor_vsync(csi_frame_vsync), .request_toggle(w_ae_request),
		.exposure_lines(w_ae_exposure), .gain_index(w_ae_gain), .sda_in(csi_sda_i),
		.scl(w_ae_scl), .sda_out(w_ae_sda), .sda_oe(w_ae_oe),
		.bus_owned(w_ae_owned), .ack_toggle(w_ae_ack), .fault(w_ae_fault), .update_done(w_ae_done)
	);
	always @(posedge clk_pixel_2x or negedge rstn_pixel) begin
		if (!rstn_pixel) r_ae_fault_sync <= 2'b00;
		else r_ae_fault_sync <= {r_ae_fault_sync[0], w_ae_fault};
	end

	//-------------------------------------------------------------------------
	// MIPI接收时钟域复位同步
	// 复位异步生效、同步释放，供中央裁剪模块使用。
	//-------------------------------------------------------------------------
	always @(posedge w_csi_rx_clk or negedge w_pll_lock) begin
		if (!w_pll_lock)
			rstn_csi_sync <= 2'b00;
		else
			rstn_csi_sync <= {rstn_csi_sync[0], 1'b1};
	end

	//-------------------------------------------------------------------------
	// MIPI中央裁剪模块
	// 每拍接收4个RAW8像素，保留1920列完整视野，不修改摄像头配置。
	//-------------------------------------------------------------------------
	mipi_center_crop_32 #(
		.INPUT_WIDTH  (1920),
		.CROP_X       (0),
		.OUTPUT_WIDTH (1920)
	) u_mipi_center_crop (
		.clk       (w_csi_rx_clk),
		.rst_n     (rstn_csi),
		.in_data   (csi_frame_raw8[31:0]),
		.in_valid  (csi_frame_valid),
		.in_hsync  (w_csi_rx_hsync0),
		.in_vsync  (csi_frame_vsync),
		.out_data  (crop_frame_raw8),
		.out_valid (crop_frame_valid),
		.out_hsync (crop_frame_hsync),
		.out_vsync (crop_frame_vsync)
	);

	//-------------------------------------------------------------------------
	// 板载按键与实时阈值控制
	// 功能键短按切换菜单，长按在回放菜单启动回放。
	// 确认键短按切换选项、增阈值或暂停；长按减阈值或保存截图。
	// 短按在松手后触发，长按释放不再触发短按。
	//-------------------------------------------------------------------------
	debounce #(
		.CLK_FREQ_HZ   (148800000),
		.DEBOUNCE_MS   (20),
		.PRESSED_LEVEL (1'b0)
	) u_function_debounce (
		.clk(clk_pixel_2x),.rst_n(rstn_pixel),.key_in(key_data[0]),
		.key_pressed(w_function_pressed),.key_pressed_pulse(w_function_down_pulse),
		.key_released_pulse(w_function_up_pulse)
	);

	key_event_controller #(
		.CLK_FREQ_HZ   (148800000),
		.LONG_PRESS_MS (800)
	) u_function_key_event (
		.clk(clk_pixel_2x),.rst_n(rstn_pixel),.key_pressed(w_function_pressed),
		.key_pressed_pulse(w_function_down_pulse),.key_released_pulse(w_function_up_pulse),
		.short_press_pulse(w_function_short_pulse),.long_press_pulse(w_function_long_pulse)
	);

	debounce #(
		.CLK_FREQ_HZ   (148800000),
		.DEBOUNCE_MS   (20),
		.PRESSED_LEVEL (1'b0)
	) u_adjust_debounce (
		.clk(clk_pixel_2x),.rst_n(rstn_pixel),.key_in(key_data[1]),
		.key_pressed(w_adjust_pressed),.key_pressed_pulse(w_adjust_down_pulse),
		.key_released_pulse(w_adjust_up_pulse)
	);

	key_event_controller #(
		.CLK_FREQ_HZ   (148800000),
		.LONG_PRESS_MS (800)
	) u_adjust_key_event (
		.clk(clk_pixel_2x),.rst_n(rstn_pixel),.key_pressed(w_adjust_pressed),
		.key_pressed_pulse(w_adjust_down_pulse),.key_released_pulse(w_adjust_up_pulse),
		.short_press_pulse(w_adjust_short_pulse),.long_press_pulse(w_adjust_long_pulse)
	);

	always @(posedge clk_pixel_2x or negedge rstn_pixel) begin
		if (!rstn_pixel)
			r_rgb_vsync_d <= 1'b1;
		else
			r_rgb_vsync_d <= w_rgb_vsync;
	end

    wire [2:0] feature_menu,snapshot_valid;
    wire median_enable,canny_enable,replay_active,replay_paused,snapshot_saving;
    wire snapshot_request,snapshot_cancel,snapshot_busy,snapshot_done,snapshot_error;
    wire [23:0] snapshot_rgb;
    wire snapshot_de,snapshot_hs,snapshot_vs;
    wire arbiter_fault_pixel;
    video_control_mailbox #(.WIDTH(1)) u_arbiter_fault_sync(
        .src_clk(w_ddr3_ui_clk),.dst_clk(clk_pixel_2x),.async_rst_n(rstn_pixel&&!w_ddr3_ui_rst),
        .src_data(arbiter_fault),.dst_data(arbiter_fault_pixel),.dst_update(),.src_busy());
    assign w_system_mode=replay_active?(replay_paused||snapshot_saving?2'd1:2'd2):(feature_menu==1?2'd3:2'd0);
    feature_menu_controller #(.INSPECTION_MENU(1),.HISTORY_FRAMES(8),.MODERN_MENU(1)) u_feature_menu(
        .clk(clk_pixel_2x),.rst_n(rstn_pixel),.frame_start(w_frame_start),
        .function_press(w_function_short_pulse),.confirm_press(w_adjust_short_pulse),
        .function_long_press(w_function_long_pulse),.confirm_long_press(w_adjust_long_pulse),
        .history_count(w_ddr_history_count),
        .snapshot_busy(snapshot_busy),.snapshot_done(snapshot_done),.snapshot_error(snapshot_error),
        .menu_index(feature_menu),.median_enable(median_enable),.canny_enable(canny_enable),
        .display_mode(w_display_mode_request),.threshold_enable(w_threshold_adjust_enable),
        .threshold_add(w_threshold_add_pulse),.threshold_sub(w_threshold_sub_pulse),
        .ddr_mode(w_ddr_mode_request),.replay_offset(w_replay_offset),.replay_active(replay_active),
        .replay_paused(replay_paused),.snapshot_request(snapshot_request),
        .snapshot_cancel(snapshot_cancel),.saving(snapshot_saving));

    // 暂停扩展按键接入；保留灯输出和引脚配置，悬空输入不影响菜单。
    exboard_control u_exboard_control(
        .clk(clk_pixel_2x),.async_rst_n(rstn_pixel),
        .key_up_n(1'b1),.key_down_n(1'b1),
        .fault_level(w_display_underflow || w_display_frame_error || r_ae_fault_sync[1] || snapshot_error || history_fault || arbiter_fault_pixel),
        .add_pulse(),.sub_pulse(),
        .led_run(ex_led_run),.led_alarm(ex_led_alarm),.alarm_active());

	threshold_controller #(
		.WIDTH        (11),
		.DEFAULT_HIGH (11'd80),
		.MIN_HIGH     (11'd16),
		.MAX_HIGH     (11'd2040),
		.STEP         (11'd8)
	) u_threshold_controller (
		.clk(clk_pixel_2x),.rst_n(rstn_pixel),
		.adjust_enable(w_threshold_adjust_enable),
		.add_pulse(w_threshold_add_pulse),
        .sub_pulse(w_threshold_sub_pulse),
		.frame_start(w_frame_start),.high_threshold(w_high_threshold),
		.low_threshold(w_low_threshold),.pending_high_threshold(w_pending_high_threshold)
	);

	//-------------------------------------------------------------------------
	// 高级边缘检测流水线
	// EDGE_MODE=1启用中值、高斯、Sobel、NMS、双阈值和滞后连接。
	//-------------------------------------------------------------------------
	edge_video_pipeline #(
		.IMAGE_WIDTH        (1920),
		.ADDR_WIDTH         (11),
		.THRESHOLD          (11'd80), // 当前固定阈值，非官方指定值
		.EDGE_MODE          (1),
        .RUNTIME_MEDIAN     (1),.RUNTIME_CANNY(1),
        .MORPH_MODE         (3),.MORPH_KERNEL_SHAPE(1),
		.VSYNC_ACTIVE_LEVEL (1'b0)
	) u_edge_video_pipeline (
		.clk              (clk_pixel_2x),
		.rst_n            (rstn_pixel),
		.in_red           (w_wb_r),
		.in_green         (w_wb_g),
		.in_blue          (w_wb_b),
		.in_valid         (w_wb_valid),
		.in_hsync         (w_wb_hsync),
		.in_vsync         (w_wb_vsync),
		.in_high_threshold(w_high_threshold),
		.in_low_threshold (w_low_threshold),
        .in_median_enable (median_enable),.in_canny_enable(canny_enable),
		.out_red          (w_alg_red),
		.out_green        (w_alg_green),
		.out_blue         (w_alg_blue),
		.out_gray         (w_alg_gray),
		.out_edge         (w_alg_edge),
		.out_valid        (w_alg_valid),
		.out_window_valid (w_alg_window_valid),
		.out_hsync        (w_alg_hsync),
		.out_vsync        (w_alg_vsync)
	);

	//-------------------------------------------------------------------------
	// 彩色边缘叠加
	// Canny边缘统一显示黄色，向右加粗4像素，不随背景变色。
	//-------------------------------------------------------------------------
	edge_overlay #(
		.EDGE_R(8'hFF),
		.EDGE_G(8'hFF),
		.EDGE_B(8'h00),
		.HORIZONTAL_EXPAND(1), .EXPAND_PIXELS(4), .ADAPTIVE_COLOR(0)
	) u_edge_overlay (
		.clk       (clk_pixel_2x),
		.rst_n     (rstn_pixel),
		.in_valid  (w_alg_valid),
		.in_hsync  (w_alg_hsync),
		.in_vsync  (w_alg_vsync),
		.in_red    (w_alg_red),
		.in_green  (w_alg_green),
		.in_blue   (w_alg_blue),
		.in_edge   (|w_alg_edge),
		.out_valid (w_overlay_valid),
		.out_hsync (w_overlay_hsync),
		.out_vsync (w_overlay_vsync),
		.out_red   (w_overlay_red),
		.out_green (w_overlay_green),
		.out_blue  (w_overlay_blue)
	);

	// 叠加模块延迟一拍，灰度、黑白边缘和窗口标志同步延迟。
	always @(posedge clk_pixel_2x or negedge rstn_pixel) begin
		if (!rstn_pixel) begin
			r_alg_gray_d          <= 8'd0;
			r_alg_edge_d          <= 8'd0;
			r_alg_window_valid_d   <= 1'b0;
		end else begin
			r_alg_gray_d          <= w_alg_gray;
			r_alg_edge_d          <= w_alg_edge;
			r_alg_window_valid_d   <= w_alg_window_valid;
		end
	end

	//-------------------------------------------------------------------------
	// 视图合成模块
	// 分屏模式显示灰度/黑白边缘；叠加模式居中显示彩色边缘图。
	//-------------------------------------------------------------------------
	gray_edge_display #(
		.SOURCE_WIDTH      (1920),
		.DISPLAY_WIDTH     (1920),
		.DISPLAY_HEIGHT    (1080),
		.FIFO_START_LEVEL  (1920),
		.VSYNC_ACTIVE_LEVEL(1'b0)
	) u_gray_edge_display (
		.clk              (clk_pixel_2x),
		.rst_n            (rstn_pixel),
		.in_lcd_de        (lcd_de),
		.in_lcd_hsync     (lcd_hs),
		.in_lcd_vsync     (lcd_vs),
		.in_display_mode  (w_display_mode_request),
		.in_ddr_data      (ddr_raw8),
		.in_ddr_valid     (ddr_raw8_valid),
		.in_ddr_count     (ddr_raw8_count),
		.out_ddr_request  (ddr_raw8_request),
		.out_source_raw   (w_source_raw),
		.out_source_valid (w_source_valid),
		.out_source_hsync (w_source_hsync),
		.out_source_vsync (w_source_vsync),
		.in_gray          (r_alg_gray_d),
		.in_edge          (r_alg_edge_d),
		.in_overlay_rgb   ({w_overlay_red,w_overlay_green,w_overlay_blue}),
		.in_alg_valid     (w_overlay_valid),
		.in_window_valid  (r_alg_window_valid_d),
		.out_pixel        (w_display_pixel),
		.out_rgb          (w_display_rgb),
		.out_valid        (w_display_valid),
		.out_window_valid (w_display_window_valid),
		.out_region_edge  (w_display_region_edge),
		.out_display_mode (w_display_mode_active),
		.out_hsync        (w_display_hsync),
		.out_vsync        (w_display_vsync),
		.underflow_seen   (w_display_underflow),
		.frame_sync_error (w_display_frame_error)
	);

	//-------------------------------------------------------------------------
	// HDMI状态信息栏
	// 顶部64行显示模式、阈值、回放位置和DDR/视频错误状态。
	//-------------------------------------------------------------------------
    // 轮廓检测旁路读取全幅Canny；长按指定帧录入、短按启停仅在第六菜单有效。
    wire inspection_background_ready,inspection_template_valid,inspection_learning,inspection_enabled;
    wire inspection_fault,inspection_matched;
    wire [31:0] inspection_frame_id;
    wire [2:0] inspection_count;
    wire [1:0] inspection_status;
    wire [63:0] inspection_tracks;
    wire [127:0] inspection_detection_ids;
    wire [7:0] inspection_diagnostic;
    wire inspection_live=w_ddr_mode_active==0 && w_ddr_mode_request==0;
    wire [31:0] inspection_config={4'd0,1'b1,1'b1,2'd3,canny_enable,median_enable,w_low_threshold,w_high_threshold};
    reg pair_enable,source_seen,source_de_d,display_vs_d;
    reg [31:0] processing_id;
    wire source_first=w_wb_valid && !source_de_d && !source_seen;
    wire [31:0] source_job_id=source_first?processing_id+1'b1:processing_id;
    always @(posedge clk_pixel_2x or negedge rstn_pixel)begin
        if(!rstn_pixel)begin pair_enable<=0;source_seen<=0;source_de_d<=0;display_vs_d<=1;processing_id<=0;end
        else begin
            source_de_d<=w_wb_valid;display_vs_d<=w_display_vsync;
            if(!w_wb_vsync)source_seen<=0;
            else if(source_first)begin source_seen<=1;processing_id<=source_job_id;end
            // 只在帧边界切换缓存/直通，保持所有视频像素节拍不变。
            if(display_vs_d && !w_display_vsync)pair_enable<=inspection_live && (feature_menu==5 || inspection_enabled || inspection_learning);
        end
    end
    wire pair_shown,pair_fault,pair_clear,pair_allocated,pair_lookup_valid;
    wire [31:0] pair_shown_id,pair_shown_cfg,pair_shown_epoch,pair_origin,pair_epoch,pair_lookup_epoch;
    wire [1:0] pair_shown_status,pair_allocated_slot,pair_lookup_slot;
    wire [15:0] pair_shown_track;
    wire [23:0] pair_rgb;wire pair_de,pair_hs,pair_vs;
    wire raw_result_valid,feature_valid,feature_bad,external_start,external_ready,external_done,external_failed,external_bad,learn_allowed,learning_fault;
    wire [31:0] raw_result_id,feature_id,feature_cfg,external_id,external_cfg;
    wire [1:0] raw_status;wire [15:0] raw_track;
    wire [1837:0] feature_descriptor,external_descriptor;
    wire learn_command=feature_menu==5 && w_adjust_long_pulse && !w_function_short_pulse && !w_adjust_short_pulse;
    wire [2:0] pair_queue,pair_high;
    wire legacy_matched;wire [31:0] legacy_frame;
    wire [2:0] legacy_count;wire [1:0] legacy_status;
    wire [63:0] legacy_tracks;wire [127:0] legacy_detection;
    wire path_fault;
    inspection_edge_formal_path #(.PAIRED_DISPLAY(1),.TEMPORAL_VOTE(1)) u_inspection(
        .clk(clk_pixel_2x),.rst_n(rstn_pixel),
        .source_valid(w_wb_valid),.source_vsync(w_wb_vsync),
        .edge_valid(w_alg_valid),.edge_window_valid(w_alg_window_valid),.edge_vsync(w_alg_vsync),.edge_pixel(w_alg_edge!=0),
        .source_config(inspection_config),
        .source_frame_id(source_job_id),.source_frame_valid(display_frame_valid && pair_enable),
        .live_mode(inspection_live && pair_enable),
        .learn_request(learn_command),
        .start_request(feature_menu==5 && w_adjust_short_pulse && !w_function_short_pulse && !w_adjust_long_pulse),
        .display_de(snapshot_de),.display_vsync(snapshot_vs),
        .background_ready(inspection_background_ready),.template_valid(inspection_template_valid),
        .learn_pending(inspection_learning),.detect_enabled(inspection_enabled),.fault(path_fault),
        .result_matched(legacy_matched),.selected_frame_id(legacy_frame),.selected_count(legacy_count),
        .selected_status(legacy_status),.selected_track_ids(legacy_tracks),.selected_detection_ids(legacy_detection),
        .selected_centers_x(),.selected_centers_y(),.accepted_frames(),.busy_frames(),.processing_cycles(),.manager_cycles(),
        .submitted(),.completed(),.queue_depth(),.queue_high_water(),.diagnostic(inspection_diagnostic),
        .visible_frame_id(pair_shown_id),.visible_frame_valid(pair_shown && inspection_live),.learning_allowed(learn_allowed),
        .external_learn_start(external_start),.external_learn_ready(external_ready),.external_descriptor(external_descriptor),.external_frame_id(external_id),.external_config(external_cfg),.external_bad(external_bad),.external_done(external_done),.external_failed(external_failed),
        .feature_valid(feature_valid),.feature_bad(feature_bad),.feature_descriptor(feature_descriptor),.feature_frame_id(feature_id),.feature_config(feature_cfg),
        .completed_result_valid(raw_result_valid),.completed_result_id(raw_result_id),.completed_result_status(raw_status),.completed_result_track(raw_track),.invalidate_display(pair_clear));
    paired_feature_learning u_displayed_learning(
        .clk(clk_pixel_2x),.rst_n(rstn_pixel),.live(inspection_live && pair_enable),.allocate(pair_allocated),.allocate_slot(pair_allocated_slot),
        .feature_valid(feature_valid),.feature_bad(feature_bad),.feature_descriptor(feature_descriptor),.feature_id(feature_id),.feature_config(feature_cfg),
        .lookup_valid(pair_lookup_valid),.lookup_slot(pair_lookup_slot),.lookup_epoch(pair_lookup_epoch),.current_epoch(pair_epoch),
        .learn_command(learn_command),.display_valid(pair_shown),.display_id(pair_shown_id),.display_config({1'b0,pair_shown_cfg[30:0]}),.display_epoch(pair_shown_epoch),.current_config(inspection_config),
        .learn_allowed(learn_allowed),.external_start(external_start),.external_ready(external_ready),.external_done(external_done),.external_descriptor(external_descriptor),.external_id(external_id),.external_config(external_cfg),.external_bad(external_bad),.fault(learning_fault));
    paired_video_buffer #(.STREAM_WRITER(1)) u_paired_display(
        .pixel_clk(clk_pixel_2x),.axi_clk(w_ddr3_ui_clk),.rst_n(rstn_pixel && !w_ddr3_ui_rst),.enable(pair_enable),.clear_pending(pair_clear),
        .in_rgb(w_display_rgb),.in_de(w_display_valid),.in_hsync(w_display_hsync),.in_vsync(w_display_vsync),.in_frame_id(processing_id),.in_config({w_display_mode_active,inspection_config[30:0]}),.in_original_id(display_frame_id),.source_frame_valid(display_frame_valid),
        .result_valid(raw_result_valid),.result_frame_id(raw_result_id),.result_status(raw_status),.result_track_id(raw_track),
        .out_rgb(pair_rgb),.out_de(pair_de),.out_hsync(pair_hs),.out_vsync(pair_vs),.shown_valid(pair_shown),.shown_frame_id(pair_shown_id),.shown_config(pair_shown_cfg),.shown_epoch(pair_shown_epoch),.shown_original_id(pair_origin),.shown_status(pair_shown_status),.shown_track_id(pair_shown_track),
        .allocated(pair_allocated),.allocated_slot(pair_allocated_slot),.current_epoch(pair_epoch),.lookup_frame_id(feature_id),.lookup_valid(pair_lookup_valid),.lookup_slot(pair_lookup_slot),.lookup_epoch(pair_lookup_epoch),
        .write_command_valid(pair_awvalid),.write_command_ready(client_ready[4]),.write_address(pair_awaddr),.write_length(pair_awlen),.write_data(pair_wdata),.write_valid(pair_wvalid),.write_last(pair_wlast),.write_ready(client_wready[2]),.response_valid(client_bvalid[2]),.response_code(client_bresp),.response_ready(pair_bready),
        .read_command_valid(pair_arvalid),.read_command_ready(client_ready[5]),.read_address(pair_araddr),.read_length(pair_arlen),.read_data(client_rdata),.read_valid(client_rvalid[2]),.read_last(client_rlast),.read_code(client_rresp),.read_ready(pair_rready),.write_level(pair_write_level),.read_level(pair_read_level),.queue_depth(pair_queue),.queue_high(pair_high),.fault(pair_fault));
    assign inspection_fault=path_fault || pair_fault || learning_fault;
    assign inspection_matched=pair_shown && inspection_live && pair_enable && inspection_enabled && inspection_template_valid && !inspection_fault;
    assign inspection_frame_id=pair_shown_id;
    assign inspection_count=inspection_matched && pair_shown_status!=0?3'd1:3'd0;
    assign inspection_status=inspection_matched?pair_shown_status:2'd0;
    assign inspection_tracks={48'd0,pair_shown_track};
    assign inspection_detection_ids={96'd0,pair_shown_id};
    snapshot_system #(.UI_FOOTER_HEIGHT(152)) u_snapshot_system(
        .pixel_clk(clk_pixel_2x),.axi_clk(w_ddr3_ui_clk),.rst_n(rstn_pixel&&!w_ddr3_ui_rst),
        .request(snapshot_request),.cancel(snapshot_cancel),.freeze_request(w_ddr_mode_request==1),
        .source_frame_id(pair_enable?pair_origin:display_frame_id),.source_frame_valid(pair_enable?pair_shown:display_frame_valid),.source_mode(w_ddr_mode_active),
        .in_rgb(pair_rgb),.in_de(pair_de),.in_hsync(pair_hs),.in_vsync(pair_vs),
        .out_rgb(snapshot_rgb),.out_de(snapshot_de),.out_hsync(snapshot_hs),.out_vsync(snapshot_vs),
        .busy(snapshot_busy),.done(snapshot_done),.error(snapshot_error),.saved_valid(snapshot_valid),
        .freeze_frame_id(snapshot_freeze_id),.awaddr(snap_awaddr),.araddr(snap_araddr),
        .awlen(snap_awlen),.arlen(snap_arlen),.awvalid(snap_awvalid),.arvalid(snap_arvalid),
        .wvalid(snap_wvalid),.wlast(snap_wlast),.bready(snap_bready),.rready(snap_rready),
        .awready(client_ready[2]),.arready(client_ready[3]),.wready(client_wready[1]),
        .bvalid(client_bvalid[1]),.rvalid(client_rvalid[1]),.rlast(client_rlast),
        .wdata(snap_wdata),.wstrb(snap_wstrb),.rdata(client_rdata),.bresp(client_bresp),.rresp(client_rresp));
	video_ui_overlay #(
        .MODERN_UI         (1),
        .FEATURE_MENU      (1),
        .INSPECTION_UI     (1),.EDGE_DIAGNOSTICS(1),
        .REPLAY_BITS       (3),.CLK_FREQ_HZ(148800000),
		.DISPLAY_WIDTH     (1920),
		.DISPLAY_HEIGHT    (1080),
		.VSYNC_ACTIVE_LEVEL(1'b0)
	) u_video_ui_overlay (
		.clk              (clk_pixel_2x),
		.rst_n            (rstn_pixel),
		.in_rgb           (snapshot_rgb),
		.in_de            (snapshot_de),
		.in_hsync         (snapshot_hs),
		.in_vsync         (snapshot_vs),
        .in_menu(feature_menu),.in_median_enable(pair_enable&&pair_shown?pair_shown_cfg[22]:median_enable),.in_canny_enable(pair_enable&&pair_shown?pair_shown_cfg[23]:canny_enable),
        .in_saving(snapshot_saving),.in_saved_valid(snapshot_valid),
        .inspection_background_ready(inspection_background_ready),.inspection_template_valid(inspection_template_valid),
        .inspection_learning(inspection_learning),.inspection_enabled(inspection_enabled),.inspection_matched(inspection_matched),
        .inspection_fault(inspection_fault),.inspection_diagnostic(inspection_diagnostic),
        .inspection_status(inspection_status),.inspection_frame_id(inspection_frame_id),.inspection_detection_id(inspection_detection_ids[31:0]),
        .inspection_track_id(inspection_tracks[15:0]),.inspection_count(inspection_count),
		.in_mode          (w_system_mode),
		.in_display_mode  (pair_enable&&pair_shown?pair_shown_cfg[31]:w_display_mode_active),
		.in_high_threshold(pair_enable&&pair_shown?pair_shown_cfg[10:0]:w_high_threshold),
		.in_low_threshold (pair_enable&&pair_shown?pair_shown_cfg[21:11]:w_low_threshold),
		.in_replay_offset (w_replay_offset),
		.in_ddr_error     (w_display_underflow||history_fault||arbiter_fault_pixel||snapshot_error),
		.in_video_error   (w_display_frame_error || r_ae_fault_sync[1]),
		.out_rgb          (w_ui_rgb),
		.out_de           (w_ui_valid),
		.out_hsync        (w_ui_hsync),
		.out_vsync        (w_ui_vsync)
	);

	endmodule
