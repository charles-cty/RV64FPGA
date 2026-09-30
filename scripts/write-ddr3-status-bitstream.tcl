if {$argc != 3} {
  error "usage: write-ddr3-status-bitstream.tcl <routed-checkpoint> <bitstream> <mcs>"
}
set routed_checkpoint [file normalize [lindex $argv 0]]
set bitstream [file normalize [lindex $argv 1]]
set mcs [file normalize [lindex $argv 2]]
open_checkpoint $routed_checkpoint
set_property IOSTANDARD DIFF_HSTL_II_18 [get_ports {sys_clk_p sys_clk_n}]
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS FALSE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 12 [current_design]
file mkdir [file dirname $bitstream]
file mkdir [file dirname $mcs]
report_drc -file [file join [file dirname $bitstream] pre_bitstream_drc.rpt]
write_bitstream -force $bitstream
write_cfgmem -format mcs -interface BPIx16 -size 64 -loadbit [list up 0x00000000 $bitstream] -force $mcs
puts "DDR3_STATUS_BITSTREAM_PASS bit=$bitstream mcs=$mcs"
close_design
