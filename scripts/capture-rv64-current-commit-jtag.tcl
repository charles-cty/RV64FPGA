if {$argc != 2} { error "usage: capture-rv64-current-commit-jtag.tcl <debug-probes.ltx> <capture.csv>" }
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
set status [lindex [get_hw_probes -of_objects $ila -filter {NAME == "debug_status"}] 0]
reset_hw_ila $ila
foreach probe [get_hw_probes -of_objects $ila] {
  set width [get_property WIDTH $probe]
  set_property TRIGGER_COMPARE_VALUE [format "eq%d'b%s" $width [string repeat X $width]] $probe
}
set_property CONTROL.DATA_DEPTH 4096 $ila
set_property CONTROL.TRIGGER_POSITION 0 $ila
set_property CONTROL.TRIGGER_CONDITION AND $ila
# debug_status bit 3 is commit_valid; wildcard all other status bits.
set_property TRIGGER_COMPARE_VALUE {eq6'bXX1XXX} $status
run_hw_ila $ila
wait_on_hw_ila -timeout 1 $ila
set data [upload_hw_ila_data $ila]
if {[llength $data] == 0} { error "no current commit capture" }
file mkdir [file dirname $out]
write_hw_ila_data -force -csv_file $out $data
puts "RV64_CURRENT_COMMIT_CAPTURE_PASS file=$out"
close_hw_target
disconnect_hw_server
close_hw_manager
