`timescale 1ns/1ps
// 两组行段RAM交替采集/处理；读端持有整帧所有权，写端只能使用空闲组。
module inspection_edge_runs #(
    parameter IMAGE_WIDTH=1920,IMAGE_HEIGHT=1080,MAX_RUNS=2048
)(
    input wire clk,rst_n,
    input wire in_valid,in_start,in_edge,in_commit,in_abort,
    input wire [10:0] in_x,in_y,
    input wire [31:0] in_frame_id,in_config,
    input wire [7:0] in_error,
    output wire result_valid,
    input wire result_ready,
    output wire [31:0] result_frame_id,result_config,
    output wire [7:0] result_error,
    output wire [$clog2(MAX_RUNS):0] run_count,
    output wire [21:0] edge_points,
    output wire [10:0] x_min,x_max,y_min,y_max,
    output wire [31:0] frame_cycles,
    output reg fault,
    output reg [7:0] fault_code,
    output wire frame_ready,
    output wire [1:0] buffer_level,
    input wire record_read,
    input wire [$clog2(MAX_RUNS)-1:0] record_index,
    input wire [31:0] record_frame_id,
    output reg record_valid,record_error,
    output reg [10:0] record_x0,record_x1,record_y
);
    localparam AW=$clog2(MAX_RUNS),MW=171+AW;
    reg [33:0] records[0:2*MAX_RUNS-1];
    reg [MW-1:0] completed_data[0:1];
    reg [33:0] record_q;
    reg wr_bank,rd_bank;
    reg [1:0] occupied,complete;
    reg read_pending,read_bad,active,discard,encoded_done,commit_seen,publish_pending;
    reg [31:0] cap_id,cap_config,cap_cycles;
    reg [7:0] cap_error;
    reg [AW:0] cap_runs;
    reg [21:0] cap_points;
    reg [10:0] cap_x0,cap_x1,cap_y0,cap_y1;
    wire rv,fd,fb;
    wire [10:0] rx0,rx1,ry;
    wire [31:0] rid;
    wire [21:0] pixels;wire [20:0] runs;
    wire release_frame=result_valid && result_ready;
    assign result_valid=complete[rd_bank];
    assign {result_frame_id,result_config,result_error,run_count,edge_points,x_min,x_max,y_min,y_max,frame_cycles}=completed_data[rd_bank];
    assign frame_ready=!occupied[wr_bank] || (release_frame && rd_bank==wr_bank);
    assign buffer_level={1'b0,occupied[0]}+{1'b0,occupied[1]};
    wire start_ok=in_start && in_valid && frame_ready && !active && !publish_pending;
    wire accept=in_valid && (start_ok || (active && !discard && !in_start));
    inspection_run_encoder #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT)) encoder(
        .clk(clk),.rst_n(rst_n),.in_valid(accept),.in_mask(in_edge),.in_frame_start(start_ok),
        .in_x(in_x),.in_y(in_y),.in_frame_id(in_frame_id),.run_valid(rv),.run_x0(rx0),.run_x1(rx1),.run_y(ry),
        .run_frame_id(rid),.frame_done(fd),.frame_bad(fb),.frame_pixels(pixels),.frame_runs(runs));
    wire save=rv && active && !discard && cap_runs<MAX_RUNS;
    wire [32:0] payload={ry,rx1,rx0};
    always @(posedge clk)begin
        if(rst_n && save)records[{wr_bank,cap_runs[AW-1:0]}]<={^payload,payload};
        record_q<=records[{rd_bank,record_index}];
        // 元数据与末段写入至少隔一拍；不在fd当拍截取尚未累加的末段计数。
        if(rst_n && publish_pending)completed_data[wr_bank]<=
            {cap_id,cap_config,cap_error,cap_runs,cap_points,cap_x0,cap_x1,cap_y0,cap_y1,cap_cycles};
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            wr_bank<=0;rd_bank<=0;occupied<=0;complete<=0;
            active<=0;discard<=0;encoded_done<=0;commit_seen<=0;publish_pending<=0;
            cap_id<=0;cap_config<=0;cap_error<=0;cap_runs<=0;cap_points<=0;cap_cycles<=0;
            cap_x0<=0;cap_x1<=0;cap_y0<=0;cap_y1<=0;fault<=0;fault_code<=0;
            read_pending<=0;read_bad<=0;record_valid<=0;record_error<=0;record_x0<=0;record_x1<=0;record_y<=0;
        end else begin
            record_valid<=read_pending;record_error<=0;read_pending<=record_read;
            if(record_read)read_bad<=!result_valid || record_frame_id!=result_frame_id ||
                {1'b0,record_index}>=run_count || result_error!=0 || (active && wr_bank==rd_bank) || release_frame;
            if(read_pending)begin
                record_error<=read_bad || ((^record_q)!==1'b0);
                {record_y,record_x1,record_x0}<=(read_bad || ((^record_q)!==1'b0))?33'd0:record_q[32:0];
                if(read_bad || ((^record_q)!==1'b0))begin fault<=1;if(!fault)fault_code<=8'h51;end
            end
            if(release_frame)begin complete[rd_bank]<=0;occupied[rd_bank]<=0;rd_bank<=!rd_bank;end
            if(active)cap_cycles<=cap_cycles+1'b1;
            if(publish_pending)begin
                complete[wr_bank]<=1;wr_bank<=!wr_bank;publish_pending<=0;
            end
            if(in_start && in_valid)begin
                if(!frame_ready)begin discard<=1;fault<=1;if(!fault)fault_code<=8'h52;end
                else if(active || publish_pending)begin
                    fault<=1;if(!fault)fault_code<=8'h53;
                    if(active)begin cap_error[4]<=1;active<=0;publish_pending<=1;end
                    discard<=1;
                end else begin
                    occupied[wr_bank]<=1;active<=1;discard<=0;encoded_done<=0;commit_seen<=0;
                    cap_id<=in_frame_id;cap_config<=in_config;cap_error<=in_error;cap_runs<=0;cap_points<=0;cap_cycles<=0;
                    cap_x0<=IMAGE_WIDTH-1;cap_x1<=0;cap_y0<=IMAGE_HEIGHT-1;cap_y1<=0;
                end
            end
            if(in_abort && active)begin
                cap_error<=cap_error | in_error | 8'h10;active<=0;publish_pending<=1;
                if((in_error & 8'hfb)!=0)begin fault<=1;if(!fault)fault_code<=8'h54;end
            end
            if(accept && (active || start_ok))begin
                if(in_error!=0)begin cap_error<=cap_error | in_error;if((in_error & 8'hfb)!=0)begin fault<=1;if(!fault)fault_code<=8'h54;end end
                if(!start_ok && (in_frame_id!=cap_id || in_config!=cap_config))begin cap_error[3]<=1;fault<=1;if(!fault)fault_code<=8'h54;end
                if(in_edge)begin
                    cap_points<=start_ok?22'd1:cap_points+1'b1;
                    if(start_ok || cap_points==0 || in_x<cap_x0)cap_x0<=in_x;
                    if(start_ok || cap_points==0 || in_x>cap_x1)cap_x1<=in_x;
                    if(start_ok || cap_points==0 || in_y<cap_y0)cap_y0<=in_y;
                    if(start_ok || cap_points==0 || in_y>cap_y1)cap_y1<=in_y;
                end
            end
            if(rv && active)begin
                if(rid!=cap_id)begin cap_error[2]<=1;fault<=1;if(!fault)fault_code<=8'h54;end
                if(cap_runs>=MAX_RUNS)cap_error[0]<=1;
                else cap_runs<=cap_runs+1'b1;
            end
            if(fd && active)begin
                encoded_done<=1;
                if(fb || pixels!=IMAGE_WIDTH*IMAGE_HEIGHT)begin cap_error[1]<=1;fault<=1;if(!fault)fault_code<=8'h55;end
            end
            if(in_commit && active)commit_seen<=1;
            if(active && encoded_done && commit_seen)begin active<=0;publish_pending<=1;end
        end
    end
endmodule
