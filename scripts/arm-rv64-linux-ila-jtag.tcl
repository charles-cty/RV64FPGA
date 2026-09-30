if {$argc != 3} {
  error "usage: arm-rv64-linux-ila-jtag.tcl <debug-probes.ltx> <capture.csv> <panic-pc-hex>"
}
set probes [file normalize [lindex $argv 0]]
set output_file [file normalize [lindex $argv 1]]
set panic_pc [string tolower [lindex $argv 2]]
set manager_open 0
set server_connected 0
set target_open 0
try {
  open_hw_manager; set manager_open 1
  connect_hw_server -allow_non_jtag; set server_connected 1
  open_hw_target; set target_open 1
  set device [lindex [get_hw_devices xc7k480t*] 0]
  current_hw_device $device
  set_property PROBES.FILE $probes $device
  refresh_hw_device -update_hw_probes true $device
  set ilas [get_hw_ilas -of_objects $device]
  if {[llength $ilas] != 1} { error "expected one ILA core, found: $ilas" }
  set ila [lindex $ilas 0]
  set traces [get_hw_probes -of_objects $ila -filter {NAME == "debug_commit_trace"}]
  if {[llength $traces] != 1} { error "expected one debug_commit_trace probe, found: $traces" }
  set trace [lindex $traces 0]
  reset_hw_ila $ila
  # The ILA trigger is an AND across all trigger probes.  Clear every
  # comparator to a wildcard first; otherwise an unconfigured status or
  # memory probe can prevent the PC comparator from ever firing.
  foreach probe [get_hw_probes -of_objects $ila] {
    set width [get_property WIDTH $probe]
    if {$width eq "" || $width < 1} { set width 1 }
    set_property TRIGGER_COMPARE_VALUE [format "eq%d'b%s" $width [string repeat X $width]] $probe
  }
  set_property CONTROL.DATA_DEPTH 4096 $ila
  set_property CONTROL.TRIGGER_POSITION 3072 $ila
  set_property CONTROL.TRIGGER_CONDITION AND $ila
  set compare [format "eq226'b%s%s" [string repeat X 162] [format %064llb 0x$panic_pc]]
  set_property TRIGGER_COMPARE_VALUE $compare $trace
  run_hw_ila $ila
  puts "RV64_ILA_ARMED pc=$panic_pc"
  flush stdout
  wait_on_hw_ila -timeout 180 $ila
  set data [upload_hw_ila_data $ila]
  if {[llength $data] == 0} { error "ILA capture returned no data" }
  file mkdir [file dirname $output_file]
  write_hw_ila_data -force -csv_file $output_file $data
  puts "RV64_ILA_CAPTURE_PASS file=$output_file"
} finally {
  if {$target_open} { close_hw_target }
  if {$server_connected} { disconnect_hw_server }
  if {$manager_open} { close_hw_manager }
}
