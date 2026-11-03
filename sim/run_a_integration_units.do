if {[file isdirectory src/ui]} {set modern_ui_dir [file normalize src/ui]} else {set modern_ui_dir [file normalize ../src/ui]}
# A角色新增控制、DDR帧管理和UI模块自检。
onerror {abort}
set sim_dir [pwd]
set project_dir [file normalize [file join $sim_dir ..]]
set run_dir [file join $sim_dir modelsim_a_integration]
file mkdir $run_dir
cd $run_dir
transcript file regression.log
if {![file isdirectory work]} {vlib work}
vmap work work

vlog -work work [file join $project_dir src/control/system_mode_controller.v]
vlog -work work [file join $project_dir src/axi/ddr_frame_manager.v]
vlog -work work [file join $project_dir src/ui/font_rom_8x16.v]
vlog +incdir+$modern_ui_dir [file join $modern_ui_dir hdmi_fps_counter.v] [file join $modern_ui_dir video_ui_metrics.v] [file join $modern_ui_dir vision_ui_renderer.v]
vlog -work work [file join $project_dir src/ui/video_ui_overlay.v]
vlog -work work [file join $project_dir src/isp/edge_overlay.v]

foreach name {system_mode_controller ddr_frame_manager video_ui_overlay edge_overlay} {
    vlog -work work [file join $sim_dir ${name}_tb.v]
    vsim -voptargs=+acc -onfinish stop -wlf ${name}.wlf work.${name}_tb
    run -all
    set count [examine -radix decimal /${name}_tb/errors]
    if {$count != 0} {error "TEST FAILED: $name, $count error(s)"}
    quit -sim
}
puts "ALL TESTS PASSED: a_integration_units"
cd $sim_dir
