if {$argc != 3} {
  error "usage: rearm-rv64-pc-jtag.tcl <debug-probes.ltx> <pc-hex> <capture.csv>"
}

set probes [file normalize [lindex $argv 0]]
set pc [string tolower [lindex $argv 1]]
set out [file normalize [lindex $argv 2]]
if {![regexp {^[0-9a-f]+$} $pc]} {
  error "PC must be hexadecimal without a 0x prefix: $pc"
}

set manager_open 0
set server_connected 0
set target_open 0
set sequence 0

proc transaction_name {} {
  global sequence
  incr sequence
  return "rv64_pc_rearm_$sequence"
}

proc write_control {axi value} {
  set transaction [transaction_name]
  create_hw_axi_txn $transaction $axi -address 7fffff00 -data [list $value] -len 1 -type WRITE
  run_hw_axi [get_hw_axi_txns $transaction]
  delete_hw_axi_txn [get_hw_axi_txns $transaction]
}

try {
  open_hw_manager
  set manager_open 1
  connect_hw_server -allow_non_jtag
  set server_connected 1
  open_hw_target
  set target_open 1

  set device [lindex [get_hw_devices xc7k480t*] 0]
  current_hw_device $device
  set_property PROBES.FILE $probes $device
  refresh_hw_device -update_hw_probes true $device

  set axi [lindex [get_hw_axis -of_objects $device] 0]
  set ila [lindex [get_hw_ilas -of_objects $device] 0]
  set trace [lindex [get_hw_probes -of_objects $ila -filter {NAME == "debug_commit_trace"}] 0]
  if {$axi eq "" || $ila eq "" || $trace eq ""} {
    error "missing JTAG AXI, ILA, or commit trace"
  }

  reset_hw_axi $axi
  write_control $axi 00000001
  after 100

  reset_hw_ila $ila
  set_property CONTROL.DATA_DEPTH 4096 $ila
  set_property CONTROL.TRIGGER_POSITION 2048 $ila
  set_property CONTROL.TRIGGER_CONDITION AND $ila
  foreach probe [get_hw_probes -of_objects $ila] {
    set width [get_property WIDTH $probe]
    set_property TRIGGER_COMPARE_VALUE [format "eq%d'b%s" $width [string repeat X $width]] $probe
  }
  set compare [format "eq226'b%s%s" [string repeat X 162] [format %064llb 0x$pc]]
  set_property TRIGGER_COMPARE_VALUE $compare $trace
  run_hw_ila $ila
  write_control $axi 00000000
  puts "RV64_PC_REARM_RELEASED pc=$pc"
  flush stdout

  wait_on_hw_ila -timeout 2 $ila
  set data [upload_hw_ila_data $ila]
  if {[llength $data] == 0} {
    error "no PC capture for $pc"
  }
  file mkdir [file dirname $out]
  write_hw_ila_data -force -csv_file $out $data
  puts "RV64_PC_REARM_CAPTURE_PASS pc=$pc file=$out"
} finally {
  if {$target_open} { close_hw_target }
  if {$server_connected} { disconnect_hw_server }
  if {$manager_open} { close_hw_manager }
}
