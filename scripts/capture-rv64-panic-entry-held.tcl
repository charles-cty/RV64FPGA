if {$argc != 2} { error "usage: capture-rv64-panic-entry-held.tcl <debug-probes.ltx> <capture.csv>" }
set probes [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
set manager_open 0; set server_connected 0; set target_open 0; set sequence 0
proc txn_name {} { global sequence; incr sequence; return "rv64_panic_entry_$sequence" }
proc write_control {axi value} {
  set n [txn_name]
  create_hw_axi_txn $n $axi -address 7fffff00 -data [list $value] -len 1 -type WRITE
  run_hw_axi [get_hw_axi_txns $n]
  delete_hw_axi_txn [get_hw_axi_txns $n]
}
try {
  open_hw_manager; set manager_open 1
  connect_hw_server -allow_non_jtag; set server_connected 1
  open_hw_target; set target_open 1
  set dev [lindex [get_hw_devices xc7k480t*] 0]; current_hw_device $dev
  set_property PROBES.FILE $probes $dev
  refresh_hw_device -update_hw_probes true $dev
  set axi [lindex [get_hw_axis -of_objects $dev] 0]
  set ila [lindex [get_hw_ilas -of_objects $dev] 0]
  set trace [lindex [get_hw_probes -of_objects $ila -filter {NAME == "debug_commit_trace"}] 0]
  set status [lindex [get_hw_probes -of_objects $ila -filter {NAME == "debug_status"}] 0]
  if {$axi eq "" || $ila eq "" || $trace eq "" || $status eq ""} { error "missing required hardware probes" }
  reset_hw_axi $axi
  write_control $axi {00000001}
  reset_hw_ila $ila
  set_property CONTROL.DATA_DEPTH 4096 $ila
  set_property CONTROL.TRIGGER_POSITION 3072 $ila
  set_property CONTROL.TRIGGER_CONDITION AND $ila
  # The trace probe is the authoritative trigger; status is retained only as
  # a visible diagnostic because some BASIC ILA builds expose one comparator.
  set_property TRIGGER_COMPARE_VALUE {eq6'bXXXXXX} $status
  set pc [format %064llb 0xffffffff80c99820]
  set_property TRIGGER_COMPARE_VALUE [format "eq226'b%s%s" [string repeat X 162] $pc] $trace
  run_hw_ila $ila
  write_control $axi {00000000}
  puts "RV64_PANIC_ENTRY_RELEASED"
  flush stdout
  wait_on_hw_ila -timeout 30 $ila
  set data [upload_hw_ila_data $ila]
  if {[llength $data] == 0} { error "panic-entry ILA returned no data" }
  file mkdir [file dirname $out]
  write_hw_ila_data -force -csv_file $out $data
  puts "RV64_PANIC_ENTRY_HELD_CAPTURE_PASS file=$out"
} finally {
  if {$target_open} { close_hw_target }
  if {$server_connected} { disconnect_hw_server }
  if {$manager_open} { close_hw_manager }
}
