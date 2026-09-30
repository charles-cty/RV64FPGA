if {$argc != 2} { error "usage: rearm-rv64-panic-history-jtag.tcl <debug-probes.ltx> <capture.csv>" }
set probes [file normalize [lindex $argv 0]]; set out [file normalize [lindex $argv 1]]
set manager_open 0; set server_connected 0; set target_open 0; set seq 0
proc txn_name {} { global seq; incr seq; return "rv64_panic_rearm_$seq" }
proc ctl {axi value} { set n [txn_name]; create_hw_axi_txn $n $axi -address 7fffff00 -data [list $value] -len 1 -type WRITE; run_hw_axi [get_hw_axi_txns $n]; delete_hw_axi_txn [get_hw_axi_txns $n] }
try {
  open_hw_manager; set manager_open 1; connect_hw_server -allow_non_jtag; set server_connected 1; open_hw_target; set target_open 1
  set dev [lindex [get_hw_devices xc7k480t*] 0]; current_hw_device $dev; set_property PROBES.FILE $probes $dev; refresh_hw_device -update_hw_probes true $dev
  set axi [lindex [get_hw_axis -of_objects $dev] 0]; set ila [lindex [get_hw_ilas -of_objects $dev] 0]
  set commit [lindex [get_hw_probes -of_objects $ila -filter {NAME == "debug_commit_trace"}] 0]
  if {$axi eq "" || $ila eq "" || $commit eq ""} { error "missing JTAG AXI, ILA, or commit probe" }
  reset_hw_axi $axi; ctl $axi 00000001; after 100; reset_hw_ila $ila
  set_property CONTROL.DATA_DEPTH 4096 $ila; set_property CONTROL.TRIGGER_POSITION 2048 $ila; set_property CONTROL.TRIGGER_CONDITION OR $ila
  set pc [format %064llb 0xffffffff80c98480]
  set_property TRIGGER_COMPARE_VALUE [format "eq226'b%s%s" [string repeat X 162] $pc] $commit
  run_hw_ila $ila; ctl $axi 00000000; puts "RV64_PANIC_HISTORY_RELEASED"; flush stdout
  wait_on_hw_ila -timeout 2 $ila; set data [upload_hw_ila_data $ila]
  if {[llength $data] == 0} { error "no panic history capture" }
  file mkdir [file dirname $out]; write_hw_ila_data -force -csv_file $out $data; puts "RV64_PANIC_HISTORY_CAPTURE_PASS file=$out"
} finally { if {$target_open} {close_hw_target}; if {$server_connected} {disconnect_hw_server}; if {$manager_open} {close_hw_manager} }
