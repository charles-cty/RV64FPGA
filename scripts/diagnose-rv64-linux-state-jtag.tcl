# Re-arm the loader, resetting the CPU/SoC, then read the retained Linux DDR
# state (jiffies, printk ring) over JTAG. This preserves DDR contents, but
# destroys live CPU/CSR/CLINT state; it is not a debugger halt.
#
# usage: diagnose-rv64-linux-state-jtag.tcl <debug-probes.ltx> <output-dir> <System.map> <logbuf-bytes>
if {$argc != 4} { error "usage: diagnose-rv64-linux-state-jtag.tcl <debug-probes.ltx> <output-dir> <System.map> <logbuf-bytes>" }
set probes [file normalize [lindex $argv 0]]
set out_dir [file normalize [lindex $argv 1]]
file mkdir $out_dir
set_msg_config -id {Labtoolstcl 44-481} -suppress

# OpenSBI loads the kernel Image to PA 0x80200000, so the kernel's VA base
# 0xffffffff80000000 maps to 0x80200000: PA = low32(va) + 0x200000.
source [file join [file dirname [info script]] rv64-jtag-addresses.tcl]
proc pa {va} { return [rv64_diag::kernel_pa $va] }

# Resolve addresses against the exact kernel supplied by the caller.
set symbols [open [lindex $argv 2] r]
set found [dict create]
while {[gets $symbols line] >= 0} {
  if {[regexp {^([0-9a-fA-F]+) +[^ ]+ +([^ ]+)$} $line -> address name]} {
    dict set found $name 0x$address
  }
}
close $symbols
set jiffies_va [dict get $found jiffies]
set prb_va [dict get $found prb]
set logbufptr_va [dict get $found log_buf]
set logbuf_va [dict get $found __log_buf]
set logbuf_size [lindex $argv 3]
if {![string is integer -strict $logbuf_size] || $logbuf_size < 1024 || $logbuf_size > 16777216 || $logbuf_size % 1024 != 0} {
  error "invalid printk buffer size"
}

set seq 0
proc txn_name {} { global seq; incr seq; return "rv64_diag_$seq" }

proc write_word {axi address value context} {
  set n [txn_name]
  create_hw_axi_txn $n $axi -address [format %08x $address] -data [list $value] -len 1 -type WRITE
  run_hw_axi [get_hw_axi_txns $n]
  set r [get_property STATUS.BRESP $axi]
  delete_hw_axi_txn [get_hw_axi_txns $n]
  puts "WRITE addr=[format %08x $address] value=$value BRESP=$r  ($context)"
  flush stdout
  return $r
}

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
if {$axi eq ""} { error "no JTAG AXI core after re-arm" }

set status [lindex [read_words $axi 0x7fffff00 1] 0]
puts "LOADER_STATUS_BEFORE=0x$status (bit1 calib, bit0 hold)"

# Re-arm: bit0 set re-asserts CPU hold and restores loader DDR ownership.
set bresp [write_word $axi 0x7fffff00 00000001 "re-arm CPU hold"]
if {$bresp ne "OKAY"} { error "re-arm was rejected: $bresp" }
after 200
set status [lindex [read_words $axi 0x7fffff00 1] 0]
puts "LOADER_STATUS_HELD=0x$status"
scan $status %x sv
if {($sv & 3) != 3} { error "CPU is not held with DDR calibrated: 0x$status" }

# Read retained jiffies once with the CPU held in reset.
set out [open [file join $out_dir jiffies.txt] w]
foreach {label addr} [list "jiffies" $jiffies_va] {
  set v [read_words $axi [pa $addr] 2]
  puts $out [format "%s pa=%08x words=%s" $label [pa $addr] $v]
}
close $out

# printk ring metadata and text.
set meta [open [file join $out_dir printk-metadata.txt] w]
foreach {label addr count} [list "prb" $prb_va 16 "log_buf_ptr" $logbufptr_va 2 "log_buf" $logbuf_va 4] {
  set v [read_words $axi [pa $addr] $count]
  puts $meta [format "%s pa=%08x %s" $label [pa $addr] $v]
  puts "META $label pa=[format %08x [pa $addr]] $v"
}
close $meta

set text [open [file join $out_dir printk-words.txt] w]
for {set offset 0} {$offset < $logbuf_size} {incr offset 1024} {
  set address [expr {[pa $logbuf_va] + $offset}]
  puts $text [format "%08x %s" $address [read_words $axi $address 256]]
}
close $text

puts "RV64_LINUX_STATE_READ_PASS dir=$out_dir"
close_hw_target
disconnect_hw_server
close_hw_manager
