onerror {quit -code 1 -f}
if {[file isdirectory ../src/ui]} {cd ..}
set root [pwd]
set run_dir [file join $root sim/modelsim_modern_ui]
file mkdir $run_dir
transcript file [file join $run_dir regression.log]
if {![file isdirectory [file join $run_dir work]]} {vlib [file join $run_dir work]}
vmap work [file join $run_dir work]
vlog +incdir+src/ui src/ui/vision_ui_renderer.v src/ui/font_rom_8x16.v src/ui/hdmi_fps_counter.v src/ui/video_ui_metrics.v src/ui/video_ui_overlay.v src/control/feature_menu_controller.v sim/modern_menu_tb.v sim/modern_ui_tb.v sim/modern_wrapper_tb.v
foreach name {modern_menu modern_ui modern_wrapper} {
    vsim -onfinish stop -voptargs=+acc work.${name}_tb
    run -all
    if {[examine -radix decimal /${name}_tb/errors] != 0} {quit -code 1 -f}
    quit -sim
}
puts "ALL TESTS PASSED: modern_vision_ui"
quit -code 0 -f
