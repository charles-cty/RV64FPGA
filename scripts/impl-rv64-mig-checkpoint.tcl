if {$argc != 2} {
  error "usage: impl-rv64-mig-checkpoint.tcl <synth-checkpoint> <report-directory>"
}

set synth_checkpoint [file normalize [lindex $argv 0]]
set report_directory [file normalize [lindex $argv 1]]

if {![file exists $synth_checkpoint]} {
  error "synthesis checkpoint does not exist: $synth_checkpoint"
}

file mkdir $report_directory
open_checkpoint $synth_checkpoint

opt_design
place_design
phys_opt_design -directive Explore
route_design -directive Explore

report_utilization -hierarchical -file [file join $report_directory utilization_hierarchical_routed.rpt]
report_timing_summary -max_paths 10 -file [file join $report_directory timing_summary_routed.rpt]
report_clock_interaction -file [file join $report_directory clock_interaction_routed.rpt]
check_timing -verbose -file [file join $report_directory check_timing_routed.rpt]
report_drc -file [file join $report_directory drc_routed.rpt]
write_checkpoint -force [file join $report_directory rv64_mig_soc_routed.dcp]

puts "RV64_MIG_IMPL_PASS checkpoint=$synth_checkpoint reports=$report_directory"
close_design
