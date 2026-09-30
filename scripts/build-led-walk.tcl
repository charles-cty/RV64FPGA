if {$argc != 2} {
  error "usage: build-led-walk.tcl <source-root> <output-directory>"
}

set source_root [file normalize [lindex $argv 0]]
set output_directory [file normalize [lindex $argv 1]]
set part_name xc7k480tffg1156-2
set top_name rv64_led_walk_top
set rtl_file [file join $source_root rtl rv64_led_walk_top.sv]
set xdc_file [file join $source_root constraints rv64_led_walk_top.xdc]

foreach required_file [list $rtl_file $xdc_file] {
  if {![file exists $required_file]} {
    error "required file does not exist: $required_file"
  }
}

file mkdir $output_directory
read_verilog -sv $rtl_file
read_xdc $xdc_file
synth_design -top $top_name -part $part_name
opt_design
place_design
route_design
report_timing_summary -max_paths 10 -file [file join $output_directory timing_summary_routed.rpt]
check_timing -verbose -file [file join $output_directory check_timing_routed.rpt]
report_drc -file [file join $output_directory drc_routed.rpt]
write_checkpoint -force [file join $output_directory rv64_led_walk_top_routed.dcp]
write_bitstream -force [file join $output_directory rv64_led_walk_top.bit]
puts "LED_WALK_BUILD_PASS output=$output_directory"
