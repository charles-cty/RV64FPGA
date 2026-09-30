# Read named kernel addresses out of DDR over JTAG while the loader holds the
# CPU.  Read-only; the payload image is inspected, never modified.
#
# usage: read-rv64-kernel-symbols-jtag.tcl <debug-probes.ltx> <output.txt>
if {$argc != 2} { error "usage: read-rv64-kernel-symbols-jtag.tcl <debug-probes.ltx> <output.txt>" }
set probes [file normalize [lindex $argv 0]]
set out_file [file normalize [lindex $argv 1]]

# OpenSBI loads the kernel Image at PA 0x80200000, so kernel VA base
# 0xffffffff80000000 maps to 0x80200000: PA = low32(va) + 0x200000.
source [file join [file dirname [info script]] rv64-jtag-addresses.tcl]
proc pa {va} { return [rv64_diag::kernel_pa $va] }

set symbols [list \
  jiffies            0xffffffff81409940 2 \
  irq_stat           0xffffffff80c3cd00 4 \
  nr_irqs            0xffffffff814e87bc 1 \
  tick_do_timer_cpu  0xffffffff814e88f8 1 \
  tick_nohz_active   0xffffffff814eb720 1 \
  riscv_ce_irq       0xffffffff814ed1a4 1 \
  riscv_ce_no_wake   0xffffffff814ed1a8 1 \
  riscv_clock_event  0xffffffff80c3cbc0 16 \
  tick_cpu_device    0xffffffff80c396e0 16 \
  riscv_clocksource  0xffffffff814ccd80 12 \
]

set seq 0
proc txn_name {} { global seq; incr seq; return "rv64_sym_$seq" }

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
foreach {name va count} $symbols {
  set words [read_words $axi [pa $va] $count]
  # Print a scalar only for scalar reads; structures remain raw word arrays.
  set scalar ""
  if {$count <= 2} { set scalar " value=[rv64_diag::words_value $words]" }
  puts $out [format "%-20s va=0x%s pa=0x%08x words={%s}%s" \
    $name [rv64_diag::hex64 $va] [pa $va] [join $words " "] $scalar]
  puts [format "%-20s words={%s}" $name [join $words " "]]
  flush stdout
}
close $out
puts "RV64_KERNEL_SYMBOLS_READ_PASS file=$out_file"
close_hw_target
disconnect_hw_server
close_hw_manager
