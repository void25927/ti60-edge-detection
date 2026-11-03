`timescale 1ns/1ps
// 单器件边缘后端：碎段聚合→边缘矩主轴→原CORDIC→边缘跨度投影→六候选比较。
// 所有工作在同一像素时钟域。LIVE切换只取消在途任务，不清除已完成模板。
module inspection_edge_system #(
    parameter IMAGE_WIDTH=1920,IMAGE_HEIGHT=1080,MAX_RUNS=4096,POST_TIMEOUT=300000,CENTER_SELECT=0,EXTERNAL_LEARN=0,TRACK_FAILED=0
)(
    input wire clk,rst_n,
    input wire in_valid,in_start,in_edge,in_commit,in_abort,
    input wire [10:0] in_x,in_y,
    input wire [31:0] in_frame_id,in_config,
    input wire [7:0] in_error,
    input wire live_mode,learn_pending,detect_enabled,
    input wire [31:0] learn_frame_id,
    output wire result_valid,
    input wire result_ready,
    output reg [31:0] result_frame_id,
    output reg [15:0] result_track_id,
    output wire [1:0] result_status,
    output reg [10:0] center_x,center_y,
    output reg [7:0] result_reasons,
    output reg [2:0] result_count,
    output wire template_valid,template_learned,
    output wire [31:0] template_source_frame,template_config,
    output reg fault,
    output reg [7:0] fault_code,
    output reg [31:0] post_cycles,max_post_cycles,compare_cycles,accepted_frames,completed_frames,busy_frames,
    output wire [2:0] queue_depth,
    output reg [2:0] queue_high,
    input wire external_learn_start,
    output wire external_learn_ready,
    input wire [1837:0] external_descriptor,
    input wire [31:0] external_frame_id,external_config,
    input wire external_bad,
    output reg external_done,external_failed,
    output wire feature_valid,feature_bad,
    output wire [1837:0] feature_descriptor,
    output wire [31:0] feature_frame_id,feature_config
);
    localparam IDLE=0,TARGET=1,GEOMETRY=2,GEO_WAIT=3,TRIG=4,TRIG_WAIT=5,PROFILE=6,PROFILE_WAIT=7,COMPARE=8,COMPARE_WAIT=9,OUTPUT=10,ABORT=11;
    localparam AW=$clog2(MAX_RUNS);
    reg [3:0] state;
    reg live_d,identity_valid,task_bad,timeout_pulse,timed_out,track_continuous;
    reg [15:0] next_track,current_track;
    reg [10:0] old_x,old_y;
    reg anchor_valid;
    reg [10:0] anchor_x,anchor_y;
    reg [31:0] old_fid,task_config;
    reg [18:0] cx,cy;
    reg signed [15:0] axis,c,s;
    wire cancel=live_d && !live_mode;
    wire work_rst_n=rst_n && !cancel && !timeout_pulse;
    wire cv,cfault,rr,record_valid,record_error;
    wire capture_ready;wire [1:0] capture_level;
    wire [7:0] capture_fault_code;
    wire [31:0] fid,cfg,capture_cycles;
    wire [7:0] capture_error;
    wire [AW:0] runs;
    wire [10:0] rx0,rx1,ry;
    wire [AW-1:0] read_index;
    wire read_enable;
    assign queue_depth={1'b0,capture_level};
    wire release_capture=state==OUTPUT && result_ready;
    inspection_edge_runs #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),.MAX_RUNS(MAX_RUNS)) capture(
        .clk(clk),.rst_n(work_rst_n),.in_valid(in_valid && live_mode),.in_start(in_start && live_mode),.in_edge(in_edge),.in_commit(in_commit),.in_abort(in_abort),
        .in_x(in_x),.in_y(in_y),.in_frame_id(in_frame_id),.in_config(in_config),.in_error(in_error),
        .result_valid(cv),.result_ready(release_capture),.result_frame_id(fid),.result_config(cfg),.result_error(capture_error),.run_count(runs),
        .edge_points(),.x_min(),.x_max(),.y_min(),.y_max(),.frame_cycles(capture_cycles),.fault(cfault),.fault_code(capture_fault_code),.frame_ready(capture_ready),.buffer_level(capture_level),
        .record_read(read_enable),.record_index(read_index),.record_frame_id(result_frame_id),.record_valid(record_valid),.record_error(record_error),.record_x0(rx0),.record_x1(rx1),.record_y(ry));
    wire tr,tv,tbad,treq;wire [AW-1:0] ti;
    wire [31:0] tfid,tcycles,taccess,twait,sx,sy;
    wire [21:0] points;
    wire [43:0] sxx,syy,sxy;
    wire [10:0] tx0,tx1,ty0,ty1;wire [7:0] treasons;
    wire mask_v,mask_bad,mask_selected;
    wire preq;wire [AW-1:0] pi;
    assign read_enable=(state==TARGET)?treq:((state==PROFILE_WAIT || state==PROFILE)?preq:1'b0);
    assign read_index=(state==TARGET)?ti:pi;
    wire [10:0] focus_cx=(learn_pending || !anchor_valid)?IMAGE_WIDTH/2:anchor_x;
    wire [10:0] focus_cy=(learn_pending || !anchor_valid)?IMAGE_HEIGHT/2:anchor_y;
    inspection_edge_target #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),.MAX_RUNS(MAX_RUNS),.CENTER_SELECT(CENTER_SELECT)) target(
        .clk(clk),.rst_n(work_rst_n),.start(state==IDLE && cv && live_mode),.ready(tr),.frame_id(fid),.run_count(runs),.frame_error(capture_error),.focus_x(focus_cx),.focus_y(focus_cy),
        .record_read(treq),.record_index(ti),.record_valid(record_valid && state==TARGET),.record_error(record_error),.record_x0(rx0),.record_x1(rx1),.record_y(ry),
        .result_valid(tv),.result_ready(release_capture),.result_frame_id(tfid),.uncertain(tbad),.reasons(treasons),.edge_points(points),
        .sum_x(sx),.sum_y(sy),.sum_xx(sxx),.sum_yy(syy),.sum_xy(sxy),.x0(tx0),.x1(tx1),.y0(ty0),.y1(ty1),.cycles(tcycles),.accesses(taccess),.max_wait(twait),
        .mask_read(preq && state==PROFILE_WAIT),.mask_index(pi),.mask_valid(mask_v),.mask_error(mask_bad),.mask_selected(mask_selected));
    wire gr,gv,gb,gm;wire [31:0] gfid;wire [2:0] goid;wire [18:0] gcx,gcy;wire signed [15:0] ga;
    inspection_geometry geometry(.clk(clk),.rst_n(work_rst_n),.in_valid(state==GEOMETRY),.in_ready(gr),.in_frame_id(result_frame_id),.in_object_id(3'd1),
        .in_area(points),.in_sum_x(sx),.in_sum_y(sy),.in_sum_xx(sxx),.in_sum_yy(syy),.in_sum_xy(sxy),
        .out_valid(gv),.out_ready(state==GEO_WAIT),.out_frame_id(gfid),.out_object_id(goid),.center_x_q8(gcx),.center_y_q8(gcy),.axis_angle_q8(ga),.axis_unreliable(gb),.invalid_moments(gm));
    wire ar,av,abad;wire [31:0] afid;wire [2:0] aoid;wire signed [15:0] ac,asine;
    inspection_angle_sincos trig(.clk(clk),.rst_n(work_rst_n),.in_valid(state==TRIG),.in_ready(ar),.frame_id(result_frame_id),.template_frame_id(result_frame_id),.object_id(3'd1),.angle_q8({axis[15],axis}),
        .out_valid(av),.out_ready(state==TRIG_WAIT),.out_frame_id(afid),.out_template_id(),.out_object_id(aoid),.cosine_q14(ac),.sine_q14(asine),.invalid_angle(abad));
    wire pr,pv,pbad;wire [31:0] pfid,profile_cycles;wire [2:0] poid;wire [1837:0] profile;
    wire profile_read_bad=record_error || mask_bad || !mask_v;
    inspection_axial_profile #(.MAX_RUNS(MAX_RUNS),.EDGE_FEATURES(1)) projector(.clk(clk),.rst_n(work_rst_n),.start_valid(state==PROFILE),.start_ready(pr),
        .frame_id(result_frame_id),.object_id(3'd1),.run_count(runs),.center_x_q8(cx),.center_y_q8(cy),.cosine_q14(c),.sine_q14(s),.invalid_geometry(task_bad),
        .record_read(preq),.record_index(pi),.record_valid(record_valid && state==PROFILE_WAIT),.record_frame_id(profile_read_bad?~result_frame_id:result_frame_id),
        .record_x0(rx0),.record_x1(rx1),.record_y(ry),.record_object_id(mask_selected?3'd1:3'd0),
        .result_valid(pv),.result_ready(state==OUTPUT && result_ready),.result_frame_id(pfid),.result_object_id(poid),.descriptor(profile),.invalid(pbad),.cycles(profile_cycles),.accesses(),.max_wait());
    wire cr,crv,learn_rejected;wire [1:0] status;wire [7:0] creasons;wire [31:0] cfid,ccycles;wire [15:0] ctid;
    // 中央优先是目标选择策略，不是“必须含引脚”的器件类型限制。
    wire external_busy=EXTERNAL_LEARN && (state==12 || state==13);
    assign external_learn_ready=EXTERNAL_LEARN && state==IDLE && !cv && live_mode;
    assign feature_valid=state==PROFILE_WAIT && pv;
    assign feature_bad=task_bad || pbad || pfid!=result_frame_id;
    assign feature_descriptor=profile;assign feature_frame_id=pfid;assign feature_config=task_config;
    inspection_edge_compare #(.REQUIRE_BODY(0)) compare(.clk(clk),.rst_n(rst_n),.cancel(cancel || timeout_pulse),.start(state==COMPARE || (EXTERNAL_LEARN && state==12)),.ready(cr),.descriptor(external_busy?external_descriptor:profile),
        .frame_id(external_busy?external_frame_id:result_frame_id),.config_word(external_busy?external_config:task_config),.track_id(external_busy?16'd0:result_track_id),.invalid(external_busy?external_bad:task_bad),
        .learn(external_busy || (learn_pending && learn_frame_id==result_frame_id)),.enable(detect_enabled && !external_busy),.result_valid(crv),.result_ready(release_capture || (external_busy && state==13)),
        .result_frame_id(cfid),.result_track_id(ctid),.status(status),.reasons(creasons),.template_valid(template_valid),.learned(template_learned),.learn_rejected(learn_rejected),
        .template_frame_id(template_source_frame),.template_config(template_config),.cycles(ccycles),.best_score());
    assign result_valid=state==OUTPUT && crv && live_mode;
    assign result_status=result_valid && !task_bad && cfid==result_frame_id && ctid==result_track_id?status:2'd0;
    wire [10:0] step_x=(gcx[18:8]>old_x)?gcx[18:8]-old_x:old_x-gcx[18:8];
    wire [10:0] step_y=(gcy[18:8]>old_y)?gcy[18:8]-old_y:old_y-gcy[18:8];
    wire [11:0] box_width={1'b0,tx1}-{1'b0,tx0}+12'd1;
    wire [11:0] box_height={1'b0,ty1}-{1'b0,ty0}+12'd1;
    // 近各向同性且外接框近方时，零度参考轴是有效约定，而非几何错误。
    // 圆形无需估计不存在的唯一主轴；非近圆的低置信方向仍拒绝。
    wire round_axis_fallback=gb && !gm &&
        box_width<=box_height+(box_height>>3)+12'd4 &&
        box_height<=box_width+(box_width>>3)+12'd4;
    wire axis_reject=gb && !round_axis_fallback;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            external_done<=0;external_failed<=0;state<=IDLE;live_d<=0;identity_valid<=0;task_bad<=0;timeout_pulse<=0;timed_out<=0;next_track<=1;current_track<=0;result_frame_id<=0;result_track_id<=0;task_config<=0;
            center_x<=0;center_y<=0;old_x<=0;old_y<=0;old_fid<=0;cx<=0;cy<=0;axis<=0;c<=0;s<=0;fault<=0;fault_code<=0;result_reasons<=0;result_count<=0;
            post_cycles<=0;max_post_cycles<=0;compare_cycles<=0;accepted_frames<=0;completed_frames<=0;busy_frames<=0;queue_high<=0;
            anchor_valid<=0;anchor_x<=0;anchor_y<=0;track_continuous<=0;
        end else begin
            external_done<=0;
            live_d<=live_mode;
            timeout_pulse<=0;
            // 缺脚会移动边缘质心；不得把失败样本质心当作下一帧选取中心。
            if((template_learned && !external_busy) || (state==COMPARE_WAIT && crv && status==1 && !task_bad))begin
                anchor_valid<=1;anchor_x<=center_x;anchor_y<=center_y;
            end
            // 累计判定时，连续身份且几何可靠的未通过件也必须持续跟踪。
            // 只更新空间搜索锚点，不改变FAIL评分；身份跳变、遮挡和错误均不更新。
            if(TRACK_FAILED && state==COMPARE_WAIT && crv && status==2 && !task_bad && track_continuous)begin
                anchor_valid<=1;anchor_x<=center_x;anchor_y<=center_y;
            end
            // 外部录入来自已显示的历史特征，不能挪用当前分析帧的质心作为锚点。
            if(template_learned && external_busy)begin anchor_valid<=0;identity_valid<=0;end
            if(queue_depth>queue_high)queue_high<=queue_depth;
            if(in_start && in_valid && live_mode)accepted_frames<=accepted_frames+1'b1;
            // 新帧可写另一组RAM；仅两组都被占用才是真正的吞吐/背压故障。
            if(in_start && in_valid && live_mode && !capture_ready)begin busy_frames<=busy_frames+1'b1;fault<=1;if(!fault)fault_code<=8'h56;end
            if(state!=IDLE && state!=OUTPUT)post_cycles<=post_cycles+1'b1;
            case(state)
                IDLE:if(EXTERNAL_LEARN && external_learn_start && external_learn_ready)begin state<=12;post_cycles<=0;external_failed<=0;timed_out<=0;end
                else if(cv && live_mode)begin
                    result_frame_id<=fid;result_track_id<=0;task_config<=cfg;post_cycles<=0;task_bad<=capture_error!=0;timed_out<=0;result_reasons<=capture_error;result_count<=0;
                    state<=TARGET;
                end
                TARGET:if(tv)begin
                    task_bad<=task_bad || tbad || tfid!=result_frame_id;result_reasons<=treasons;
                    if(tbad || tfid!=result_frame_id)begin identity_valid<=0;anchor_valid<=0;state<=COMPARE;end else state<=GEOMETRY;
                end
                GEOMETRY:if(gr)state<=GEO_WAIT;
                GEO_WAIT:if(gv)begin
                    track_continuous<=identity_valid && result_frame_id==old_fid+32'd1 && step_x<=32 && step_y<=32;
                    cx<=gcx;cy<=gcy;axis<=round_axis_fallback?16'sd0:ga;center_x<=gcx[18:8];center_y<=gcy[18:8];
                    task_bad<=task_bad || axis_reject || gm || gfid!=result_frame_id;result_count<=axis_reject || gm?3'd0:3'd1;
                    if(!identity_valid || result_frame_id!=old_fid+1'b1 || step_x>32 || step_y>32)begin result_track_id<=next_track;current_track<=next_track;next_track<=next_track+1'b1;end
                    else result_track_id<=current_track;
                    old_x<=gcx[18:8];old_y<=gcy[18:8];old_fid<=result_frame_id;identity_valid<=!axis_reject && !gm;
                    state<=axis_reject || gm || gfid!=result_frame_id?COMPARE:TRIG;
                end
                TRIG:if(ar)state<=TRIG_WAIT;
                TRIG_WAIT:if(av)begin c<=ac;s<=asine;task_bad<=task_bad || abad || afid!=result_frame_id;state<=PROFILE;end
                PROFILE:if(pr)state<=PROFILE_WAIT;
                PROFILE_WAIT:if(pv)begin task_bad<=task_bad || pbad || pfid!=result_frame_id;state<=COMPARE;end
                COMPARE:if(cr)state<=COMPARE_WAIT;
                COMPARE_WAIT:if(crv)begin
                    result_reasons<=result_reasons | creasons;compare_cycles<=ccycles;
                    if(post_cycles>max_post_cycles)max_post_cycles<=post_cycles;state<=OUTPUT;
                end
                OUTPUT:if(result_ready)begin completed_frames<=completed_frames+1'b1;state<=IDLE;end
                12:if(cr)state<=13;
                13:if(crv)begin external_done<=1;external_failed<=learn_rejected || !template_valid;state<=IDLE;end
                ABORT:if(!timeout_pulse)state<=COMPARE;
                default:state<=IDLE;
            endcase
            if(cfault)begin fault<=1;if(!fault)fault_code<=capture_fault_code;end
            if(state!=IDLE && state!=OUTPUT && post_cycles>=POST_TIMEOUT && !timed_out)begin
                fault<=1;if(!fault)fault_code<=8'h57;task_bad<=1;result_reasons[7]<=1;
                timed_out<=1;timeout_pulse<=1;identity_valid<=0;state<=ABORT;
                if(external_busy)begin external_done<=1;external_failed<=1;state<=IDLE;end
            end
            if(cancel)begin if(external_busy)begin external_done<=1;external_failed<=1;end state<=IDLE;identity_valid<=0;anchor_valid<=0;result_count<=0;result_reasons<=0;end
        end
    end
endmodule
