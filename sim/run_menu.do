onerror {quit -code 1 -f}
if {[file isdirectory src/isp]} {cd sim}
if {![file isdirectory ../src/isp]} {error "Please run this script from the project or sim directory"}
file mkdir modelsim_menu
cd modelsim_menu
transcript file regression.log
if {![file isdirectory work]} {vlib work}
vmap work work
vlog ../../src/control/feature_menu_controller.v ../../src/control/debounce.v ../../src/control/key_event_controller.v ../../src/control/threshold_controller.v ../feature_menu_tb.v ../onboard_keys_tb.v
vsim -voptargs=+acc -onfinish stop work.feature_menu_tb
run -all
if {[examine -radix decimal /feature_menu_tb/errors] != 0} {quit -code 1 -f}
quit -sim
vsim -voptargs=+acc -onfinish stop work.onboard_keys_tb
run -all
if {[examine -radix decimal /onboard_keys_tb/errors] != 0} {quit -code 1 -f}
quit -code 0 -f
