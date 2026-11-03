onerror {quit -code 1 -f}
if {[file isdirectory src/isp]} {cd sim}
if {![file isdirectory ../src/isp]} {error "Please run this script from the project or sim directory"}
file mkdir modelsim_snapshot_arbiter
cd modelsim_snapshot_arbiter
transcript file regression.log
if {![file isdirectory work]} {vlib work}
vlog ../../src/axi/video_snapshot_arbiter.v ../video_snapshot_arbiter_tb.v
vsim -voptargs=+acc -onfinish stop work.video_snapshot_arbiter_tb
run -all
if {[examine -radix decimal /video_snapshot_arbiter_tb/errors] != 0} {quit -code 1 -f}
quit -code 0 -f
