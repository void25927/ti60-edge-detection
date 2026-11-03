onerror {quit -code 1 -f}
if {[file isdirectory src/isp]} {cd sim}
if {![file isdirectory ../src/isp]} {error "Please run this script from the project or sim directory"}
file mkdir modelsim_snapshot_line
cd modelsim_snapshot_line
transcript file regression.log
if {![file isdirectory work]} {vlib work}
vlog ../../src/ui/snapshot_line_overlay.v ../snapshot_line_tb.v
vsim -voptargs=+acc -onfinish stop work.snapshot_line_tb
run -all
if {[examine -radix decimal /snapshot_line_tb/errors] != 0} {quit -code 1 -f}
quit -code 0 -f
