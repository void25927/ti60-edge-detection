onerror {abort}
set sim_dir [pwd]
set src_dir [file normalize [file join $sim_dir ../src/isp]]
set run_dir [file join $sim_dir modelsim_full_chain]
file mkdir $run_dir
cd $run_dir
if {![file isdirectory work]} {vlib work}
vmap work work
foreach name {Line_Shift_RAM_8Bit VIP_Matrix_Generate_3X3_8Bit VIP_RAW8_RGB888 rgb888_to_gray gray_3x3_window median_3x3 gaussian_3x3 sobel_3x3 gradient_threshold canny_nms canny_double_threshold canny_hysteresis canny_edge_pipeline edge_video_pipeline edge_overlay gray_edge_display} {
    vlog -work work [file join $src_dir ${name}.v]
}
vlog -work work [file join $sim_dir gray_edge_full_chain_tb.v]
vsim -voptargs=+acc -onfinish stop work.gray_edge_full_chain_tb
run -all
quit -sim
cd $sim_dir
