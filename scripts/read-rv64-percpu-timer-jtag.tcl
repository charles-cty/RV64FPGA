# Read CPU0's live per-CPU timer state out of DDR over JTAG while the loader
# holds the CPU.  Read-only.  Per-CPU variables live at link address +
# __per_cpu_offset[0]; the static copies under __per_cpu_load are templates.
#
# usage: read-rv64-percpu-timer-jtag.tcl <debug-probes.ltx> <output.txt>
if {$argc != 2} { error "usage: read-rv64-percpu-timer-jtag.tcl <debug-probes.ltx> <output.txt>" }
set probes [file normalize [lindex $argv 0]]
set out_file [file normalize [lindex $argv 1]]

# Kernel image: PA = low32(va) + 0x200000.  Linear map: VA 0xffffffd600000000
# maps to PA 0x80000000 (matches the 9-20 task-slab reads).
source [file join [file dirname [info script]] rv64-jtag-addresses.tcl]
proc kpa {va} { return [rv64_diag::kernel_pa $va] }
proc lpa {va} { return [rv64_diag::linear_pa $va] }

set per_cpu_offset_va 0xffffffff8151f650
set percpu_symbols [list \
  riscv_clock_event 0xffffffff80c3cbc0 32 \
  tick_cpu_device   0xffffffff80c396e0 6 \
  tick_cpu_sched    0xffffffff80c396f8 32 \
  hrtimer_bases     0xffffffff80c39240 48 \
]

set seq 0
proc txn_name {} { global seq; incr seq; return "rv64_pcpu_$seq" }
proc read_words {axi address count} {
  set n [txn_name]
  create_hw_axi_txn $n $axi -address [format %08x $address] -len $count -type READ
  run_hw_axi [get_hw_axi_txns $n]
  set r [get_property STATUS.RRESP $axi]
  set report [report_hw_axi_txn [get_hw_axi_txns $n] -t x4 -w 4]
  delete_hw_axi_txn [get_hw_axi_txns $n]
  if {$r ne "OKAY"} { error "read at [format %08x $address] returned $r" }
  set vals [regexp -all -inline -nocase {\m[0-9a-f]{8}\M} $report]
  set res {}
  for {set i 0} {$i + 1 < [llength $vals]} {incr i 2} {
    lappend res [string tolower [lindex $vals [expr {$i + 1}]]]
  }
  if {[llength $res] != $count} { error "short AXI read: expected $count words, got [llength $res]" }
  return $res
}

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7k480t*] 0]
current_hw_device $dev
set_property PROBES.FILE $probes $dev
refresh_hw_device -update_hw_probes true $dev
set axi [lindex [get_hw_axis -of_objects $dev] 0]
if {$axi eq ""} { error "no JTAG AXI core; reconfigure the loader bitstream" }

set status [lindex [read_words $axi 0x7fffff00 1] 0]
scan $status %x sv
if {($sv & 3) != 3} { error "CPU must be held with DDR calibrated: 0x$status" }

set out [open $out_file w]
set w [read_words $axi [kpa $per_cpu_offset_va] 2]
set offset [rv64_diag::words_value $w]
puts $out "__per_cpu_offset0 = 0x[rv64_diag::hex64 $offset]"
puts "PERCPU_OFFSET0 0x[rv64_diag::hex64 $offset]"
foreach {name va count} $percpu_symbols {
  set live [expr {($va + $offset) & 0xffffffffffffffff}]
  set words [read_words $axi [lpa $live] $count]
  puts $out [format "%-18s live_va=0x%s pa=0x%08x" $name [rv64_diag::hex64 $live] [lpa $live]]
  for {set i 0} {$i < $count} {incr i 2} {
    puts $out [format "  +0x%03x %s%s" [expr {$i * 4}] [lindex $words [expr {$i + 1}]] [lindex $words $i]]
  }
  puts "$name words={[join $words { }]}"
  flush stdout
}
close $out
puts "RV64_PERCPU_TIMER_READ_PASS file=$out_file"
close_hw_target
disconnect_hw_server
close_hw_manager
