if {$argc != 2} { error "usage: capture-rv64-first-trap-jtag.tcl <debug-probes.ltx> <capture.csv>" }
set probes [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
set opened 0
set connected 0
set target 0
set seq 0
proc txn_name {} { global seq; incr seq; return "trap_capture_$seq" }
proc ctl {axi value} {
  set n [txn_name]
  create_hw_axi_txn $n $axi -address 7fffff00 -data [list $value] -len 1 -type WRITE
  run_hw_axi [get_hw_axi_txns $n]
  set response [get_property STATUS.BRESP $axi]
  delete_hw_axi_txn [get_hw_axi_txns $n]
  if {$response ne "OKAY"} {
    error "CPU control write failed: $response; reconfigure SRAM and reload in hold mode first"
  }
}
try {
  open_hw_manager; set opened 1
  connect_hw_server -allow_non_jtag; set connected 1
  open_hw_target; set target 1
  set dev [lindex [get_hw_devices xc7k480t*] 0]
  current_hw_device $dev
  set_property PROBES.FILE $probes $dev
  refresh_hw_device -update_hw_probes true $dev
  set axi [lindex [get_hw_axis -of_objects $dev] 0]
  set ila [lindex [get_hw_ilas -of_objects $dev] 0]
  if {$axi eq "" || $ila eq ""} { error "missing JTAG AXI or ILA" }
  reset_hw_ila $ila
  set status [lindex [get_hw_probes -of_objects $ila -filter {NAME == "debug_status"}] 0]
  if {$status eq ""} { error "missing debug_status probe" }
  foreach probe [get_hw_probes -of_objects $ila] {
    set width [get_property WIDTH $probe]
    if {$width eq "" || $width < 1} { set width 1 }
    set_property TRIGGER_COMPARE_VALUE [format "eq%d'b%s" $width [string repeat X $width]] $probe
  }
  set_property CONTROL.DATA_DEPTH 4096 $ila
  set_property CONTROL.TRIGGER_POSITION 3072 $ila
  set_property CONTROL.TRIGGER_CONDITION AND $ila
  # debug_status = {illegal, trap, commit, reset_n, hold, calib};
  # Match trap-valid regardless of the illegal-instruction status bit.
  set_property TRIGGER_COMPARE_VALUE {eq6'bX1XXXX} $status
  reset_hw_axi $axi
  ctl $axi 00000001
  run_hw_ila $ila
  ctl $axi 00000000
  # Vivado measures this timeout in minutes.
  wait_on_hw_ila -timeout 2 $ila
  set data [upload_hw_ila_data $ila]
  if {[llength $data] == 0} { error "no first-trap capture" }
  file mkdir [file dirname $out]
  write_hw_ila_data -force -csv_file $out $data
  puts "RV64_FIRST_TRAP_CAPTURE_PASS file=$out"
} finally {
  if {$target} { close_hw_target }
  if {$connected} { disconnect_hw_server }
  if {$opened} { close_hw_manager }
}
