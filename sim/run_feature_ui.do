if {[file isdirectory src/ui]} {set modern_ui_dir [file normalize src/ui]} else {set modern_ui_dir [file normalize ../src/ui]}
onerror {quit -code 1 -f}
if {[file isdirectory src/isp]} {cd sim}
if {![file isdirectory ../src/isp]} {error "Please run this script from the project or sim directory"}
file mkdir modelsim_feature_ui
cd modelsim_feature_ui
transcript file regression.log
if {![file isdirectory work]} {vlib work}
vmap work work
vlog +incdir+$modern_ui_dir [file join $modern_ui_dir hdmi_fps_counter.v] [file join $modern_ui_dir video_ui_metrics.v] [file join $modern_ui_dir vision_ui_renderer.v]
vlog ../../src/ui/font_rom_8x16.v ../../src/ui/video_ui_overlay.v ../feature_ui_tb.v
vsim -voptargs=+acc -onfinish stop work.feature_ui_tb
run -all
if {[examine -radix decimal /feature_ui_tb/errors] != 0} {quit -code 1 -f}
quit -code 0 -f
