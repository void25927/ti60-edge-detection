transcript on
if {[file exists work]} {vdel -lib work -all}
vlib work
vmap work work

set root_dir [file normalize [file join [pwd] ..]]
vlog -work work [file join $root_dir src isp mipi_center_crop_32.v]
vlog -work work [file join $root_dir sim mipi_center_crop_32_tb.v]
vsim work.mipi_center_crop_32_tb
onfinish stop
run -all
quit -sim

vlog -work work [file join $root_dir src isp gray_edge_display.v]
vlog -work work [file join $root_dir sim gray_edge_display_tb.v]
vsim work.gray_edge_display_tb
onfinish stop
run -all
quit -sim
