if {$argc < 1 || $argc > 2} {
  error "usage: program-jtag-bitstream.tcl <bitstream> ?debug-probes.ltx?"
}

set bitstream [file normalize [lindex $argv 0]]
if {![file exists $bitstream]} {
  error "bitstream does not exist: $bitstream"
}
set debug_probes ""
if {$argc == 2} {
  set debug_probes [file normalize [lindex $argv 1]]
  if {![file exists $debug_probes]} {
    error "debug probes file does not exist: $debug_probes"
  }
}

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set devices [get_hw_devices xc7k480t*]
if {[llength $devices] != 1} {
  error "expected exactly one xc7k480t JTAG device, found: $devices"
}
set dev [lindex $devices 0]
current_hw_device $dev
set_property PROGRAM.FILE $bitstream $dev
if {$debug_probes ne ""} {
  set_property PROBES.FILE $debug_probes $dev
}
program_hw_devices $dev
refresh_hw_device -update_hw_probes true $dev
puts "JTAG_PROGRAM_DONE device=$dev bitstream=$bitstream"
if {$debug_probes ne ""} {
  puts "JTAG_PROBES_LOADED file=$debug_probes"
}
puts "JTAG_DEBUG_CORE_COUNT [llength [get_hw_cores -quiet]]"
close_hw_target
disconnect_hw_server
close_hw_manager
