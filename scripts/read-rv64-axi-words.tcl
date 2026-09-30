if {$argc < 2 || $argc > 3} { error "usage: read-rv64-axi-words.tcl <probes.ltx> <address> ?count?" }
set probes [file normalize [lindex $argv 0]]
set address [lindex $argv 1]
set count [expr {$argc == 3 ? [lindex $argv 2] : 1}]
scan $address %x base_address
set m 0; set s 0; set t 0; set n 0
try {
 open_hw_manager; set m 1; connect_hw_server -allow_non_jtag; set s 1; open_hw_target; set t 1
 set d [lindex [get_hw_devices xc7k480t*] 0]; current_hw_device $d
 set_property PROBES.FILE $probes $d; refresh_hw_device -update_hw_probes true $d
 set axi [lindex [get_hw_axis -of_objects $d] 0]
 for {set i 0} {$i < $count} {incr i} {
   incr n; set name "read_${n}"
   set current_address [expr {$base_address + 4*$i}]
   create_hw_axi_txn $name $axi -address [format %08x $current_address] -len 1 -type READ
   run_hw_axi [get_hw_axi_txns $name]
   set report [report_hw_axi_txn [get_hw_axi_txns $name] -t x4 -w 4]
   puts "ADDR=[format %08x $current_address] $report"
   delete_hw_axi_txn [get_hw_axi_txns $name]
 }
} finally { if {$t} {close_hw_target}; if {$s} {disconnect_hw_server}; if {$m} {close_hw_manager} }
