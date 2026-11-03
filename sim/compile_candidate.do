onerror {quit -code 1 -f}
if {[file isdirectory src/isp]} {cd sim}
set root [file normalize ..]
file mkdir $root/sim/modelsim_candidate
cd $root/sim/modelsim_candidate
transcript file compile.log
if {![file isdirectory work]} {vlib work}
set f [open $root/Ti60_Edge_Detection.xml r]
set xml [read $f]
close $f
foreach {tag path} [regexp -all -inline {<efx:design_file name="([^"]+)"} $xml] {
    vlog +incdir+$root/src $root/$path
}
puts "SYNTAX PASSED: candidate source list (not elaboration)"
quit -code 0 -f
