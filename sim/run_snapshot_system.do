onerror {quit -code 1 -f}
if {[file isdirectory src/isp]} {cd sim}
if {![file isdirectory ../src/isp]} {error "Please run this script from the project or sim directory"}
file mkdir modelsim_snapshot_system
cd modelsim_snapshot_system
transcript file regression.log
if {![file isdirectory work]} {vlib work}
vlog ../../src/control/video_async_fifo.v ../../src/control/video_reset_sync.v ../../src/control/video_control_mailbox.v
vlog ../../src/ui/snapshot*.v ../snapshot_system_tb.v
vsim -voptargs=+acc -onfinish stop work.snapshot_system_tb
run -all
if {[examine -radix decimal /snapshot_system_tb/errors] != 0} {quit -code 1 -f}
quit -code 0 -f
