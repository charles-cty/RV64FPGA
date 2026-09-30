if {$argc < 3 || $argc > 4} {
  error "usage: write-rv64-mig-bitstream.tcl <routed-checkpoint> <bitstream> <mcs> ?debug-probes.ltx?"
}

set routed_checkpoint [file normalize [lindex $argv 0]]
set bitstream [file normalize [lindex $argv 1]]
set mcs [file normalize [lindex $argv 2]]
set debug_probes ""
if {$argc == 4} {
  set debug_probes [file normalize [lindex $argv 3]]
}

if {![file exists $routed_checkpoint]} {
  error "routed checkpoint does not exist: $routed_checkpoint"
}

file mkdir [file dirname $bitstream]
file mkdir [file dirname $mcs]
if {$debug_probes ne ""} {
  file mkdir [file dirname $debug_probes]
}
open_checkpoint $routed_checkpoint
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS FALSE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 12 [current_design]
write_bitstream -force $bitstream
if {$debug_probes ne ""} {
  write_debug_probes -force $debug_probes
}
write_cfgmem -format mcs -interface BPIx16 -size 64 \
  -loadbit [list up 0x00000000 $bitstream] \
  -force $mcs
puts "RV64_MIG_BITSTREAM_PASS bit=$bitstream mcs=$mcs"
if {$debug_probes ne ""} {
  puts "RV64_MIG_DEBUG_PROBES_PASS ltx=$debug_probes"
}
close_design
