# Observe live execution without writing loader control or resetting the CPU.
if {$argc != 2} { error "usage: capture-progress.tcl <probes.ltx> <output-dir>" }
set probes [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
file mkdir $out
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7k480t*] 0]
current_hw_device $dev
set_property PROBES.FILE $probes $dev
refresh_hw_device -update_hw_probes true $dev
set ila [lindex [get_hw_ilas -of_objects $dev] 0]
set status [lindex [get_hw_probes -of_objects $ila -filter {NAME == "debug_status"}] 0]
set trace [lindex [get_hw_probes -of_objects $ila -filter {NAME == "debug_commit_trace"}] 0]
foreach kind {user loadfault fetchfault current1 current2 current3} {
    reset_hw_ila $ila
    foreach probe [get_hw_probes -of_objects $ila] {
        set width [get_property WIDTH $probe]
        set_property TRIGGER_COMPARE_VALUE [format "eq%d'b%s" $width [string repeat X $width]] $probe
    }
    set_property CONTROL.DATA_DEPTH 4096 $ila
    set_property CONTROL.TRIGGER_POSITION 2048 $ila
    set_property CONTROL.TRIGGER_CONDITION AND $ila
    set_property TRIGGER_COMPARE_VALUE {eq6'bXX1XXX} $status
    if {$kind eq "user"} {
        set_property TRIGGER_COMPARE_VALUE [format "eq226'b%s00%s" [string repeat X 64] [string repeat X 160]] $trace
    } elseif {$kind eq "loadfault" || $kind eq "fetchfault"} {
        set cause [expr {$kind eq "loadfault" ? 13 : 12}]
        set_property TRIGGER_COMPARE_VALUE {eq6'bX11XXX} $status
        set_property TRIGGER_COMPARE_VALUE [format "eq226'b%s%s%s" [string repeat X 66] [format %064llb $cause] [string repeat X 96]] $trace
    }
    run_hw_ila $ila
    if {[catch {wait_on_hw_ila -timeout 1 $ila} reason]} {
        puts "LIVE_CAPTURE_TIMEOUT kind=$kind reason=$reason"
        continue
    }
    set data [upload_hw_ila_data $ila]
    if {[llength $data] == 0} {
        puts "LIVE_CAPTURE_NO_MATCH kind=$kind"
        continue
    }
    write_hw_ila_data -force -csv_file [file join $out $kind.csv] $data
    puts "LIVE_CAPTURE_PASS kind=$kind"
}
close_hw_target
disconnect_hw_server
close_hw_manager
