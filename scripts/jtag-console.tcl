# Persistent, file-spooled terminal bridge. Never writes loader control/DDR.
# Run only after programming the console-enabled bitstream and releasing CPU.
if {$argc != 2} {error "usage: jtag-console.tcl <probes.ltx> <session-directory>"}
set probes [file normalize [lindex $argv 0]]
set session [file normalize [lindex $argv 1]]
set sequence 0
set attached 0
set axi ""
set_msg_config -id {Labtoolstcl 44-481} -suppress
proc reg_read {address} {
  global axi sequence
  set name jc_[incr sequence]
  create_hw_axi_txn $name $axi -address [format %08x $address] -len 1 -type READ
  try {
    run_hw_axi [get_hw_axi_txns $name]
    if {[get_property STATUS.RRESP $axi] ne "OKAY"} {error "console read rejected at [format %08x $address]"}
    set report [report_hw_axi_txn [get_hw_axi_txns $name] -t x4 -w 4]
    set words [regexp -all -inline -nocase {\m[0-9a-f]{8}\M} $report]
    if {[llength $words] < 2} {error "invalid console read report: $report"}
    return [expr {0 + "0x[lindex $words end]"}]
  } finally {delete_hw_axi_txn [get_hw_axi_txns $name]}
}
proc reg_write {address value} {
  global axi sequence
  set name jc_[incr sequence]
  create_hw_axi_txn $name $axi -address [format %08x $address] -len 1 -type WRITE -data [list [format %08x $value]]
  try {
    run_hw_axi [get_hw_axi_txns $name]
    if {[get_property STATUS.BRESP $axi] ne "OKAY"} {error "console write rejected at [format %08x $address]"}
  } finally {delete_hw_axi_txn [get_hw_axi_txns $name]}
}
try {
  open_hw_manager
  connect_hw_server -allow_non_jtag
  open_hw_target
  set devices [get_hw_devices xc7k480t*]
  if {[llength $devices] != 1} {error "expected exactly one xc7k480t"}
  set dev [lindex $devices 0]
  current_hw_device $dev
  set_property PROBES.FILE $probes $dev
  refresh_hw_device -update_hw_probes true $dev
  set axis [get_hw_axis -of_objects $dev]
  if {[llength $axis] != 1} {error "expected exactly one JTAG AXI master"}
  set axi [lindex $axis 0]
  if {[reg_read 0x7ffffe00] != 0x4a544331} {error "JTC1 not found; use the console-enabled bitstream"}
  if {[reg_read 0x7fffff00] & 1} {error "CPU is held; load and release Linux before attaching"}
  reg_write 0x7ffffe14 1
  set attached 1
  set out [open [file join $session output.bin] ab]
  fconfigure $out -translation binary -buffering none
  set ready [open [file join $session ready] w]; puts $ready JTC1; close $ready
  set position 0
  set pending ""
  set last_dropped -1
  set last_heartbeat ""
  set last_seen [clock milliseconds]
  while {![file exists [file join $session stop]]} {
    set heartbeat [file join $session heartbeat]
    if {![file exists $heartbeat]} {break}
    set hb [open $heartbeat r]; set value [read $hb]; close $hb
    if {$value ne "" && $value ne $last_heartbeat} {
      set last_seen [clock milliseconds]; set last_heartbeat $value
    }
    if {[clock milliseconds] - $last_seen > 5000} {break}
    # Renew after possible lease expiry; never silently retain a disconnected state.
    reg_write 0x7ffffe14 1
    set input [open [file join $session input.bin] rb]
    fconfigure $input -translation binary
    seek $input $position start
    append pending [read $input [expr {256 - [string length $pending]}]]
    set position [tell $input]
    close $input
    set free [reg_read 0x7ffffe04]
    set send [expr {min($free, [string length $pending], 32)}]
    for {set i 0} {$i < $send} {incr i} {
      binary scan [string index $pending $i] c byte
      reg_write 0x7ffffe0c [expr {$byte & 255}]
    }
    set pending [string range $pending $send end]
    set count [expr {min([reg_read 0x7ffffe08], 128)}]
    for {set i 0} {$i < $count} {incr i} {
      set word [reg_read 0x7ffffe0c]
      if {!($word & 0x80000000)} {error "TX count changed unexpectedly; another client may be consuming data"}
      puts -nonewline $out [binary format c [expr {$word & 255}]]
    }
    set dropped [reg_read 0x7ffffe10]
    if {$dropped != $last_dropped} {
      set status [open [file join $session dropped.txt] w]; puts $status $dropped; close $status
      set last_dropped $dropped
    }
    after 10
  }
  close $out
  puts JTAG_CONSOLE_STOPPED
} finally {
  if {$attached} {catch {reg_write 0x7ffffe14 0}}
  catch {close_hw_target}
  catch {disconnect_hw_server}
  catch {close_hw_manager}
}
