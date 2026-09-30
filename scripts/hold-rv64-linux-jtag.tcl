if {$argc != 1} { error "usage: hold-rv64-linux-jtag.tcl <debug-probes.ltx>" }
set probes [file normalize [lindex $argv 0]]
set m 0; set s 0; set t 0; set seq 0
proc n {kind} { global seq; incr seq; return "rv64_hold_${kind}_$seq" }
try {
  open_hw_manager; set m 1
  connect_hw_server -allow_non_jtag; set s 1
  open_hw_target; set t 1
  set dev [lindex [get_hw_devices xc7k480t*] 0]; current_hw_device $dev
  set_property PROBES.FILE $probes $dev; refresh_hw_device -update_hw_probes true $dev
  set axi [lindex [get_hw_axis -of_objects $dev] 0]
  if {$axi eq ""} { error "JTAG AXI core not found" }
  reset_hw_axi $axi
  set wr [n write]
  create_hw_axi_txn $wr $axi -address 7fffff00 -data {00000001} -len 1 -type WRITE
  run_hw_axi [get_hw_axi_txns $wr]
  set bresp [get_property STATUS.BRESP $axi]
  delete_hw_axi_txn [get_hw_axi_txns $wr]
  puts "RV64_HOLD_WRITE_BRESP=$bresp"
  set rd [n read]
  create_hw_axi_txn $rd $axi -address 7fffff00 -len 1 -type READ
  run_hw_axi [get_hw_axi_txns $rd]
  set rresp [get_property STATUS.RRESP $axi]
  set report [report_hw_axi_txn [get_hw_axi_txns $rd] -t x4 -w 4]
  delete_hw_axi_txn [get_hw_axi_txns $rd]
  set values [regexp -all -inline -nocase {\m[0-9a-f]{8}\M} $report]
  puts "RV64_HOLD_READ_RRESP=$rresp"
  if {[llength $values] == 0} { error "status read had no 32-bit value: $report" }
  set status [string tolower [lindex $values end]]
  puts "RV64_HOLD_STATUS=$status"
  if {$status ne "00000003"} { error "CPU was not held/calibrated: status=$status" }
  puts "RV64_HOLD_PASS"
} finally {
  if {$t} { close_hw_target }
  if {$s} { disconnect_hw_server }
  if {$m} { close_hw_manager }
}
