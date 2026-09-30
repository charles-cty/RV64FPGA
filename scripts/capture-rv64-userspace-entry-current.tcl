if {$argc < 2 || $argc > 3} { error "usage: capture-rv64-userspace-entry-current.tcl <debug-probes.ltx> <capture.csv> ?release?" }
if {$argc == 3 && [lindex $argv 2] ne "release"} { error "third argument must be release" }
set probes [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7k480t*] 0]
current_hw_device $dev
set_property PROBES.FILE $probes $dev
refresh_hw_device -update_hw_probes true $dev
set ila [lindex [get_hw_ilas -of_objects $dev] 0]
set trace [lindex [get_hw_probes -of_objects $ila -filter {NAME == "debug_commit_trace"}] 0]
reset_hw_ila $ila
foreach probe [get_hw_probes -of_objects $ila] {
  set width [get_property WIDTH $probe]
  set_property TRIGGER_COMPARE_VALUE [format "eq%d'b%s" $width [string repeat X $width]] $probe
}
set_property CONTROL.DATA_DEPTH 4096 $ila
set_property CONTROL.TRIGGER_POSITION 0 $ila
set_property CONTROL.TRIGGER_CONDITION AND $ila
set pc [format %064llb 0x100b0]
set_property TRIGGER_COMPARE_VALUE [format "eq226'b%s00%s%s" [string repeat X 64] [string repeat X 96] $pc] $trace
set status [lindex [get_hw_probes -of_objects $ila -filter {NAME == "debug_status"}] 0]
set_property TRIGGER_COMPARE_VALUE {eq6'bXX1XXX} $status
run_hw_ila $ila
if {$argc == 3} {
  set axi [lindex [get_hw_axis -of_objects $dev] 0]
  create_hw_axi_txn userspace_release $axi -address 7fffff00 -data {00000000} -len 1 -type WRITE
  run_hw_axi [get_hw_axi_txns userspace_release]
  set response [get_property STATUS.BRESP $axi]
  delete_hw_axi_txn [get_hw_axi_txns userspace_release]
  if {$response ne "OKAY"} { error "CPU release failed: $response; load in hold mode first" }
}
# The Linux 6.12 image spends about three minutes in jitterentropy setup on
# this core before reaching later initcalls. Allow that boot work to finish.
wait_on_hw_ila -timeout 15 $ila
set data [upload_hw_ila_data $ila]
if {[llength $data] == 0} { error "userspace entry was not observed" }
file mkdir [file dirname $out]
write_hw_ila_data -force -csv_file $out $data
puts "RV64_USERSPACE_ENTRY_CAPTURE_PASS file=$out"
close_hw_target
disconnect_hw_server
close_hw_manager
