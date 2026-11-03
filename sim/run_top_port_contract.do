onerror {quit -code 1 -f}
set project [file normalize ..]
file mkdir modelsim_top_port_contract
cd modelsim_top_port_contract
if {![file isdirectory work]} {vlib work}
vmap work [file normalize work]
foreach f [glob C:/Efinity/2023.2/sim_models/verilog/*.v] {vlog $f}
vlog ../ddr_port_declaration_only.v $project/ip/W0_FIFO_32/W0_FIFO_32.v $project/ip/R0_FIFO_8/R0_FIFO_8.v
set f [open $project/Ti60_Edge_Detection.xml r]
set xml [read $f]
close $f
foreach {tag path} [regexp -all -inline {<efx:design_file name="([^"]+)"} $xml] {vlog +incdir+$project/src +incdir+$project/src/ui $project/$path}
set port_ini [file normalize modelsim.ini]
cd $project
vsim -modelsimini $port_ini -voptargs=+acc -onfinish stop work.Ti60_top
puts "TEST PASSED: top port contract only. DDR declaration-only fixture, no DDR/PHY behavioral coverage."
quit -code 0 -f
