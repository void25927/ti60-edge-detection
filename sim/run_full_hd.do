onerror {quit -code 1 -f}
set root [pwd]
file mkdir modelsim_full_hd
cd modelsim_full_hd
transcript file regression.log
if {![file isdirectory work]} {vlib work}
vmap work work
foreach f {rgb888_to_gray gray_3x3_window median_3x3 gaussian_3x3 sobel_3x3 gradient_threshold canny_nms canny_double_threshold canny_hysteresis canny_edge_pipeline edge_video_pipeline gray_edge_display video_auto_levels edge_overlay mipi_center_crop_32 VIP_RAW8_RGB888 VIP_Matrix_Generate_3X3_8Bit Line_Shift_RAM_8Bit} {
    vlog ../../src/isp/${f}.v
}
foreach f {bayer_coordinate overlay_contrast mipi_full_frame full_hd_display full_hd_pipeline} {
    vlog ../${f}_tb.v
    vsim -voptargs=+acc -onfinish stop work.${f}_tb
    run -all
    if {[examine -radix decimal /${f}_tb/errors] != 0} {quit -code 1 -f}
    quit -sim
}
echo "ALL TESTS PASSED: full_hd"
cd $root
