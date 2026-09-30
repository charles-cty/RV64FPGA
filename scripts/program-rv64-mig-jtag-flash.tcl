if {$argc != 2} {
  error "usage: program-rv64-mig-jtag-flash.tcl <bitstream> <mcs>"
}

set bitstream [file normalize [lindex $argv 0]]
set mcs [file normalize [lindex $argv 1]]
if {![file exists $bitstream]} { error "bitstream does not exist: $bitstream" }
if {![file exists $mcs]} { error "MCS file does not exist: $mcs" }

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

set_property PROGRAM.FILE $bitstream $dev
program_hw_devices $dev
refresh_hw_device -update_hw_probes false $dev
puts "JTAG_PROGRAM_DONE"

set cfgmem_parts [get_cfgmem_parts {mt28gu512aax1e-bpi-x16}]
if {[llength $cfgmem_parts] < 1} {
  error "no mt28gu512aax1e-bpi-x16 cfgmem part is available"
}
create_hw_cfgmem -hw_device $dev [lindex $cfgmem_parts 0]
set cfg [get_property PROGRAM.HW_CFGMEM $dev]
set_property PROGRAM.ADDRESS_RANGE {use_file} $cfg
set_property PROGRAM.FILES [list $mcs] $cfg
set_property PROGRAM.BLANK_CHECK 0 $cfg
set_property PROGRAM.ERASE 1 $cfg
set_property PROGRAM.CFG_PROGRAM 1 $cfg
set_property PROGRAM.VERIFY 1 $cfg
set_property PROGRAM.CHECKSUM 0 $cfg

create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
program_hw_devices $dev
refresh_hw_device -update_hw_probes false $dev
puts "BPI_BRIDGE_LOADED"

program_hw_cfgmem -hw_cfgmem $cfg
puts "FLASH_PROGRAM_DONE"

boot_hw_device $dev
refresh_hw_device -update_hw_probes false $dev
puts "FLASH_BOOT_DONE"

close_hw_target
disconnect_hw_server
close_hw_manager
