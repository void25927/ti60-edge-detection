onerror {quit -code 1 -f}
set sim [pwd]
set project [file normalize ..]
file mkdir modelsim_inspection_user_control
cd modelsim_inspection_user_control
if {![file isdirectory work]} {vlib work}
vmap work work
vlog $project/src/inspection/inspection_user_control.v $sim/inspection_user_control_tb.v
vsim -voptargs=+acc -onfinish stop work.inspection_user_control_tb
run -all
if {[examine -radix decimal /inspection_user_control_tb/errors] != 0} {quit -code 1 -f}
quit -code 0 -f
