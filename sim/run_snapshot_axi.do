onerror {quit -code 1 -f}
if {[file isdirectory src/isp]} {cd sim}
if {![file isdirectory ../src/isp]} {error "Please run this script from the project or sim directory"}
file mkdir modelsim_snapshot_axi
cd modelsim_snapshot_axi
transcript file regression.log
if {![file isdirectory work]} {vlib work}
vlog ../../src/ui/snapshot_axi_writer.v ../snapshot_axi_writer_tb.v
vsim -voptargs=+acc -onfinish stop work.snapshot_axi_writer_tb
run -all
if {[examine -radix decimal /snapshot_axi_writer_tb/errors] != 0} {quit -code 1 -f}
quit -code 0 -f
