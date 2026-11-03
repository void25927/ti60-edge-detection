onerror {quit -code 1 -f}
if {[file isdirectory src/isp]} {cd sim}
if {![file isdirectory ../src/isp]} {error "Please run this script from the project or sim directory"}
file mkdir modelsim_video_ddr_full_hd
cd modelsim_video_ddr_full_hd
transcript file regression.log
if {![file isdirectory work]} {vlib work}
vlog ../../ip/R0_FIFO_8/R0_FIFO_8.v ../../ip/W0_FIFO_32/W0_FIFO_32.v
vlog ../../src/control/video_reset_sync.v ../../src/control/video_control_mailbox.v
vlog ../../src/axi/video_history_manager.v ../../src/axi/video_snapshot_arbiter.v ../../src/axi/axi4_ctrl.v
vlog +define+FULL_HD ../video_ddr_path_tb.v
vsim -voptargs=+acc -onfinish stop work.video_ddr_path_tb
run -all
if {[examine -radix decimal /video_ddr_path_tb/errors] != 0} {quit -code 1 -f}
quit -code 0 -f
