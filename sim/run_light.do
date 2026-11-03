onerror {quit -code 1 -f}
if {[file isdirectory src/isp]} {cd sim}
if {![file isdirectory ../src/isp]} {error "Please run this script from the project or sim directory"}
file mkdir modelsim_light
cd modelsim_light
transcript file regression.log
if {![file isdirectory work]} {vlib work}
vmap work work
foreach f [glob ../../src/isp/*.v] {vlog -work work $f}
vlog -work work ../light_repair_tb.v ../median_switch_tb.v
foreach test {light_repair median_switch} {
 vsim -voptargs=+acc -onfinish stop work.${test}_tb
 run -all
 if {[examine -radix decimal /${test}_tb/errors] != 0} {quit -code 1 -f}
 quit -sim
}
quit -code 0 -f
