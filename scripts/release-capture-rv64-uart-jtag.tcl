if {$argc != 2} {
  error "usage: release-capture-rv64-uart-jtag.tcl <debug-probes.ltx> <capture.csv>"
}
set probes [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
set manager_open 0
set server_connected 0
set target_open 0
set sequence 0
proc txn_name {} { global sequence; incr sequence; return "rv64_uart_release_$sequence" }
try {
  open_hw_manager; set manager_open 1
  connect_hw_server -allow_non_jtag; set server_connected 1
  open_hw_target; set target_open 1
  set dev [lindex [get_hw_devices xc7k480t*] 0]
  current_hw_device $dev
  set_property PROBES.FILE $probes $dev
  refresh_hw_device -update_hw_probes true $dev
  set axi [lindex [get_hw_axis -of_objects $dev] 0]
  set ila [lindex [get_hw_ilas -of_objects $dev] 0]
  set uart [lindex [get_hw_probes -of_objects $ila -filter {NAME == "uart_tx"}] 0]
  if {$axi eq "" || $ila eq "" || $uart eq ""} { error "missing JTAG AXI, ILA, or uart_tx probe" }
  reset_hw_axi $axi
  reset_hw_ila $ila
  set_property CONTROL.DATA_DEPTH 4096 $ila
  set_property CONTROL.TRIGGER_POSITION 0 $ila
  set_property CONTROL.TRIGGER_CONDITION AND $ila
  set_property TRIGGER_COMPARE_VALUE {eq1'b0} $uart
  run_hw_ila $ila
  set tx [txn_name]
  create_hw_axi_txn $tx $axi -address 7fffff00 -data {00000000} -len 1 -type WRITE
  run_hw_axi [get_hw_axi_txns $tx]
  delete_hw_axi_txn [get_hw_axi_txns $tx]
  puts "RV64_UART_RELEASED"
  flush stdout
  wait_on_hw_ila -timeout 30 $ila
  set data [upload_hw_ila_data $ila]
  if {[llength $data] == 0} { error "UART ILA returned no data" }
  file mkdir [file dirname $out]
  write_hw_ila_data -force -csv_file $out $data
  puts "RV64_UART_RELEASE_CAPTURE_PASS file=$out"
} finally {
  if {$target_open} { close_hw_target }
  if {$server_connected} { disconnect_hw_server }
  if {$manager_open} { close_hw_manager }
}
