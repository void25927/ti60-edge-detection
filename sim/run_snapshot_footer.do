onerror {quit -code 1 -f}
if {[file isdirectory src/ui]} {cd sim}
set sim_dir [pwd]
set root [file normalize ..]
set run_dir [file join $sim_dir modelsim_snapshot_footer]
file mkdir $run_dir
cd $run_dir
transcript file regression.log
if {![file isdirectory work]} {vlib work}
vmap work work
vlog $root/src/control/video_async_fifo.v $root/src/control/video_reset_sync.v $root/src/control/video_control_mailbox.v
vlog $root/src/ui/snapshot_capture.v $root/src/ui/snapshot_axi_writer.v $root/src/ui/snapshot_axi_reader.v $root/src/ui/snapshot_line_overlay.v $root/src/ui/snapshot_system.v $sim_dir/snapshot_system_tb.v
vsim -onfinish stop -voptargs=+acc -gFOOTER_HEIGHT=152 work.snapshot_system_tb
run -all
if {[examine -radix decimal /snapshot_system_tb/errors] != 0} {quit -code 1 -f}
puts "ALL TESTS PASSED: snapshot_footer_152"
quit -code 0 -f
