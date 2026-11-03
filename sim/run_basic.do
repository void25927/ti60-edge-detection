if {[file isdirectory src/ui]} {set modern_ui_dir [file normalize src/ui]} else {set modern_ui_dir [file normalize ../src/ui]}
# 在ModelSim中切换到project/sim后执行：do run_basic.do
onerror {abort}
set sim_dir [pwd]
if {![file exists [file join $sim_dir edge_video_pipeline_tb.v]]} {
    error "Please change directory to project/sim before running this script."
}
set isp_dir [file normalize [file join $sim_dir ../src/isp]]
set control_dir [file normalize [file join $sim_dir ../src/control]]
set axi_dir [file normalize [file join $sim_dir ../src/axi]]
set ui_dir [file normalize [file join $sim_dir ../src/ui]]
set run_dir [file join $sim_dir modelsim_basic]
file mkdir $run_dir
cd $run_dir
transcript file regression.log
if {![file isdirectory work]} {vlib work}
vmap work work

foreach name {binary_morphology_3x3 edge_morphology_pipeline rgb888_to_gray gray_3x3_window median_3x3 gaussian_3x3 sobel_3x3 gradient_threshold canny_nms canny_double_threshold canny_hysteresis canny_edge_pipeline mipi_center_crop_32 gray_edge_display edge_video_pipeline edge_overlay} {
    vlog -work work [file join $isp_dir ${name}.v]
}
foreach name {debounce key_event_controller system_mode_controller threshold_controller} {
    vlog -work work [file join $control_dir ${name}.v]
}
vlog -work work [file join $axi_dir ddr_frame_manager.v]
vlog -work work [file join $ui_dir font_rom_8x16.v]
vlog +incdir+$modern_ui_dir [file join $modern_ui_dir hdmi_fps_counter.v] [file join $modern_ui_dir video_ui_metrics.v] [file join $modern_ui_dir vision_ui_renderer.v]
vlog -work work [file join $ui_dir video_ui_overlay.v]
foreach name {rgb888_to_gray gray_3x3_window gray_window_stream median_3x3 gaussian_3x3 sobel_3x3 gradient_threshold canny_nms canny_double_threshold canny_hysteresis debounce key_event_controller system_mode_controller threshold_controller ddr_frame_manager video_ui_overlay mipi_center_crop_32 gray_edge_display edge_video_pipeline edge_overlay} {
    vlog -work work [file join $sim_dir ${name}_tb.v]
}

foreach name {rgb888_to_gray gray_3x3_window gray_window_stream median_3x3 gaussian_3x3 sobel_3x3 gradient_threshold canny_nms canny_double_threshold canny_hysteresis debounce key_event_controller system_mode_controller threshold_controller ddr_frame_manager video_ui_overlay mipi_center_crop_32 gray_edge_display edge_video_pipeline edge_overlay} {
    vsim -voptargs=+acc -onfinish stop -wlf ${name}.wlf work.${name}_tb
    run -all
    set error_signal errors
    if {$name eq "rgb888_to_gray"} {set error_signal error_count}
    set count [examine -radix decimal /${name}_tb/$error_signal]
    if {$count != 0} {error "TEST FAILED: $name, $count error(s)"}
    quit -sim
}
puts "ALL TESTS PASSED: a_integrated_advanced_edge_video"
cd $sim_dir
