# Arm the debug ILA for the first trap on an already-running CPU and upload the
# capture.  This does not touch the loader control register, so it works after
# the CPU has been released and DDR ownership has moved to the CPU.
if {$argc != 2} { error "usage: arm-rv64-trap-capture-jtag.tcl <debug-probes.ltx> <capture.csv>" }
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
if {$ila eq ""} { error "no ILA core is visible" }
reset_hw_ila $ila
foreach probe [get_hw_probes -of_objects $ila] {
  set width [get_property WIDTH $probe]
  if {$width eq "" || $width < 1} { set width 1 }
  set_property TRIGGER_COMPARE_VALUE [format "eq%d'b%s" $width [string repeat X $width]] $probe
}
set_property CONTROL.DATA_DEPTH 4096 $ila
set_property CONTROL.TRIGGER_POSITION 3072 $ila
set_property CONTROL.TRIGGER_CONDITION AND $ila
set status [lindex [get_hw_probes -of_objects $ila -filter {NAME == "debug_status"}] 0]
if {$status eq ""} { error "missing debug_status probe" }
# debug_status = {illegal, trap, commit, reset_n, hold, calib}.
set_property TRIGGER_COMPARE_VALUE {eq6'bX1XXXX} $status
run_hw_ila $ila
# Vivado measures this timeout in minutes.
wait_on_hw_ila -timeout 2 $ila
set data [upload_hw_ila_data $ila]
if {[llength $data] == 0} { error "no trap was observed" }
file mkdir [file dirname $out]
write_hw_ila_data -force -csv_file $out $data
puts "RV64_TRAP_CAPTURE_PASS file=$out"
close_hw_target
disconnect_hw_server
close_hw_manager
