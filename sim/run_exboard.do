onerror {quit -code 1 -f}
set here D:/FPGA_Edge_Detection/project/sim
cd $here
file mkdir modelsim_exboard
cd modelsim_exboard
transcript file exboard.log
vlib work
vlog -work work ../../src/control/key_debounce.v ../../src/control/exboard_control.v ../../src/control/threshold_controller.v ../key_debounce_check_tb.v ../exboard_threshold_tb.v
vsim -voptargs=+acc -onfinish stop work.key_debounce_check_tb
run -all
set failures [examine -radix decimal /key_debounce_check_tb/errors]
if {$failures != 0} {quit -code 1 -f}
quit -sim
vsim -voptargs=+acc -onfinish stop work.exboard_threshold_tb
run -all
set failures [examine -radix decimal /exboard_threshold_tb/errors]
if {$failures != 0} {quit -code 1 -f}
echo "TEST PASSED: expansion board regression"
quit -sim
