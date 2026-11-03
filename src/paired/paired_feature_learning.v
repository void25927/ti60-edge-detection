`timescale 1ns/1ps
// 显示端长按查询该显示帧的特征，等待后台空闲后录入；绝不改录未来帧。
module paired_feature_learning(
 input wire clk,rst_n,live,
 input wire allocate,
 input wire [1:0] allocate_slot,
 input wire feature_valid,feature_bad,
 input wire [1837:0] feature_descriptor,
 input wire [31:0] feature_id,feature_config,
 input wire lookup_valid,
 input wire [1:0] lookup_slot,
 input wire [31:0] lookup_epoch,current_epoch,
 input wire learn_command,display_valid,
 input wire [31:0] display_id,display_config,display_epoch,current_config,
 output wire learn_allowed,
 output wire external_start,
 input wire external_ready,external_done,
 output wire [1837:0] external_descriptor,
 output wire [31:0] external_id,external_config,
 output wire external_bad,
 output wire fault
);
 reg storing,store_bad,local_fault;reg [3:0] index;
 reg feature_pending,feature_allowed_q;
 reg [1:0] slot_q;
 reg [831:0] captured;
 reg [31:0] fid_q,cfg_q,epoch_q;
 wire wr;
 reg [2:0] state;localparam IDLE=0,QUERY=1,SEND=2,WAIT=3;
 reg [31:0] requested_id,requested_config,requested_epoch;
 wire qr,ov,ob,cache_fault;wire [31:0] ofid,ocfg;
 wire consume=(!live)||(state==WAIT&&external_done);
 inspection_display_features cache(clk,rst_n,allocate,allocate_slot,storing,wr,slot_q,index,captured[63:0],index==12,store_bad,fid_q,cfg_q,epoch_q,
  state==QUERY,qr,requested_id,requested_epoch,ov,consume,external_descriptor,ofid,ocfg,ob,cache_fault);
 assign learn_allowed=state==IDLE&&!fault;
 assign external_start=state==SEND&&ov&&live;
 assign external_id=ofid;assign external_config=ocfg;
 assign external_bad=ob||ofid!=requested_id||ocfg!=requested_config||ocfg!=current_config;
 assign fault=cache_fault||local_fault;
 // captured仅在storing有效时读取；每次必须先完整锁存，不需要整组复位。
 always @(posedge clk)begin
  if(rst_n&&feature_valid&&!storing&&!feature_pending)
   captured<={18'd0,feature_descriptor[1837:1024]};
  else if(storing&&wr)captured<={64'd0,captured[831:64]};
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin feature_pending<=0;feature_allowed_q<=0;storing<=0;store_bad<=0;local_fault<=0;index<=0;slot_q<=0;fid_q<=0;cfg_q<=0;epoch_q<=0;state<=IDLE;requested_id<=0;requested_config<=0;requested_epoch<=0;end
  else begin
   if(storing&&wr)begin if(index==12)storing<=0;else index<=index+1'b1;end
   feature_pending<=0;
   if(feature_pending&&feature_allowed_q&&epoch_q==current_epoch)begin storing<=1;index<=0;end
   // 先保存字段，下一拍决定是否写缓存；查找/时代比较不再控制百位数据寄存器CE。
   if(feature_valid)begin
    if(storing||feature_pending)begin if(lookup_valid&&lookup_epoch==current_epoch)local_fault<=1;end
    else begin
     feature_pending<=1;feature_allowed_q<=lookup_valid&&lookup_epoch==current_epoch;
     fid_q<=feature_id;cfg_q<=feature_config;epoch_q<=lookup_epoch;slot_q<=lookup_slot;store_bad<=feature_bad;
    end
   end
   case(state)
    IDLE:if(learn_command&&learn_allowed&&display_valid&&live)begin requested_id<=display_id;requested_config<=display_config;requested_epoch<=display_epoch;state<=QUERY;end
    QUERY:if(qr)state<=SEND;
    SEND:if(external_start&&external_ready)state<=WAIT;
    WAIT:if(external_done)state<=IDLE;
    default:begin local_fault<=1;state<=IDLE;end
   endcase
   if(!live)state<=IDLE;
  end
 end
endmodule
