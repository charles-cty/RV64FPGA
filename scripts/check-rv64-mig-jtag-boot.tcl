open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set devices [get_hw_devices xc7k480t*]
if {[llength $devices] != 1} {
  error "expected exactly one xc7k480t JTAG device, found: $devices"
}
set dev [lindex $devices 0]
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev
puts "JTAG_DEVICE $dev"
puts "JTAG_PART [get_property PART $dev]"
puts "JTAG_CORES [llength [get_hw_cores -quiet]]"
puts "JTAG_BOOT_CHECK_DONE"
close_hw_target
disconnect_hw_server
close_hw_manager
