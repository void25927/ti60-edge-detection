onerror {quit -code 1 -f}
if {[file isdirectory ../src/ui]} {cd ..}
file mkdir sim/modelsim_fps
vlib sim/modelsim_fps/work
vmap work sim/modelsim_fps/work
vlog src/ui/hdmi_fps_counter.v sim/hdmi_fps_counter_tb.v
vsim -onfinish stop -voptargs=+acc work.hdmi_fps_counter_tb
run -all
if {[examine -radix decimal /hdmi_fps_counter_tb/errors] != 0} {quit -code 1 -f}
quit -code 0 -f
