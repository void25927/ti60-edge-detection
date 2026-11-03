onerror {quit -code 1 -f}
if {[file isdirectory src/isp]} {cd sim}
if {![file isdirectory ../src/isp]} {error "Please run this script from the project or sim directory"}
file mkdir modelsim_history
cd modelsim_history
transcript file regression.log
if {![file isdirectory work]} {vlib work}
vmap work work
vlog ../../src/axi/video_history_manager.v ../video_history_tb.v
vsim -voptargs=+acc -onfinish stop work.video_history_tb
run -all
if {[examine -radix decimal /video_history_tb/errors] != 0} {quit -code 1 -f}
quit -code 0 -f
