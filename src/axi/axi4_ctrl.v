//  by CrazyBird
module axi4_ctrl #(
	parameter 	C_ID_LEN      = 8, 
			C_DATA_LEN    = 128, 
			C_DATA_SIZE   = 4, 	//	C_DATA_LEN=8:0, 16:1, 32:2, 64:3, 128:4, 256:5, 512:6, 1024:7
			
			C_BURST_LEN   = 128,
			
			C_STRB_LEN    = C_DATA_LEN / 8, 
			C_ADDR_INC    = C_BURST_LEN * C_STRB_LEN,
			
			C_BASE_ADDR   = 32'h00000000, 	//	Start at 0x00000000 by default
			C_BUF_SIZE    = 22, 			//	Allocate 2^22 bytes (4MB) by default. The module takes 4*4MB by default. 
			C_RD_END_ADDR = 1280 * 720,
			
			C_W_WIDTH     = 64, 
			C_R_WIDTH     = 8,
            HISTORY_FRAMES=4, FRAME_SLOTS=6,
            OFFSET_BITS=(HISTORY_FRAMES<=2)?1:$clog2(HISTORY_FRAMES),
            COUNT_BITS=$clog2(HISTORY_FRAMES+1), INDEX_BITS=$clog2(FRAME_SLOTS)
)(
    input  wire                 axi_clk         ,
    input  wire                 axi_reset       ,
    
    output       [C_ID_LEN-1:0]      axi_awid        ,
    output       [31:0]      axi_awaddr      ,
    output       [ 7:0]      axi_awlen       ,
    output       [ 2:0]      axi_awsize      ,
    output       [ 1:0]      axi_awburst     ,
    output                   axi_awlock      ,
    output       [ 3:0]      axi_awcache     ,
    output       [ 2:0]      axi_awprot      ,
    output       [ 3:0]      axi_awqos       ,
    output reg                  axi_awvalid     ,
    input  wire                 axi_awready     ,
    
    output       [C_DATA_LEN-1:0]      axi_wdata       ,
    output       [C_STRB_LEN-1:0]      axi_wstrb       ,
    output                   axi_wlast       ,
    output reg                  axi_wvalid      ,
    input  wire                 axi_wready      ,
    
    input  wire     [C_ID_LEN-1:0]      axi_bid         ,
    input  wire     [ 1:0]      axi_bresp       ,
    input  wire                 axi_bvalid      ,
    output                   axi_bready      ,
    
    output       [C_ID_LEN-1:0]      axi_arid        ,
    output       [31:0]      axi_araddr      ,
    output       [ 7:0]      axi_arlen       ,
    output       [ 2:0]      axi_arsize      ,
    output       [ 1:0]      axi_arburst     ,
    output                   axi_arlock      ,
    output       [ 3:0]      axi_arcache     ,
    output       [ 2:0]      axi_arprot      ,
    output       [ 3:0]      axi_arqos       ,
    output reg                  axi_arvalid     ,
    input  wire                 axi_arready     ,
    
    input  wire     [C_ID_LEN-1:0]      axi_rid         ,
    input  wire     [C_DATA_LEN-1:0]      axi_rdata       ,
    input  wire     [ 1:0]      axi_rresp       ,
    input  wire                 axi_rlast       ,
    input  wire                 axi_rvalid      ,
    output                   axi_rready      ,
    
    input  wire                 wframe_pclk     ,
    input  wire                 wframe_vsync    ,		//	Writter VSync. Flush on falling edge. Connect to EOF. 
    input  wire                 wframe_data_en  ,
    input  wire     [C_W_WIDTH-1:0]      wframe_data     ,
    
    input  wire                 rframe_pclk     ,
    input  wire                 rframe_vsync    ,		//	Reader VSync. Flush on falling edge. Connect to ~EOF. 
    input  wire                 rframe_data_en  ,
    output wire     [C_R_WIDTH-1:0]      rframe_data     ,
    output wire                 rframe_data_valid, // FWFT读端当前数据有效，高电平有效
    output wire     [12:0]      rframe_data_count, // 读FIFO内可用像素数量

    input  wire     [1:0]       frame_mode_request, // 0实时，1冻结，2回放
    input  wire     [OFFSET_BITS-1:0] replay_frame_offset,// 0最新，HISTORY_FRAMES-1最旧
    output wire     [1:0]       frame_mode_active,  // DDR当前实际模式
    output wire     [INDEX_BITS-1:0] frame_write_index,
    output wire     [INDEX_BITS-1:0] frame_read_index,
    output wire     [COUNT_BITS-1:0] frame_history_count,
    input wire [31:0] freeze_frame_id,
    output wire [31:0] display_frame_id,
    output wire display_frame_valid,
    output wire frame_fault,
    
    output 		[31:0] 	tp_o
);
	
	initial begin
		axi_awvalid <= 0; 
		axi_wvalid <= 0; 
		axi_arvalid <= 0; 
	end

	assign axi_awid    = {C_ID_LEN{1'b0}};
	assign axi_awlen   = C_BURST_LEN - 1'b1;
	assign axi_awsize  = C_DATA_SIZE;
	assign axi_awburst = 2'b01;	//	INCR
	assign axi_awlock  = 1'b0;
	assign axi_awcache = 0;
	assign axi_awprot  = 3'b0;
	assign axi_awqos   = 4'b0;
	assign axi_wstrb   = 32'hFFFFFFFF;
	assign axi_bready  = 1; 
	    
	assign axi_arid    = {C_ID_LEN{1'b0}};
	assign axi_arlen   = C_BURST_LEN - 1'b1;
	assign axi_arsize  = C_DATA_SIZE;
	assign axi_arburst = 2'b01;	//	INCR
	assign axi_arlock  = 1'b0;
	assign axi_arcache = 0;
	assign axi_arprot  = 3'b0;
	assign axi_arqos   = 4'b0;
	assign axi_rready  = 1; 
	
	
	
	
	////////////////////////////////////////////////////////////////
	// 4帧历史管理。模式请求在模块内部同步到AXI时钟域。
	wire [INDEX_BITS-1:0] rc_wframe_index;
	wire [INDEX_BITS-1:0] rc_rframe_index;
	wire       w_capture_enable_axi;
	wire       w_source_frame_boundary;
	wire       w_read_frame_boundary;
	reg        r_wframe_inc = 0;
	reg        r_rframe_inc = 0;

    localparam CONTROL_BITS=34+OFFSET_BITS, STATUS_BITS=36+COUNT_BITS;
	wire [CONTROL_BITS-1:0] control_axi;
    wire [1:0] mode_axi;
    wire [COUNT_BITS-1:0] history_axi;
    wire [31:0] id_axi;
    wire valid_axi,manager_fault;
    reg bus_fault;
    wire [STATUS_BITS-1:0] status_pixel;
    video_control_mailbox #(.WIDTH(CONTROL_BITS)) u_history_control(
        .src_clk(rframe_pclk),.dst_clk(axi_clk),.async_rst_n(!axi_reset),
        .src_data({freeze_frame_id,replay_frame_offset,frame_mode_request}),
        .dst_data(control_axi),.dst_update(),.src_busy());
    video_control_mailbox #(.WIDTH(STATUS_BITS)) u_history_status(
        .src_clk(axi_clk),.dst_clk(rframe_pclk),.async_rst_n(!axi_reset),
        .src_data({manager_fault|bus_fault,valid_axi,id_axi,history_axi,mode_axi}),
        .dst_data(status_pixel),.dst_update(),.src_busy());
    assign {frame_fault,display_frame_valid,display_frame_id,frame_history_count,frame_mode_active}=status_pixel;
	video_history_manager #(.HISTORY_FRAMES(HISTORY_FRAMES),.FRAME_SLOTS(FRAME_SLOTS)) u_ddr_frame_manager (
		.clk                    (axi_clk),
		.rst                    (axi_reset),
		.requested_mode         (control_axi[1:0]),
		.replay_offset          (control_axi[OFFSET_BITS+1:2]),
        .freeze_frame_id        (control_axi[CONTROL_BITS-1:OFFSET_BITS+2]),
		.source_frame_boundary  (w_source_frame_boundary),
		.write_frame_done       (r_wframe_inc),
		.read_frame_boundary    (w_read_frame_boundary),
		.capture_enable         (w_capture_enable_axi),
		.write_index            (rc_wframe_index),
		.read_index             (rc_rframe_index),
		.active_mode            (mode_axi),
		.history_count          (history_axi),
        .read_frame_id(id_axi),.read_valid(valid_axi),.fault(manager_fault)
	);
	assign frame_write_index = rc_wframe_index;
	assign frame_read_index  = rc_rframe_index;
	
	
	
	////////////////////////////////////////////////////////////////
	//	AXI Writter

	wire 				w_wfifo_pempty, w_wfifo_empty; 
	wire 				w_wfifo_ren; 
	wire 	[C_DATA_LEN-1:0] 	w_wfifo_rdata; 

	//	On EOF when ~empty, flush the last data then reset FIFO. 
	reg 	[3:0] 	rs_w = 0; 
	wire 	[3:0] 	ws_w_idle = 0; 
	wire 	[3:0] 	ws_w_wdata = 1; 
	wire 	[3:0] 	ws_w_winc = 2; 
	wire 	[3:0] 	ws_w_eof = 3; 
    wire [3:0] ws_w_response=4;

	//	Write Pointer. Burst bytes is always C_ADDR_INC. 
	reg 	[C_BUF_SIZE-1:0] 	rc_w_ptr = 0; 
	reg 	[0:0] 		rc_w_eof = 0; 
	reg 				r_w_rst = 1; 
	
	//	Burst Control
	reg 	[7:0] 	rc_burst = 0; 	//	Compare to C_BURST_LEN - 1. 
	
	//	EOF Monitor. 
	reg 	[1:0] 	r_wframe_sync = 0; 	
	reg 			r_weof_pending = 0; 
	reg             r_frame_write_seen = 0; // 当前帧至少有一个AXI写数据节拍
	assign w_source_frame_boundary = (r_wframe_sync == 2'b10);

	always @(posedge axi_clk or posedge axi_reset) begin
		if(axi_reset) begin
			rs_w <= 0; 
			rc_w_ptr <= 0; 
			rc_w_eof <= 0; 
			r_w_rst <= 1; 
			axi_awvalid <= 0; 
			axi_wvalid <= 0; 
			r_wframe_sync <= 0; 
			r_weof_pending <= 0; 
			r_wframe_inc <= 0; 
			r_frame_write_seen <= 0;
            bus_fault<=0;
			
		end else begin
			rc_w_eof <= 0; 
			r_wframe_inc <= 0; 
			if(w_wfifo_ren)
				r_frame_write_seen <= 1'b1;
			if(~w_capture_enable_axi)
				r_frame_write_seen <= 1'b0;
			
			//	Raise EOF on falling edge of VSYNC. 
			r_wframe_sync <= {r_wframe_sync, wframe_vsync}; 
			if(r_wframe_sync == 2'b10) begin
				r_weof_pending <= 1; 
			end else begin
			end
			
			if(axi_awready) begin
				axi_awvalid <= 0; 
			end else begin
			end
			
			case (rs_w)
				ws_w_idle: begin
						rc_burst <= 0; 
						r_w_rst <= 0; 
						
						if(~w_wfifo_pempty && !bus_fault) begin
							axi_awvalid <= 1; 
							axi_wvalid <= 1; 
							rs_w <= ws_w_wdata; 
						
						end else if(r_weof_pending && (~w_wfifo_empty) && !bus_fault) begin
							//	There's some data in the FIFO. write last. 
							axi_awvalid <= 1; 
							axi_wvalid <= 1; 
							rs_w <= ws_w_wdata; 
							
						end else if(r_weof_pending) begin
							//	EOF. Reset FIFO. Increment write pointer. 
							r_w_rst <= 1; 
							if(r_frame_write_seen && !bus_fault)
								r_wframe_inc <= 1; 
							r_frame_write_seen <= 1'b0;
							rs_w <= ws_w_eof; 
							
						end else begin
						end
					end
					
				ws_w_eof: begin
						//	Wait for some cycles to release reset. 
						r_weof_pending <= 0; 
						rc_w_ptr <= 0; 
						
						rc_w_eof <= rc_w_eof + 1; 
						if(&rc_w_eof)
							rs_w <= ws_w_idle; 
						else begin
						end
					end
					
				ws_w_wdata: begin
						rc_burst <= rc_burst + axi_wready; 
						
						//	On last transaction terminate write. 
						if(axi_wlast && axi_wready) begin
							axi_wvalid <= 0; 
							rs_w <= ws_w_response; 
						end else begin
						end
					end
					
                ws_w_response:if(axi_bvalid)begin
                    if(axi_bresp!=0 || axi_bid!=0)bus_fault<=1;
                    rs_w<=ws_w_winc;
                end
				ws_w_winc: begin
						rc_w_ptr <= rc_w_ptr + C_ADDR_INC; 
						rs_w <= ws_w_idle; 
					end
			endcase
		end
	end
	assign axi_awaddr = C_BASE_ADDR + {rc_wframe_index, rc_w_ptr}; 
	assign axi_wdata = w_wfifo_rdata; 
	assign axi_wlast = (rc_burst >= C_BURST_LEN - 1); 
	
	assign w_wfifo_ren = axi_wvalid && axi_wready; 

	// 将采集允许信号同步到MIPI像素时钟域后再控制写FIFO。
	reg [1:0] r_capture_enable_sync = 2'b00;
	always @(posedge wframe_pclk or posedge axi_reset) begin
		if(axi_reset)
			r_capture_enable_sync <= 2'b00;
		else
			r_capture_enable_sync <= {r_capture_enable_sync[0], w_capture_enable_axi};
	end
	wire w_capture_enable_pclk = r_capture_enable_sync[1];
	
	
	assign tp_o[1:0] = {rs_w[1:0]}; 
	assign tp_o[2] = axi_wvalid; 
	assign tp_o[3] = wframe_data_en; 
	
	
	generate
		if(C_W_WIDTH == 64) begin: Gen_FIFO_W64
			W0_FIFO_64 u_W0_FIFO_64 
			(
			    .wr_clk_i       (wframe_pclk    ),
			    .wr_en_i        (wframe_data_en && w_capture_enable_pclk),
			    .wdata          (wframe_data    ),
			    
			    .a_rst_i 	(r_w_rst), 

			    .rd_clk_i       (axi_clk        ),
			    .rd_en_i        (w_wfifo_ren     ),
			    .rdata          (w_wfifo_rdata    ),
			    .prog_empty_o	(w_wfifo_pempty),
			    .empty_o 		(w_wfifo_empty)
			);
		end else if(C_W_WIDTH == 32) begin: Gen_FIFO_W32
			W0_FIFO_32 u_W0_FIFO_32
			(
			    .wr_clk_i       (wframe_pclk    ),
			    .wr_en_i        (wframe_data_en && w_capture_enable_pclk),
			    .wdata          (wframe_data    ),
			    
			    .a_rst_i 	(r_w_rst), 

			    .rd_clk_i       (axi_clk        ),
			    .rd_en_i        (w_wfifo_ren     ),
			    .rdata          (w_wfifo_rdata    ),
			    .prog_empty_o	(w_wfifo_pempty),
			    .empty_o 		(w_wfifo_empty)
			);
		end else if(C_W_WIDTH == 8) begin: Gen_FIFO_W8
			W0_FIFO_8 u_W0_FIFO_8 
			(
			    .wr_clk_i       (wframe_pclk    ),
			    .wr_en_i        (wframe_data_en && w_capture_enable_pclk),
			    .wdata          (wframe_data    ),
			    
			    .a_rst_i 	(r_w_rst), 

			    .rd_clk_i       (axi_clk        ),
			    .rd_en_i        (w_wfifo_ren     ),
			    .rdata          (w_wfifo_rdata    ),
			    .prog_empty_o	(w_wfifo_pempty),
			    .empty_o 		(w_wfifo_empty)
			);
		end
	endgenerate




















reg                             rframe_vsync_dly;

always @(posedge rframe_pclk)
begin
    if(axi_reset == 1'b1)
        rframe_vsync_dly <= 1'b0;
    else
        rframe_vsync_dly <= rframe_vsync;
end

wire                            rframe_vsync_neg;
assign rframe_vsync_neg =  rframe_vsync_dly & ~rframe_vsync;

reg             [4:0]           rfifo_cnt;

always @(posedge rframe_pclk)
begin
    if(axi_reset == 1'b1)
        rfifo_cnt <= 5'h1f;
    else
    begin
        if(rframe_vsync_neg == 1'b1)
            rfifo_cnt <= 5'h1f;
        else if(rfifo_cnt > 5'd0)
            rfifo_cnt <= rfifo_cnt - 1'b1;
        else
            rfifo_cnt <= 5'b0;
    end
end

reg                             rfifo_rst;

always @(posedge rframe_pclk)
begin
    if(axi_reset == 1'b1)
        rfifo_rst <= 1'b1;
    else
    begin
        if(rfifo_cnt == 5'b0)
            rfifo_rst <= 1'b0;
        else
            rfifo_rst <= 1'b1;
    end
end


wire 			w_rfifo_rst = axi_reset || rfifo_rst; 

reg                             rfifo_wenb;
reg             [C_DATA_LEN-1:0]          rfifo_wdata;
wire            [ 9:0]          rfifo_wcnt;
wire 					  rfifo_wfull; 
wire                            rfifo_wr_rst_busy;
wire 					w_rfifo_aempty; 
wire 					w_rfifo_empty; 
wire            [12:0]          w_rfifo_rcount_8;
wire            [11:0]          w_rfifo_rcount_16;


generate
	if(C_R_WIDTH == 8) begin: Gen_RFIFO_8
		R0_FIFO_8 u_R0_FIFO_8
		(
			.wr_clk_i		(axi_clk),
			.wr_en_i		(rfifo_wenb),
			.wdata			(rfifo_wdata),
			.a_rst_i		(w_rfifo_rst), 
			.prog_full_o		(rfifo_wfull),
			
			.rd_clk_i		(rframe_pclk),
			.rd_en_i		(rframe_data_en),
			.rdata			(rframe_data),
			.empty_o		(w_rfifo_empty),
			.almost_empty_o	(w_rfifo_aempty),
			.rd_datacount_o (w_rfifo_rcount_8)
		);
	end else if(C_R_WIDTH == 16) begin: Gen_RFIFO_16	
		R0_FIFO_16 u_R0_FIFO_16
		(
			.wr_clk_i		(axi_clk),
			.wr_en_i		(rfifo_wenb),
			.wdata			(rfifo_wdata),
			.a_rst_i		(w_rfifo_rst), 
			.prog_full_o		(rfifo_wfull),
			
			.rd_clk_i		(rframe_pclk),
			.rd_en_i		(rframe_data_en),
			.rdata			(rframe_data),
			.empty_o		(w_rfifo_empty),
			.almost_empty_o	(w_rfifo_aempty),
			.rd_datacount_o (w_rfifo_rcount_16)
		);
	end
endgenerate

// 读FIFO采用FWFT模式：非空时，rframe_data即为当前队首有效数据。
assign rframe_data_valid = ~w_rfifo_empty;
assign rframe_data_count = (C_R_WIDTH == 8) ? w_rfifo_rcount_8 :
                           {1'b0, w_rfifo_rcount_16};
		
reg r_rfifo_rst = 0; 
always @(posedge axi_clk)
begin
	r_rfifo_rst <= w_rfifo_rst; 
end

//assign tp_o[7:0] = {w_rfifo_empty, rfifo_wfull, rframe_data_en, rfifo_wenb, rfifo_rst, axi_reset, rframe_pclk, axi_clk}; 

reg             [15:0]               rfifo_wr_rst_busy_dly = 2'b0;

always @(posedge axi_clk or posedge r_rfifo_rst)
begin
    if(r_rfifo_rst == 1'b1)
        rfifo_wr_rst_busy_dly <= 0;
    else
        rfifo_wr_rst_busy_dly <= {rfifo_wr_rst_busy_dly,1'b1};
end

wire                                rfifo_wr_rst_busy_neg;
assign rfifo_wr_rst_busy_neg = (rfifo_wr_rst_busy_dly[1:0] == 2'b01) ? 1'b1 : 1'b0;

reg             [4:0]               read_ddr_delay_cnt;

always @(posedge axi_clk or posedge r_rfifo_rst)
begin
    if(r_rfifo_rst == 1'b1)
        read_ddr_delay_cnt <= 5'b0;
    else
    begin
        if(rfifo_wr_rst_busy_neg == 1'b1)
            read_ddr_delay_cnt <= 5'd31;
        else if(read_ddr_delay_cnt > 5'b0)
            read_ddr_delay_cnt <= read_ddr_delay_cnt - 1'b1;
        else
            read_ddr_delay_cnt <= 5'b0;
    end
end

// 显示帧复位只丢弃旧数据，不撤销已发布的AXI命令或响应。
// 旧事务排空后再切换帧槽，并留出同步FIFO恢复时间。
reg read_restart,read_started;
reg [5:0] read_start_delay;
reg [C_BUF_SIZE-1:0] araddr;
reg [31:0] read_command_address;
reg [8:0] read_beats;
reg read_outstanding;
assign axi_araddr=read_command_address;
assign w_read_frame_boundary=r_rframe_inc;
always @(posedge axi_clk or posedge axi_reset)begin
 if(axi_reset)begin
  read_restart<=1;read_started<=0;read_start_delay<=0;araddr<=0;
  read_command_address<=0;read_beats<=0;read_outstanding<=0;
  axi_arvalid<=0;r_rframe_inc<=0;rfifo_wenb<=0;rfifo_wdata<=0;
 end else begin
  r_rframe_inc<=0;rfifo_wenb<=0;
  if(r_rfifo_rst)begin read_restart<=1;read_started<=0;end
  if(axi_arvalid&&axi_arready)begin
   axi_arvalid<=0;read_outstanding<=1;read_beats<=C_BURST_LEN;
   araddr<=araddr+C_ADDR_INC;
  end
  if(axi_rvalid&&read_outstanding)begin
   read_beats<=read_beats-1'b1;
   if(read_beats==1)read_outstanding<=0;
   if(!read_restart&&!r_rfifo_rst&&read_started)begin
    rfifo_wdata<=axi_rdata;rfifo_wenb<=1;
   end
  end
  if(read_restart&&!r_rfifo_rst&&!read_outstanding&&!axi_arvalid)begin
   read_restart<=0;araddr<=0;read_start_delay<=31;r_rframe_inc<=1;
  end else if(read_start_delay!=0)begin
   read_start_delay<=read_start_delay-1'b1;
   if(read_start_delay==1)read_started<=1;
  end
  if(read_started&&!read_restart&&!r_rfifo_rst&&!read_outstanding&&!axi_arvalid&&
     !rfifo_wfull&&araddr<C_RD_END_ADDR&&valid_axi&&!manager_fault&&!bus_fault)begin
   read_command_address<=C_BASE_ADDR+{rc_rframe_index,araddr};axi_arvalid<=1;
  end
 end
end

endmodule
