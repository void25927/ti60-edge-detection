
// Efinity Top-level template
// Version: 2023.2.307.5.10
// Date: 2026-10-29 19:21

// Copyright (C) 2013 - 2023 Efinix Inc. All rights reserved.

// This file may be used as a starting point for Efinity synthesis top-level target.
// The port list here matches what is expected by Efinity constraint files generated
// by the Efinity Interface Designer.

// To use this:
//     #1)  Save this file with a different name to a different directory, where source files are kept.
//              Example: you may wish to save as D:\FPGA_Edge_Detection\project\Ti60_Edge_Detection.v
//     #2)  Add the newly saved file into Efinity project as design file
//     #3)  Edit the top level entity in Efinity project to:  Ti60_Edge_Detection
//     #4)  Insert design content.


module Ti60_Edge_Detection
(
  input clk_24m,
  input sys_pll_lock,
  input ddr_pll_lock,
  input core_clk,
  input tdqss_clk,
  input tac_clk,
  input twd_clk,
  input clk_sys,
  input clk_pixel_2x,
  input clk_pixel_10x,
  input csi_rxc_i,
  input csi_ctl0_i,
  input csi_ctl1_i,
  input csi_scl_i,
  input csi_sda_i,
  input [15:0] i_dq_hi,
  input [15:0] i_dq_lo,
  input [1:0] i_dqs_hi,
  input [1:0] i_dqs_lo,
  input ex_key_down_n,
  input ex_key_up_n,
  input [1:0] key_data,
  input csi_rxc_lp_n_i,
  input csi_rxc_lp_p_i,
  input [7:0] csi_rxd0_hs_i,
  input csi_rxd0_lp_n_i,
  input csi_rxd0_lp_p_i,
  input [7:0] csi_rxd1_hs_i,
  input csi_rxd1_lp_n_i,
  input csi_rxd1_lp_p_i,
  input [7:0] csi_rxd2_hs_i,
  input csi_rxd2_lp_n_i,
  input csi_rxd2_lp_p_i,
  input [7:0] csi_rxd3_hs_i,
  input csi_rxd3_lp_n_i,
  input csi_rxd3_lp_p_i,
  output [5:0] led_o,
  output sys_pll_rstn_o,
  output ddr_pll_rstn_o,
  output [2:0] shift,
  output shift_ena,
  output [4:0] shift_sel,
  output hdmi_txc_oe,
  output [9:0] hdmi_txc_o,
  output hdmi_txc_rst_o,
  output hdmi_txd0_oe,
  output [9:0] hdmi_txd0_o,
  output hdmi_txd0_rst_o,
  output hdmi_txd1_oe,
  output [9:0] hdmi_txd1_o,
  output hdmi_txd1_rst_o,
  output hdmi_txd2_oe,
  output [9:0] hdmi_txd2_o,
  output hdmi_txd2_rst_o,
  output [15:0] addr,
  output [2:0] ba,
  output cas,
  output cke,
  output clk_n_hi,
  output clk_n_lo,
  output clk_p_hi,
  output clk_p_lo,
  output cs,
  output csi_ctl0_o,
  output csi_ctl0_oe,
  output csi_ctl1_o,
  output csi_ctl1_oe,
  output csi_scl_o,
  output csi_scl_oe,
  output csi_sda_o,
  output csi_sda_oe,
  output [1:0] o_dm_hi,
  output [1:0] o_dm_lo,
  output [15:0] o_dq_hi,
  output [15:0] o_dq_lo,
  output [15:0] o_dq_oe,
  output [1:0] o_dqs_hi,
  output [1:0] o_dqs_lo,
  output [1:0] o_dqs_oe,
  output [1:0] o_dqs_n_oe,
  output ex_led_alarm,
  output ex_led_run,
  output odt,
  output ras,
  output reset,
  output we,
  output csi_rxc_hs_en_o,
  output csi_rxc_hs_term_en_o,
  output csi_rxd0_hs_en_o,
  output csi_rxd0_hs_term_en_o,
  output csi_rxd0_rst_o,
  output csi_rxd1_hs_en_o,
  output csi_rxd1_hs_term_en_o,
  output csi_rxd1_rst_o,
  output csi_rxd2_hs_en_o,
  output csi_rxd2_hs_term_en_o,
  output csi_rxd2_rst_o,
  output csi_rxd3_hs_en_o,
  output csi_rxd3_hs_term_en_o,
  output csi_rxd3_rst_o
);


endmodule

