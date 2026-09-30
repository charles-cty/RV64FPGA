if {$argc != 2} {
  error "usage: capture-rv64-cpu-jtag.tcl <debug-probes.ltx> <capture.csv>"
}

set debug_probes [file normalize [lindex $argv 0]]
set capture_file [file normalize [lindex $argv 1]]
foreach path [list $debug_probes] {
  if {![file exists $path] || ![file isfile $path]} {
    error "input file does not exist: $path"
  }
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

  set ilas [get_hw_ilas -of_objects $device]
  if {[llength $ilas] != 1} {
    error "expected exactly one ILA core, found: $ilas"
  }
  set ila [lindex $ilas 0]
  set reset_probes [get_hw_probes -of_objects $ila -filter {NAME == "cpu_reset"}]
  if {[llength $reset_probes] != 1} {
    error "expected exactly one cpu_reset probe, found: $reset_probes"
  }

  reset_hw_ila $ila
  set_property CONTROL.DATA_DEPTH 4096 $ila
  set_property CONTROL.TRIGGER_POSITION 0 $ila
  set_property CONTROL.TRIGGER_CONDITION AND $ila
  set_property TRIGGER_COMPARE_VALUE {eq1'b0} [lindex $reset_probes 0]
  run_hw_ila $ila
  wait_on_hw_ila -timeout 5 $ila
  set capture [upload_hw_ila_data $ila]
  if {[llength $capture] == 0} {
    error "CPU ILA did not produce a capture"
  }

  file mkdir [file dirname $capture_file]
  file delete -force $capture_file
  write_hw_ila_data -force -csv_file $capture_file $capture
  set handle [open $capture_file r]
  set lines [split [read $handle] "\n"]
  close $handle
  set nonempty_lines 0
  foreach line $lines {
    if {[string trim $line] ne ""} {
      incr nonempty_lines
    }
  }
  if {$nonempty_lines <= 2} {
    error "CPU ILA capture contains no samples: $capture_file"
  }
  puts "RV64_CPU_CAPTURE_PASS file=$capture_file samples=[expr {$nonempty_lines - 2}]"
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
