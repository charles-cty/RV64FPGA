if {$argc != 1} { error "usage: release-only-rv64-linux-jtag.tcl <debug-probes.ltx>" }
set probes [file normalize [lindex $argv 0]]
set manager_open 0
set server_connected 0
set target_open 0
set sequence 0
proc transaction_name {} { global sequence; incr sequence; return "rv64_release_only_$sequence" }
try {
  open_hw_manager; set manager_open 1
  connect_hw_server -allow_non_jtag; set server_connected 1
  open_hw_target; set target_open 1
  set device [lindex [get_hw_devices xc7k480t*] 0]
  current_hw_device $device
  set_property PROBES.FILE $probes $device
  refresh_hw_device -update_hw_probes true $device
  set axis [get_hw_axis -of_objects $device]
  if {[llength $axis] != 1} { error "expected one JTAG AXI core, found: $axis" }
  set axi [lindex $axis 0]
  reset_hw_axi $axi
  set transaction [transaction_name]
  create_hw_axi_txn $transaction $axi -address 7fffff00 -data {00000000} -len 1 -type WRITE
  puts "RV64_RELEASE_WRITE_START"
  flush stdout
  run_hw_axi [get_hw_axi_txns $transaction]
  puts "RV64_RELEASE_WRITE_DONE"
  delete_hw_axi_txn [get_hw_axi_txns $transaction]
} finally {
  if {$target_open} { close_hw_target }
  if {$server_connected} { disconnect_hw_server }
  if {$manager_open} { close_hw_manager }
}
