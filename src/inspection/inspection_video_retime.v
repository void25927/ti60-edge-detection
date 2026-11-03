`timescale 1ns/1ps
// 检测专用同步FIFO：接收DDR预取RGB，按HDMI有效行节奏读出；不背压主视频。
module inspection_video_retime #(
    parameter ADDRESS_BITS=12,LINE_WIDTH=1920
)(
    input wire clk,rst_n,in_valid,in_vsync,
    input wire [23:0] in_rgb,
    input wire [31:0] in_frame_id,
    input wire in_frame_valid,in_live,
    input wire display_de,display_vsync,
    output reg out_valid,out_vsync,
    output reg [23:0] out_rgb,
    output reg [31:0] out_frame_id,
    output wire out_frame_valid,
    output reg out_live,
    output reg fault,
    output reg [ADDRESS_BITS:0] high_water,low_water
);
    localparam DEPTH=1<<ADDRESS_BITS;
    reg [25:0] memory[0:DEPTH-1]; // 偶校验、首像素标记和RGB888
    reg [25:0] read_q,forward_q;
    reg forward_valid;
    reg [33:0] metadata[0:1]; // 每帧只存一次完整ID、valid和LIVE快照
    reg [ADDRESS_BITS-1:0] wr,rd;
    reg [ADDRESS_BITS:0] level;
    reg in_vs_d,input_first,write_slot,read_slot;
    reg output_started,output_enable,frame_bad,current_valid;
    reg [31:0] captured_id;
    reg [1:0] metadata_bad;
    reg active_slot,captured_valid;
    wire marker=input_first;
    wire begin_display=display_de && !output_started;
    wire read_allow=output_enable || (begin_display && level>=LINE_WIDTH);
    wire pop=display_de && read_allow && level!=0;
    wire push=in_valid && (level<DEPTH || pop);
    // 同步预取下一队首；同拍写入预取地址时旁路新数据，保持原有对外延迟。
    wire [ADDRESS_BITS-1:0] prefetch_address=pop?(rd+1'b1):rd;
    wire [24:0] write_data={marker,in_rgb};
    wire [25:0] head=forward_valid?forward_q:read_q;
    wire head_bad=(^head)!==1'b0;
    assign out_frame_valid=current_valid && !frame_bad && !metadata_bad[active_slot];
    // 同步读写推断块RAM；RAM内容不复位，只复位指针和有效状态。
    always @(posedge clk)begin
        if(rst_n && push)memory[wr]<={^write_data,write_data};
        if(push && marker)metadata[write_slot]<={in_frame_valid,in_live,in_frame_id};
        read_q<=memory[prefetch_address];
        forward_valid<=rst_n && push && wr==prefetch_address;
        if(push)forward_q<={^write_data,write_data};
        if(pop)out_rgb<=head[23:0];
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            wr<=0;rd<=0;level<=0;in_vs_d<=0;input_first<=1;write_slot<=0;read_slot<=0;
            output_started<=0;output_enable<=0;frame_bad<=0;current_valid<=0;
            out_valid<=0;out_vsync<=0;out_frame_id<=0;out_live<=0;fault<=0;high_water<=0;low_water<=DEPTH;
            captured_id<=0;metadata_bad<=0;active_slot<=0;captured_valid<=0;
        end else begin
            in_vs_d<=in_vsync;out_vsync<=display_vsync;out_valid<=pop;
            if(in_vsync && !in_vs_d)input_first<=1;
            if(in_valid && !push)begin fault<=1;frame_bad<=1;end
            if(push)begin
                wr<=wr+1'b1;input_first<=0;
                if(marker)begin
                    write_slot<=~write_slot;captured_id<=in_frame_id;captured_valid<=in_frame_valid;metadata_bad[write_slot]<=0;
                end else if(captured_valid && (in_frame_id!=captured_id || !in_frame_valid))begin
                    metadata_bad[!write_slot]<=1;fault<=1;
                end
            end
            if(pop)begin
                rd<=rd+1'b1;
                // 元数据按显示帧首消耗；首字损坏也必须前进，不能使后续帧错配。
                if(begin_display)begin
                    out_frame_id<=metadata[read_slot][31:0];out_live<=metadata[read_slot][32];current_valid<=metadata[read_slot][33];
                    active_slot<=read_slot;
                    read_slot<=~read_slot;
                end
                if(head_bad)begin
                    frame_bad<=1;current_valid<=0;
                    // 上游明确无效的启动帧不参与检测；有效帧损坏必须锁存故障。
                    if(begin_display?metadata[read_slot][33]:current_valid)fault<=1;
                end else if((head[24]&&!begin_display)||(!head[24]&&begin_display))begin
                    frame_bad<=1;fault<=1;
                end
            end
            case({push,pop})2'b10:level<=level+1'b1;2'b01:level<=level-1'b1;default:begin end endcase
            if(level>high_water)high_water<=level;
            if(output_enable && level<low_water)low_water<=level;
            if(!display_vsync)begin output_started<=0;output_enable<=0;frame_bad<=0;end
            else if(begin_display)begin
                output_started<=1;output_enable<=level>=LINE_WIDTH;
                if(level<LINE_WIDTH && in_frame_valid)begin fault<=1;frame_bad<=1;end
            end
            if(display_de && output_enable && level==0)begin fault<=1;frame_bad<=1;end
        end
    end
endmodule
