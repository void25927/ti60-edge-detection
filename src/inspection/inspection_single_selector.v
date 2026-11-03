`timescale 1ns/1ps
// 单个真实器件的保守候选选择。保留原始连通域，不改轮廓/面积或判定阈值。
// 无轨迹时不能仅按面积选最大块；已知轨迹之外的小干扰还必须远离目标。
module inspection_single_selector #(
    parameter MAX_STEP=32, GUARD=8
)(
    input wire clk,rst_n,clear,
    input wire in_valid,
    output wire in_ready,
    input wire [31:0] frame_id,
    input wire [2:0] count,
    input wire [7:0] frame_error,
    input wire [87:0] areas,
    input wire [43:0] boxes_x0,boxes_x1,boxes_y0,boxes_y1,
    input wire [3:0] invalid_objects,
    output reg out_valid,
    input wire out_ready,
    output reg [31:0] out_frame_id,
    output reg selected_valid,uncertain,
    output reg [1:0] selected_index,
    output reg [2:0] ignored_count,
    output reg [31:0] cycles
);
    localparam IDLE=0,SCAN=1,DECIDE=2,CHECK=3,FINISH=4,OUTPUT=5,SCAN_CENTER=6,SCAN_MATCH=7,CHECK_USE=8;
    reg [3:0] state;
    reg [2:0] n,index,matches,persistent;
    reg [1:0] choice,continued;
    reg [87:0] a;
    reg [43:0] x0,x1,y0,y1;
    reg [3:0] bad;
    reg input_bad,unsafe;
    reg anchor,have;
    reg [31:0] last_id;
    reg [10:0] ax,ay,ax0,ax1,ay0,ay1;
    reg [21:0] aa;
    reg [3:0] previous_valid;
    reg [10:0] previous_x[0:3],previous_y[0:3];
    reg [21:0] previous_area[0:3];
    reg [21:0] ref_area;
    reg [10:0] ref_x0,ref_x1,ref_y0,ref_y1;
    wire [10:0] ix0=x0[index[1:0]*11+:11],ix1=x1[index[1:0]*11+:11];
    wire [10:0] iy0=y0[index[1:0]*11+:11],iy1=y1[index[1:0]*11+:11];
    wire [21:0] ia=a[index[1:0]*22+:22];
    // 只锁存当前候选，不复制4目标描述；index保持至关联/边界比较完成。
    reg [21:0] qa;
    reg [10:0] qx0,qx1,qy0,qy1,mx,my;
    reg qbad;
    wire [11:0] xsum={1'b0,qx0}+{1'b0,qx1},ysum={1'b0,qy0}+{1'b0,qy1};
    wire [21:0] adiff=qa>aa?qa-aa:aa-qa;
    wire [21:0] area_gate=(aa>>3)<32?22'd32:(aa>>3);
    wire [21:0] noise_limit=(ref_area>>6)<16?22'd16:(ref_area>>6);
    wire separate=({1'b0,qx1}+GUARD<{1'b0,ref_x0}) ||
                  ({1'b0,ref_x1}+GUARD<{1'b0,qx0}) ||
                  ({1'b0,qy1}+GUARD<{1'b0,ref_y0}) ||
                  ({1'b0,ref_y1}+GUARD<{1'b0,qy0});
    function [10:0] distance;
        input [10:0] p,q;
        begin distance=p>q?p-q:q-p;end
    endfunction
    integer k,history_index;
    reg seen_before;
    always @(*)begin
        seen_before=0;
        for(history_index=0;history_index<4;history_index=history_index+1)if(previous_valid[history_index] && distance(mx,previous_x[history_index])<=MAX_STEP &&
            distance(my,previous_y[history_index])<=MAX_STEP &&
            (qa>previous_area[history_index]?qa-previous_area[history_index]:previous_area[history_index]-qa)<=((qa>>3)<32?22'd32:(qa>>3)))seen_before=1;
    end
    assign in_ready=state==IDLE;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;out_valid<=0;selected_valid<=0;selected_index<=0;uncertain<=0;ignored_count<=0;
            anchor<=0;have<=0;last_id<=0;previous_valid<=0;cycles<=0;out_frame_id<=0;
            a<=0;x0<=0;x1<=0;y0<=0;y1<=0;bad<=0;n<=0;index<=0;matches<=0;persistent<=0;choice<=0;continued<=0;
            aa<=0;ax<=0;ay<=0;ax0<=0;ax1<=0;ay0<=0;ay1<=0;input_bad<=0;unsafe<=0;
            ref_area<=0;ref_x0<=0;ref_x1<=0;ref_y0<=0;ref_y1<=0;
            qa<=0;qx0<=0;qx1<=0;qy0<=0;qy1<=0;mx<=0;my<=0;qbad<=0;
        end else if(clear)begin
            state<=IDLE;out_valid<=0;selected_valid<=0;uncertain<=0;anchor<=0;have<=0;previous_valid<=0;
        end else begin
            if(state!=IDLE && state!=OUTPUT)cycles<=cycles+1'b1;
            case(state)
                IDLE:if(in_valid)begin
                    a<=areas;x0<=boxes_x0;x1<=boxes_x1;y0<=boxes_y0;y1<=boxes_y1;bad<=invalid_objects;
                    n<=count;out_frame_id<=frame_id;input_bad<=frame_error!=0 || count>4;
                    if(have && frame_id!=last_id+32'd1)begin anchor<=0;previous_valid<=0;end
                    last_id<=frame_id;have<=1;index<=0;matches<=0;persistent<=0;unsafe<=0;
                    selected_valid<=0;uncertain<=0;ignored_count<=0;cycles<=0;state<=SCAN;
                end
                SCAN:if(index<n && index<4)begin
                    qa<=ia;qx0<=ix0;qx1<=ix1;qy0<=iy0;qy1<=iy1;qbad<=bad[index[1:0]];state<=SCAN_CENTER;
                end else state<=DECIDE;
                SCAN_CENTER:begin
                    mx<=xsum[11:1];my<=ysum[11:1];
                    if(qbad || qa==0 || qx0==0 || qy0==0 || qx1>=1919 || qy1>=1079 || qx0>qx1 || qy0>qy1)unsafe<=1;
                    state<=SCAN_MATCH;
                end
                SCAN_MATCH:begin
                    if(anchor && distance(mx,ax)<=MAX_STEP && distance(my,ay)<=MAX_STEP && adiff<=area_gate)begin matches<=matches+1'b1;choice<=index[1:0];end
                    if(seen_before)begin persistent<=persistent+1'b1;continued<=index[1:0];end
                    index<=index+1'b1;state<=SCAN;
                end
                DECIDE:begin
                    if(input_bad || n==0 || unsafe)begin uncertain<=input_bad || unsafe;state<=FINISH;end
                    else if(anchor && matches==1)begin index<=0;state<=CHECK;end
                    else if(!anchor && n==1)begin choice<=0;index<=0;state<=CHECK;end
                    else if(!anchor && persistent==1)begin choice<=continued;index<=0;state<=CHECK;end
                    else begin uncertain<=1;state<=FINISH;end
                    // CHECK随后使用选中候选的原始范围，不使用最大块排序。
                    if(anchor && matches==1)begin
                        ref_area<=a[choice*22+:22];ref_x0<=x0[choice*11+:11];ref_x1<=x1[choice*11+:11];ref_y0<=y0[choice*11+:11];ref_y1<=y1[choice*11+:11];
                    end else if(!anchor && (n==1 || persistent==1))begin
                        ref_area<=a[(n==1?2'd0:continued)*22+:22];
                        ref_x0<=x0[(n==1?2'd0:continued)*11+:11];ref_x1<=x1[(n==1?2'd0:continued)*11+:11];
                        ref_y0<=y0[(n==1?2'd0:continued)*11+:11];ref_y1<=y1[(n==1?2'd0:continued)*11+:11];
                    end
                end
                CHECK:if(index<n && index<4)begin
                    qa<=ia;qx0<=ix0;qx1<=ix1;qy0<=iy0;qy1<=iy1;state<=CHECK_USE;
                end else begin
                    selected_valid<=!unsafe;uncertain<=unsafe;selected_index<=choice;state<=FINISH;
                end
                CHECK_USE:begin
                    if(index!=choice)begin
                        if(qa>noise_limit || !separate)unsafe<=1;
                        else ignored_count<=ignored_count+1'b1;
                    end
                    index<=index+1'b1;state<=CHECK;
                end
                FINISH:begin
                    anchor<=selected_valid && !uncertain;
                    if(selected_valid && !uncertain)begin
                        aa<=ref_area;ax0<=ref_x0;ax1<=ref_x1;ay0<=ref_y0;ay1<=ref_y1;
                        ax<=({1'b0,ref_x0}+{1'b0,ref_x1})>>1;ay<=({1'b0,ref_y0}+{1'b0,ref_y1})>>1;
                    end
                    previous_valid<=input_bad?4'd0:((5'd1<<n)-1'b1);
                    for(k=0;k<4;k=k+1)begin
                        previous_x[k]<=({1'b0,x0[k*11+:11]}+{1'b0,x1[k*11+:11]})>>1;
                        previous_y[k]<=({1'b0,y0[k*11+:11]}+{1'b0,y1[k*11+:11]})>>1;
                        previous_area[k]<=a[k*22+:22];
                    end
                    out_valid<=1;state<=OUTPUT;
                end
                OUTPUT:if(out_ready)begin out_valid<=0;state<=IDLE;end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
