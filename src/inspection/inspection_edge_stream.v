`timescale 1ns/1ps
// Canny完整输出入口：帧元数据先入队，随延后的边缘帧首出队；不读取分屏或加粗结果。
// 配置字由上层打包，必须包含阈值、滤波/算法开关及形态学模式。
module inspection_edge_stream #(
    parameter IMAGE_WIDTH=1920,IMAGE_HEIGHT=1080,CONFIG_WIDTH=32,FRAME_TIMEOUT=6400000,
    parameter VSYNC_ACTIVE_LEVEL=1'b0
)(
    input wire clk,rst_n,
    input wire source_valid,source_vsync,
    input wire [31:0] source_frame_id,
    input wire source_frame_valid,source_live,
    input wire [CONFIG_WIDTH-1:0] source_config,
    input wire edge_valid,edge_window_valid,edge_vsync,edge_pixel,
    input wire live_now,
    output reg out_valid,out_start,out_done,out_commit,out_abort,out_edge,out_usable,
    output reg [10:0] out_x,out_y,
    output reg [31:0] out_frame_id,
    output reg [CONFIG_WIDTH-1:0] out_config,
    output reg [7:0] frame_error,
    output reg fault,
    output reg [2:0] metadata_high_water,
    output reg [31:0] complete_frames
);
    localparam MW=CONFIG_WIDTH+34;
    reg [MW:0] metadata[0:3]; // 偶校验 + LIVE/有效/配置/frame_id；四个帧槽，无像素缓存。
    reg [1:0] wr,rd,source_slot;
    reg [2:0] level;
    reg source_started,edge_started,edge_complete;
    reg [21:0] source_count,edge_count;
    reg [31:0] frame_timer;
    reg [10:0] x,y;
    reg [31:0] source_id;
    reg [CONFIG_WIDTH-1:0] source_cfg;
    reg source_fv,source_lv,current_usable;
    wire source_active=source_vsync!=VSYNC_ACTIVE_LEVEL;
    wire edge_active=edge_vsync!=VSYNC_ACTIVE_LEVEL;
    wire source_first=source_active && source_valid && !source_started;
    wire edge_first=edge_active && edge_valid && !edge_started;
    wire pop=edge_first && (level!=0 || source_first);
    wire push=source_first && (level<4 || pop);
    wire [MW-1:0] payload={source_live,source_frame_valid,source_config,source_frame_id};
    wire [MW:0] head=(level==0 && push)?{^payload,payload}:metadata[rd];
    wire head_bad=(^head)!==1'b0;
    wire source_changed=source_valid && source_started &&
        (source_frame_id!=source_id || source_config!=source_cfg || source_frame_valid!=source_fv || source_live!=source_lv);
    wire source_data_error=source_frame_id!=source_id || source_frame_valid!=source_fv;
    wire accepted_pixel=edge_active && edge_valid && (!edge_started || !edge_complete);
    wire usable_first=pop && !head_bad && head[MW-1] && head[MW-2] && live_now;
    always @(posedge clk)begin
        if(rst_n && push)metadata[wr]<={^payload,payload};
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            wr<=0;rd<=0;source_slot<=0;level<=0;source_started<=0;edge_started<=0;edge_complete<=0;
            source_count<=0;edge_count<=0;x<=0;y<=0;source_id<=0;source_cfg<=0;source_fv<=0;source_lv<=0;current_usable<=0;
            out_valid<=0;out_start<=0;out_done<=0;out_commit<=0;out_abort<=0;out_edge<=0;out_usable<=0;out_x<=0;out_y<=0;frame_timer<=0;
            out_frame_id<=0;out_config<=0;frame_error<=0;fault<=0;metadata_high_water<=0;complete_frames<=0;
        end else begin
            out_valid<=0;out_start<=0;out_done<=0;out_commit<=0;out_abort<=0;
            if(edge_started && !edge_complete)begin
                if(frame_timer<FRAME_TIMEOUT)frame_timer<=frame_timer+1'b1;
                else begin fault<=1;frame_error[7]<=1;out_abort<=1;current_usable<=0;end
            end
            if(!source_active)begin
                if(source_started && source_count!=IMAGE_WIDTH*IMAGE_HEIGHT)begin fault<=1;frame_error[1]<=1;out_abort<=1;end
                source_started<=0;source_count<=0;
            end
            if(source_first)begin
                source_started<=1;source_count<=1;source_id<=source_frame_id;source_cfg<=source_config;
                source_fv<=source_frame_valid;source_lv<=source_live;source_slot<=wr;
            end else if(source_valid && source_active)begin
                if(source_count<IMAGE_WIDTH*IMAGE_HEIGHT)source_count<=source_count+1'b1;
                else begin fault<=1;frame_error[1]<=1;out_abort<=1;end
            end
            if(source_changed)begin
                // 正常配置/模式切换只取消该帧；ID/有效性中途损坏才锁存硬故障。
                if(source_data_error)fault<=1;
                if(source_data_error || source_config!=source_cfg)frame_error[2]<=1;
                out_abort<=1;current_usable<=0;
            end
            if(push)wr<=wr+1'b1;
            if(pop)rd<=rd+1'b1;
            case({push,pop})2'b10:level<=level+1'b1;2'b01:level<=level-1'b1;default:begin end endcase
            if(level>metadata_high_water)metadata_high_water<=level;
            if(source_first && !push)begin fault<=1;frame_error[3]<=1;out_abort<=1;end
            if(!edge_active)begin
                if(edge_started && !edge_complete)begin fault<=1;frame_error[4]<=1;out_abort<=1;end
                if(edge_started && edge_complete)out_commit<=1;
                edge_started<=0;edge_complete<=0;edge_count<=0;x<=0;y<=0;
            end
            if(edge_first)begin
                edge_started<=1;edge_count<=1;x<=1;y<=0;edge_complete<=0;frame_error<=0;frame_timer<=0;
                out_start<=1;out_x<=0;out_y<=0;
                out_frame_id<=pop?head[31:0]:32'd0;
                out_config<=pop?head[CONFIG_WIDTH+31:32]:{CONFIG_WIDTH{1'b0}};
                current_usable<=usable_first;out_usable<=usable_first;
                if(!pop || head_bad)begin fault<=1;frame_error[5]<=1;end
            end else if(accepted_pixel)begin
                edge_count<=edge_count+1'b1;out_x<=x;out_y<=y;out_usable<=current_usable && live_now;
                if(x==IMAGE_WIDTH-1)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
                if(edge_count==IMAGE_WIDTH*IMAGE_HEIGHT-1)begin
                    out_done<=1;edge_complete<=1;complete_frames<=complete_frames+1'b1;
                end
            end
            if(accepted_pixel)begin
                out_valid<=1;out_edge<=edge_window_valid && edge_pixel;
            end
            if(edge_valid && (!edge_active || edge_complete))begin fault<=1;frame_error[6]<=1;out_abort<=1;end
            if(!live_now)begin
                if(current_usable && edge_started && !edge_complete)out_abort<=1;
                current_usable<=0;out_usable<=0;
            end
        end
    end
endmodule
