if {$argc != 4} {
  error "usage: build-ddr3-clock-frequency-probe.tcl <source-root> <project-dir> <bitstream> <mcs>"
}

set source_root [file normalize [lindex $argv 0]]
set project_dir [file normalize [lindex $argv 1]]
set bitstream [file normalize [lindex $argv 2]]
set mcs [file normalize [lindex $argv 3]]
set report_dir [file dirname $bitstream]

file mkdir $report_dir
create_project rv64_ddr3_clock_frequency_probe $project_dir -part xc7k480tffg1156-2 -force
add_files -norecurse [file join $source_root rtl rv64_ddr3_clock_frequency_probe_top.sv]
add_files -fileset constrs_1 -norecurse [file join $source_root constraints rv64_ddr3_clock_frequency_probe.xdc]
set_property top rv64_ddr3_clock_frequency_probe_top [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
  error "clock frequency probe synthesis failed"
}

open_run synth_1
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -file [file join $report_dir timing_summary_routed.rpt]
report_drc -file [file join $report_dir drc_routed.rpt]
write_checkpoint -force [file join $report_dir rv64_ddr3_clock_frequency_probe_routed.dcp]
write_bitstream -force $bitstream
write_cfgmem -format mcs -interface BPIx16 -size 64 -loadbit [list up 0x0 $bitstream] -force $mcs
puts "RV64_DDR3_CLOCK_FREQUENCY_PROBE_PASS bit=$bitstream mcs=$mcs"
