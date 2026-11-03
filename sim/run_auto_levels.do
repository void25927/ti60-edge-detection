# ModelSim切换至project/sim，执行do run_auto_levels.do。
onerror {quit -code 1 -f}
set root [pwd]
file mkdir modelsim_auto_levels
cd modelsim_auto_levels
transcript file regression.log
if {![file isdirectory work]} {vlib work}
vmap work work
vlog ../../src/isp/video_auto_levels.v
vlog ../../src/cmos_i2c/i2c_register_writer.v ../../src/cmos_i2c/sc2210_auto_exposure.v
vlog ../../src/isp/gray_edge_display.v
foreach name {video_auto_levels sc2210_auto_exposure auto_levels_display} {
    vlog ../${name}_tb.v
    vsim -voptargs=+acc -onfinish stop work.${name}_tb
    run -all
    if {[examine -radix decimal /${name}_tb/errors] != 0} {quit -code 1 -f}
    quit -sim
}
echo "ALL TESTS PASSED: auto_levels"
cd $root
