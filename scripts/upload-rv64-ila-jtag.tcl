if {$argc != 2} {
  error "usage: upload-rv64-ila-jtag.tcl <debug-probes.ltx> <capture.csv>"
}

set probes [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
set manager_open 0
set server_connected 0
set target_open 0

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
  set ila [lindex [get_hw_ilas -of_objects $device] 0]
  set data [upload_hw_ila_data $ila]
  if {[llength $data] == 0} {
    error "ILA has no completed capture"
  }
  file mkdir [file dirname $out]
  write_hw_ila_data -force -csv_file $out $data
  puts "RV64_ILA_UPLOAD_PASS file=$out"
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
