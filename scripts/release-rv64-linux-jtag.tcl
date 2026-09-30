if {$argc < 3 || $argc > 4} {
  error "usage: release-rv64-linux-jtag.tcl <debug-probes.ltx> <capture.csv> <target-pc-hex> ?timeout-minutes?"
}

set probes [file normalize [lindex $argv 0]]
set output_file [file normalize [lindex $argv 1]]
set target_pc [string tolower [lindex $argv 2]]
set timeout_minutes 3
if {$argc == 4} {
  set timeout_minutes [lindex $argv 3]
}
if {![string is integer -strict $timeout_minutes] || $timeout_minutes < 1} {
  error "timeout-minutes must be a positive integer"
}
set manager_open 0
set server_connected 0
set target_open 0
set sequence 0

proc transaction_name {prefix} {
  global sequence
  incr sequence
  return [format "rv64_release_%s_%d" $prefix $sequence]
}

proc release_cpu {axi} {
  set transaction [transaction_name write]
  create_hw_axi_txn $transaction $axi -address 7fffff00 -data {00000000} -len 1 -type WRITE
  # The control write transfers DDR ownership from the loader to the CPU.
  # Waiting synchronously for its BRESP can deadlock while that handoff is
  # occurring; queue the one transaction and let the ILA observe the CPU.
  run_hw_axi -queue [get_hw_axi_txns $transaction]
  delete_hw_axi_txn [get_hw_axi_txns $transaction]
}

proc read_loader_status {axi} {
  set transaction [transaction_name read]
  create_hw_axi_txn $transaction $axi -address 7fffff00 -len 1 -type READ
  run_hw_axi [get_hw_axi_txns $transaction]
  set response [get_property STATUS.RRESP $axi]
  set report [report_hw_axi_txn [get_hw_axi_txns $transaction] -t x4 -w 4]
  delete_hw_axi_txn [get_hw_axi_txns $transaction]
  if {$response ne "OKAY"} {
    error "loader status read returned AXI response $response"
  }
  set values [regexp -all -inline -nocase {\m[0-9a-f]{8}\M} $report]
  if {[llength $values] == 0} {
    error "loader status read returned no data: $report"
  }
  return [string tolower [lindex $values end]]
}

try {
  open_hw_manager
  set manager_open 1
  connect_hw_server -allow_non_jtag
  set server_connected 1
  open_hw_target
  set target_open 1
  set device [lindex [get_hw_devices xc7k480t*] 0]
  if {$device eq ""} {
    error "XC7K480T JTAG device was not found"
  }
  current_hw_device $device
  set_property PROBES.FILE $probes $device
  refresh_hw_device -update_hw_probes true $device

  set axis [get_hw_axis -of_objects $device]
  if {[llength $axis] != 1} {
    error "expected one JTAG AXI core, found: $axis"
  }
  set axi [lindex $axis 0]
  reset_hw_axi $axi
  set status [read_loader_status $axi]
  scan $status %x status_value
  if {($status_value & 0x3) != 0x3} {
    error "loader is not held and calibrated: status=0x$status"
  }
  set ilas [get_hw_ilas -of_objects $device]
  if {[llength $ilas] != 1} {
    error "expected one ILA core, found: $ilas"
  }
  set ila [lindex $ilas 0]
  set traces [get_hw_probes -of_objects $ila -filter {NAME == "debug_commit_trace"}]
  if {[llength $traces] != 1} {
    error "expected one debug_commit_trace probe, found: $traces"
  }
  set trace [lindex $traces 0]
  reset_hw_ila $ila
  set_property CONTROL.DATA_DEPTH 4096 $ila
  set_property CONTROL.TRIGGER_POSITION 3072 $ila
  set_property CONTROL.TRIGGER_CONDITION AND $ila
  set compare [format "eq226'b%s%s" [string repeat X 162] [format %064llb 0x$target_pc]]
  set_property TRIGGER_COMPARE_VALUE $compare $trace
  run_hw_ila $ila
  puts "RV64_RELEASE_ILA_ARMED pc=$target_pc timeout_minutes=$timeout_minutes"

  release_cpu $axi
  wait_on_hw_ila -timeout $timeout_minutes $ila
  set data [upload_hw_ila_data $ila]
  if {[llength $data] == 0} {
    error "release capture returned no ILA data"
  }
  file mkdir [file dirname $output_file]
  write_hw_ila_data -force -csv_file $output_file $data
  puts "RV64_RELEASE_CAPTURE_PASS file=$output_file"
} finally {
  if {$target_open} {
    close_hw_target
  }
  if {$server_connected} {
    disconnect_hw_server
  }
  if {$manager_open} {
    close_hw_manager
  }
}
