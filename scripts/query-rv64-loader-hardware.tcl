if {$argc != 1} {
  error "usage: query-rv64-loader-hardware.tcl <debug-probes.ltx>"
}

set debug_probes [file normalize [lindex $argv 0]]
if {![file exists $debug_probes] || ![file isfile $debug_probes]} {
  error "debug probes file does not exist: $debug_probes"
}

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
  set devices [get_hw_devices xc7k480t*]
  if {[llength $devices] != 1} {
    error "expected exactly one xc7k480t JTAG device, found: $devices"
  }
  set device [lindex $devices 0]
  current_hw_device $device
  set_property PROBES.FILE $debug_probes $device
  refresh_hw_device -update_hw_probes true $device

  set axis [get_hw_axis -of_objects $device]
  set ilas [get_hw_ilas -of_objects $device]
  puts "RV64_LOADER_HW_AXES count=[llength $axis]"
  puts "RV64_LOADER_HW_ILAS count=[llength $ilas]"
  foreach ila $ilas {
    set probes [get_hw_probes -of_objects $ila]
    puts "RV64_LOADER_HW_ILA name=[get_property NAME $ila] probes=[llength $probes]"
    report_property $ila
    foreach probe $probes {
      puts "RV64_LOADER_HW_PROBE name=[get_property NAME $probe]"
    }
  }
  puts "RV64_LOADER_HW_QUERY_PASS ltx=$debug_probes"
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
