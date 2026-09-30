if {$argc != 2} {
  error "usage: capture-rv64-uart-jtag.tcl <debug-probes.ltx> <capture.csv>"
}

set debug_probes [file normalize [lindex $argv 0]]
set capture_file [file normalize [lindex $argv 1]]
if {![file exists $debug_probes] || ![file isfile $debug_probes]} {
  error "debug probes file does not exist: $debug_probes"
}

set manager_open 0
set server_connected 0
set target_open 0
try {
  open_hw_manager
  set manager_open 1
  connect_hw_server -allow_non_jtag
  set server_connected 1
  open_hw_target
  set target_open 1
  set devices [get_hw_devices xc7k480t*]
  if {[llength $devices] != 1} {
    error "expected exactly one xc7k480t JTAG device, found: $devices"
  }
  set device [lindex $devices 0]
  current_hw_device $device
  set_property PROBES.FILE $debug_probes $device
  refresh_hw_device -update_hw_probes true $device
  set ilas [get_hw_ilas -of_objects $device]
  if {[llength $ilas] != 1} {
    error "expected exactly one ILA core, found: $ilas"
  }
  set ila [lindex $ilas 0]
  set uart_probe [get_hw_probes -of_objects $ila -filter {NAME == "uart_tx"}]
  if {[llength $uart_probe] != 1} {
    error "expected exactly one uart_tx probe, found: $uart_probe"
  }
  reset_hw_ila $ila
  set_property CONTROL.DATA_DEPTH 4096 $ila
  set_property CONTROL.TRIGGER_POSITION 0 $ila
  set_property CONTROL.TRIGGER_CONDITION AND $ila
  set_property TRIGGER_COMPARE_VALUE {eq1'b0} [lindex $uart_probe 0]
  run_hw_ila $ila
  puts "RV64_UART_ILA_ARMED"
  flush stdout
  wait_on_hw_ila -timeout 10 $ila
  set capture [upload_hw_ila_data $ila]
  if {[llength $capture] == 0} {
    error "UART ILA did not produce a capture"
  }
  file mkdir [file dirname $capture_file]
  file delete -force $capture_file
  write_hw_ila_data -force -csv_file $capture_file $capture
  puts "RV64_UART_CAPTURE_PASS file=$capture_file"
} finally {
  if {$target_open} { close_hw_target }
  if {$server_connected} { disconnect_hw_server }
  if {$manager_open} { close_hw_manager }
}
