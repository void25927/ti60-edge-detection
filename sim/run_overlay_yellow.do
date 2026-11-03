onerror {quit -code 1 -f}
set root [pwd]
file mkdir modelsim_overlay_yellow
cd modelsim_overlay_yellow
transcript file regression.log
if {![file isdirectory work]} {vlib work}
vmap work work
vlog ../../src/isp/edge_overlay.v ../overlay_yellow_tb.v
vsim -voptargs=+acc -onfinish stop work.overlay_yellow_tb
run -all
if {[examine -radix decimal /overlay_yellow_tb/errors] != 0} {quit -code 1 -f}
quit -sim
cd $root
