if {$argc != 3} {
  error "usage: capture-rv64-panic-entry-jtag.tcl <debug-probes.ltx> <capture.csv> <panic-pc-hex>"
}
set probes [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
set panic_pc [string tolower [lindex $argv 2]]
set manager_open 0
set server_connected 0
set target_open 0
set sequence 0
proc txn_name {prefix} { global sequence; incr sequence; return "panic_${prefix}_${sequence}" }
proc axi_write {axi address data} {
  set n [txn_name write]
  create_hw_axi_txn $n $axi -address [format %08x $address] -data $data -len 1 -type WRITE
  run_hw_axi [get_hw_axi_txns $n]
  set response [get_property STATUS.BRESP $axi]
  delete_hw_axi_txn [get_hw_axi_txns $n]
  if {$response ne "OKAY"} {
    error "CPU control write failed: $response; reconfigure SRAM and load the payload in hold mode before capturing"
  }
}
try {
  open_hw_manager; set manager_open 1
  connect_hw_server -allow_non_jtag; set server_connected 1
  open_hw_target; set target_open 1
  set dev [lindex [get_hw_devices xc7k480t*] 0]; current_hw_device $dev
  set_property PROBES.FILE $probes $dev; refresh_hw_device -update_hw_probes true $dev
  set axi [lindex [get_hw_axis -of_objects $dev] 0]
  reset_hw_axi $axi
  set ila [lindex [get_hw_ilas -of_objects $dev] 0]
  reset_hw_ila $ila
  set trace [lindex [get_hw_probes -of_objects $ila -filter {NAME == "debug_commit_trace"}] 0]
  foreach probe [get_hw_probes -of_objects $ila] {
    set width [get_property WIDTH $probe]
    if {$width eq "" || $width < 1} { set width 1 }
    set_property TRIGGER_COMPARE_VALUE [format "eq%d'b%s" $width [string repeat X $width]] $probe
  }
  set_property CONTROL.DATA_DEPTH 4096 $ila
  # Preserve as much caller history as possible; only 96 samples follow entry.
  set_property CONTROL.TRIGGER_POSITION 4000 $ila
  set_property CONTROL.TRIGGER_CONDITION AND $ila
  set compare [format "eq226'b%s%s" [string repeat X 162] [format %064llb 0x$panic_pc]]
  # reset_hw_ila restores the default trigger; program the compare value after
  # reset so a held CPU cannot produce a match-all false capture.
  set_property TRIGGER_COMPARE_VALUE $compare $trace
  # This only works before the first CPU release; the loader locks afterward.
  axi_write $axi 0x7fffff00 {00000001}
  run_hw_ila $ila
  axi_write $axi 0x7fffff00 {00000000}
  # Vivado measures this timeout in minutes.
  wait_on_hw_ila -timeout 2 $ila
  set data [upload_hw_ila_data $ila]
  if {[llength $data] == 0} { error "panic entry was not captured" }
  file mkdir [file dirname $out]
  write_hw_ila_data -force -csv_file $out $data
  puts "RV64_PANIC_ENTRY_CAPTURE_PASS file=$out pc=$panic_pc"
} finally {
  if {$target_open} { close_hw_target }
  if {$server_connected} { disconnect_hw_server }
  if {$manager_open} { close_hw_manager }
}
