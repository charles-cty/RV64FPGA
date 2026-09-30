if {$argc != 3} { error "usage: capture-rv64-pc-jtag.tcl <debug-probes.ltx> <pc_hex> <capture.csv>" }
set probes [file normalize [lindex $argv 0]]
set pc [string tolower [lindex $argv 1]]
set out [file normalize [lindex $argv 2]]
set m 0; set s 0; set t 0
try {
  open_hw_manager; set m 1
  connect_hw_server -allow_non_jtag; set s 1
  open_hw_target; set t 1
  set dev [lindex [get_hw_devices xc7k480t*] 0]; current_hw_device $dev
  set_property PROBES.FILE $probes $dev; refresh_hw_device -update_hw_probes true $dev
  set ila [lindex [get_hw_ilas -of_objects $dev] 0]
  set p [lindex [get_hw_probes -of_objects $ila -filter {NAME == "debug_commit_trace"}] 0]
  reset_hw_ila $ila
  set_property CONTROL.DATA_DEPTH 4096 $ila
  set_property CONTROL.TRIGGER_POSITION 3072 $ila
  set_property CONTROL.TRIGGER_CONDITION AND $ila
  set compare [format "eq226'b%s%s" [string repeat X 162] [format %064llb 0x$pc]]
  foreach probe [get_hw_probes -of_objects $ila] {
    set width [get_property WIDTH $probe]
    set_property TRIGGER_COMPARE_VALUE [format "eq%d'b%s" $width [string repeat X $width]] $probe
  }
  set_property TRIGGER_COMPARE_VALUE $compare $p
  puts "RV64_PC_COMPARE=[get_property TRIGGER_COMPARE_VALUE $p]"
  run_hw_ila $ila
  wait_on_hw_ila -timeout 1 $ila
  set d [upload_hw_ila_data $ila]
  if {[llength $d] == 0} { error "no PC capture" }
  file mkdir [file dirname $out]; write_hw_ila_data -force -csv_file $out $d
  puts "RV64_PC_CAPTURE_PASS pc=$pc file=$out"
} finally {
  if {$t} { close_hw_target }; if {$s} { disconnect_hw_server }; if {$m} { close_hw_manager }
}
