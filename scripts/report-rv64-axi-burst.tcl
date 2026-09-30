if {$argc != 3} { error "usage: report-rv64-axi-burst.tcl <probes.ltx> <address> <words>" }
set probes [file normalize [lindex $argv 0]]
scan [lindex $argv 1] %x address
set words [lindex $argv 2]
set m 0; set s 0; set t 0
try {
  open_hw_manager; set m 1; connect_hw_server -allow_non_jtag; set s 1; open_hw_target; set t 1
  set d [lindex [get_hw_devices xc7k480t*] 0]; current_hw_device $d
  set_property PROBES.FILE $probes $d; refresh_hw_device -update_hw_probes true $d
  set axi [lindex [get_hw_axis -of_objects $d] 0]
  create_hw_axi_txn burst_read $axi -address [format %08x $address] -len $words -type READ
  run_hw_axi [get_hw_axi_txns burst_read]
  puts [report_hw_axi_txn [get_hw_axi_txns burst_read] -t x4 -w 4]
} finally { if {$t} {close_hw_target}; if {$s} {disconnect_hw_server}; if {$m} {close_hw_manager} }
