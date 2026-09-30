if {$argc != 3} { error "usage: capture-rv64-memory-address-jtag.tcl <debug-probes.ltx> <address_hex> <capture.csv>" }
set probes [file normalize [lindex $argv 0]]; set addr [string tolower [lindex $argv 1]]; set out [file normalize [lindex $argv 2]]
set m 0; set s 0; set t 0
try {
  open_hw_manager; set m 1; connect_hw_server -allow_non_jtag; set s 1; open_hw_target; set t 1
  set dev [lindex [get_hw_devices xc7k480t*] 0]; current_hw_device $dev
  set_property PROBES.FILE $probes $dev; refresh_hw_device -update_hw_probes true $dev
  set ila [lindex [get_hw_ilas -of_objects $dev] 0]
  set p [lindex [get_hw_probes -of_objects $ila -filter {NAME == "debug_memory_trace"}] 0]
  set_property CONTROL.DATA_DEPTH 4096 $ila; set_property CONTROL.TRIGGER_POSITION 2048 $ila
  set_property CONTROL.TRIGGER_CONDITION AND $ila
  set compare [format "eq130'b1%s%s" [format %064llb 0x$addr] [string repeat X 65]]
  set_property TRIGGER_COMPARE_VALUE $compare $p
  reset_hw_ila $ila; run_hw_ila $ila; wait_on_hw_ila -timeout 30 $ila
  set d [upload_hw_ila_data $ila]; if {[llength $d] == 0} { error "no memory capture" }
  file mkdir [file dirname $out]; write_hw_ila_data -force -csv_file $out $d
  puts "RV64_MEMORY_CAPTURE_PASS address=$addr file=$out"
} finally { if {$t} {close_hw_target}; if {$s} {disconnect_hw_server}; if {$m} {close_hw_manager} }
