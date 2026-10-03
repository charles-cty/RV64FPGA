if {$argc < 2 || $argc > 5} {
  error "usage: load-rv64-linux-jtag.tcl <payload.bin> <debug-probes.ltx> ?sample-count? ?hold|startup|first-trap|first-s-trap|first-s-illegal|kernel-park|panic? ?ddr-scrub.bin?"
}

set payload_file [file normalize [lindex $argv 0]]
set debug_probes [file normalize [lindex $argv 1]]
set sample_count 16
if {$argc >= 3} {
  set sample_count [lindex $argv 2]
}
set capture_mode startup
if {$argc >= 4} {
  set capture_mode [lindex $argv 3]
}
if {![file exists $payload_file] || ![file isfile $payload_file]} {
  error "payload file does not exist: $payload_file"
}
if {![file exists $debug_probes] || ![file isfile $debug_probes]} {
  error "debug probes file does not exist: $debug_probes"
}
if {![string is integer -strict $sample_count] || $sample_count < 1} {
  error "sample-count must be a positive integer"
}
if {$capture_mode ni {hold startup first-trap first-s-trap first-s-illegal kernel-park panic}} {
  error "capture mode must be hold, startup, first-trap, first-s-trap, first-s-illegal, kernel-park, or panic: $capture_mode"
}

set scrub_image [file normalize [file join [file dirname [info script]] .. build boot ddr-scrub.bin]]
if {$argc == 5} {set scrub_image [file normalize [lindex $argv 4]]}
if {![file isfile $scrub_image] || [file size $scrub_image] != 136} {
  error "missing/invalid DDR scrub image; run scripts/build-ddr-scrub.sh: $scrub_image"
}

set control_address 0x7fffff00
set ddr_base_address 0x80000000
set diagnostic_address 0x8ff00000
# Matches the OpenSBI FW_PAYLOAD_FDT_OFFSET=0x10000000 relocation.
# Linux hashes the expanded FDT totalsize, including OpenSBI's unused padding.
set dtb_workspace_address 0x90000000
set dtb_workspace_bytes 65536
set max_payload_bytes [expr {$diagnostic_address - $ddr_base_address}]
set maximum_words_per_transaction 256
# The JTAG AXI core may report only the final BRESP for a queued batch.  A
# single failed transaction can therefore go unnoticed and leave stale DDR
# contents.  Run writes individually until the loader has per-transaction
# response accounting.
set configured_write_queue_length 1
set progress_interval_bytes 1048576
set transaction_sequence 0

if {[llength [info commands set_msg_config]] != 0} {
  set_msg_config -id {Labtoolstcl 44-481} -suppress
}

proc transaction_name {prefix} {
  global transaction_sequence
  incr transaction_sequence
  return [format "rv64_%s_%d" $prefix $transaction_sequence]
}

proc check_axi_response {axi property context} {
  set response [get_property $property $axi]
  if {$response ne "OKAY"} {
    error "$context returned AXI response $response"
  }
}

proc write_words {axi address words context} {
  set count [llength $words]
  if {$count < 1 || $count > 256} {
    error "$context has an invalid AXI write length: $count"
  }
  set transaction [transaction_name write]
  create_hw_axi_txn $transaction $axi -address [format %08x $address] \
    -data $words -len $count -type WRITE
  run_hw_axi [get_hw_axi_txns $transaction]
  check_axi_response $axi STATUS.BRESP $context
  delete_hw_axi_txn [get_hw_axi_txns $transaction]
}

proc read_word {axi address context} {
  set transaction [transaction_name read]
  create_hw_axi_txn $transaction $axi -address [format %08x $address] -len 1 -type READ
  run_hw_axi [get_hw_axi_txns $transaction]
  check_axi_response $axi STATUS.RRESP $context
  set report [report_hw_axi_txn [get_hw_axi_txns $transaction] -t x4 -w 4]
  delete_hw_axi_txn [get_hw_axi_txns $transaction]
  set values [regexp -all -inline -nocase {\m[0-9a-f]{8}\M} $report]
  if {[llength $values] == 0} {
    error "$context did not return a 32-bit read value: $report"
  }
  return [string tolower [lindex $values end]]
}

proc read_words {axi address count context} {
  if {$count < 1 || $count > 256} {
    error "$context has an invalid AXI read length: $count"
  }
  set transaction [transaction_name read_burst]
  create_hw_axi_txn $transaction $axi -address [format %08x $address] -len $count -type READ
  run_hw_axi [get_hw_axi_txns $transaction]
  check_axi_response $axi STATUS.RRESP $context
  set report [report_hw_axi_txn [get_hw_axi_txns $transaction] -t x4 -w 4]
  delete_hw_axi_txn [get_hw_axi_txns $transaction]
  set values [regexp -all -inline -nocase {\m[0-9a-f]{8}\M} $report]
  set result {}
  # The tabular report contains address/data pairs.  The leading concatenated
  # READ DATA field is longer than eight digits and is excluded by word bounds.
  for {set index 0} {$index + 1 < [llength $values]} {incr index 2} {
    lappend result [string tolower [lindex $values [expr {$index + 1}]]]
  }
  if {[llength $result] != $count} {
    error "$context returned [llength $result] words, expected $count: $report"
  }
  return $result
}

proc payload_words {payload offset count} {
  set words {}
  for {set index 0} {$index < $count} {incr index} {
    set byte_offset [expr {$offset + 4 * $index}]
    set bytes [string range $payload $byte_offset [expr {$byte_offset + 3}]]
    append bytes [string repeat "\x00" [expr {4 - [string length $bytes]}]]
    binary scan $bytes H8 little_endian_hex
    set word [string tolower [join [list \
      [string range $little_endian_hex 6 7] \
      [string range $little_endian_hex 4 5] \
      [string range $little_endian_hex 2 3] \
      [string range $little_endian_hex 0 1]] ""]]
    lappend words $word
  }
  return $words
}

proc payload_word {payload_handle word_index} {
  seek $payload_handle [expr {$word_index * 4}] start
  set bytes [read $payload_handle 4]
  return [lindex [payload_words $bytes 0 1] 0]
}

set payload_size [file size $payload_file]
if {$payload_size == 0} {
  error "payload file is empty: $payload_file"
}
if {$payload_size > $max_payload_bytes} {
  error "payload is too large for the loader-safe range: bytes=$payload_size limit=$max_payload_bytes"
}
set word_count [expr {($payload_size + 3) / 4}]

set manager_open 0
set server_connected 0
set target_open 0
set payload_handle [open $payload_file rb]
fconfigure $payload_handle -translation binary -encoding binary
try {
  open_hw_manager
  set manager_open 1
  connect_hw_server -allow_non_jtag
  set server_connected 1
  open_hw_target
  set target_open 1
  set devices [get_hw_devices xc7k480t*]
  if {[llength $devices] != 1} {
    error "expected exactly one xc7k480t JTAG device, found: $devices"
  }
  set device [lindex $devices 0]
  current_hw_device $device
  set_property PROBES.FILE $debug_probes $device
  refresh_hw_device -update_hw_probes true $device
  set axis [get_hw_axis -of_objects $device]
  if {[llength $axis] != 1} {
    error "expected exactly one JTAG AXI core; configure the loader bitstream and matching probes first, found: $axis"
  }
  set axi [lindex $axis 0]
  reset_hw_axi $axi
  set ilas [get_hw_ilas -of_objects $device]
  if {[llength $ilas] != 1} {
    error "expected exactly one ILA core; configure the loader bitstream and matching probes first, found: $ilas"
  }
  set ila [lindex $ilas 0]
  set scrub_status [read_word $axi $control_address "pre-scrub loader status"]
  scan $scrub_status %x scrub_status_value
  if {($scrub_status_value & 3) != 3} {error "DDR scrub requires calibrated DDR and CPU hold"}
  # ECC check bits are undefined after power-up, including pages Linux may
  # legally read before writing (e.g. XOR calibration buffers). Initialize the
  # entire advertised RAM before loading the real software image.
  source [file join [file dirname [info script]] rv64-ddr-scrub.tcl]
  rv64_scrub_ddr $axi $ila \
    $scrub_image \
    [file join [file dirname [info script]] .. build boot ddr-scrub-last.csv]

  foreach probe [get_hw_probes -of_objects $ila] {
    set width [get_property WIDTH $probe]
    set_property TRIGGER_COMPARE_VALUE [format "eq%d'b%s" $width [string repeat X $width]] $probe
  }
  set reset_probes [get_hw_probes -of_objects $ila -filter {NAME == "cpu_reset"}]
  if {[llength $reset_probes] != 1} {
    error "expected exactly one ILA cpu_reset probe, found: $reset_probes"
  }
  set reset_probe [lindex $reset_probes 0]
  reset_hw_ila $ila
  set_property CONTROL.DATA_DEPTH 4096 $ila
  set_property CONTROL.TRIGGER_CONDITION AND $ila
  if {$capture_mode in {first-trap first-s-trap first-s-illegal}} {
    set status_probes [get_hw_probes -of_objects $ila -filter {NAME == "debug_status"}]
    if {[llength $status_probes] != 1} {
      error "expected exactly one ILA debug_status probe, found: $status_probes"
    }
    set_property CONTROL.TRIGGER_POSITION 2048 $ila
    set_property TRIGGER_COMPARE_VALUE {eq6'bX1XXXX} [lindex $status_probes 0]
    if {$capture_mode in {first-s-trap first-s-illegal}} {
      set commit_probes [get_hw_probes -of_objects $ila -filter {NAME == "debug_commit_trace"}]
      if {[llength $commit_probes] != 1} {
        error "expected exactly one ILA debug_commit_trace probe, found: $commit_probes"
      }
      if {$capture_mode eq "first-s-illegal"} {
        set cause_bits [format %064llb 2]
        set commit_compare [format "eq226'b%s01%s%s" \
          [string repeat X 64] $cause_bits [string repeat X 96]]
      } else {
        set commit_compare [format "eq226'b%s01%s" \
          [string repeat X 64] [string repeat X 160]]
      }
      set_property TRIGGER_COMPARE_VALUE $commit_compare [lindex $commit_probes 0]
    }
  } elseif {$capture_mode eq "kernel-park"} {
    set commit_probes [get_hw_probes -of_objects $ila -filter {NAME == "debug_commit_trace"}]
    if {[llength $commit_probes] != 1} {
      error "expected exactly one ILA debug_commit_trace probe, found: $commit_probes"
    }
    set park_pc [format %064llb 0x80200110]
    set park_compare [format "eq226'b%s%s" [string repeat X 162] $park_pc]
    set_property CONTROL.TRIGGER_POSITION 3072 $ila
    set_property TRIGGER_COMPARE_VALUE $park_compare [lindex $commit_probes 0]
  } elseif {$capture_mode eq "panic"} {
    set commit_probes [get_hw_probes -of_objects $ila -filter {NAME == "debug_commit_trace"}]
    if {[llength $commit_probes] != 1} {
      error "expected exactly one ILA debug_commit_trace probe, found: $commit_probes"
    }
    # Capture the stable panic-loop branch.  The earlier panic prologue point
    # is not observed reliably by this implementation's commit trace, while
    # the loop branch is continuously committed and retains the preceding
    # call-path history in the ILA pre-trigger window.
    set panic_pc [format %064llb 0xffffffff80c99bb4]
    set panic_compare [format "eq226'b%s%s" [string repeat X 162] $panic_pc]
    set_property CONTROL.TRIGGER_POSITION 3072 $ila
    set_property TRIGGER_COMPARE_VALUE $panic_compare [lindex $commit_probes 0]
  } else {
    set_property CONTROL.TRIGGER_POSITION 0 $ila
    set_property TRIGGER_COMPARE_VALUE {eq1'b0} $reset_probe
  }
  run_hw_ila $ila

  set status_word [read_word $axi $control_address "loader status"]
  scan $status_word %x status_value
  if {($status_value & 0x3) != 0x3} {
    error [format "loader is not ready: status=0x%s (expected hold-reset and calibrated DDR3)" $status_word]
  }

  set diagnostic_words {13579bdf 2468ace0 0badf00d c001d00d}
  write_words $axi $diagnostic_address $diagnostic_words "DDR3 diagnostic write"
  for {set index 0} {$index < [llength $diagnostic_words]} {incr index} {
    set actual [read_word $axi [expr {$diagnostic_address + 4 * $index}] "DDR3 diagnostic read"]
    set expected [lindex $diagnostic_words $index]
    if {$actual ne $expected} {
      error [format "DDR3 diagnostic mismatch at 0x%08x: expected 0x%s got 0x%s" \
        [expr {$diagnostic_address + 4 * $index}] $expected $actual]
    }
  }
  puts [format "JTAG_DDR3_DIAGNOSTIC_PASS address=0x%08x" $diagnostic_address]

  # Initialize every ECC-covered word before reading any workspace data.
  # SRAM reconfiguration does not initialize DDR or its ECC check bits.
  set zero_words [lrepeat $maximum_words_per_transaction 00000000]
  set workspace_chunk_bytes [expr {4 * $maximum_words_per_transaction}]
  for {set offset 0} {$offset < $dtb_workspace_bytes} {incr offset $workspace_chunk_bytes} {
    write_words $axi [expr {$dtb_workspace_address + $offset}] $zero_words \
      "DTB workspace initialization"
  }
  for {set offset 0} {$offset < $dtb_workspace_bytes} {incr offset $workspace_chunk_bytes} {
    set address [expr {$dtb_workspace_address + $offset}]
    if {[read_words $axi $address $maximum_words_per_transaction \
           "DTB workspace verification"] ne $zero_words} {
      error [format "DTB workspace mismatch at 0x%08x" $address]
    }
  }
  puts [format "JTAG_DTB_WORKSPACE_INIT_PASS address=0x%08x bytes=%d" \
    $dtb_workspace_address $dtb_workspace_bytes]

  set word_index 0
  set queue_transactions {}
  set last_progress_bytes 0
  set payload_write_start_ms [clock milliseconds]
  seek $payload_handle 0 start
  while {$word_index < $word_count} {
    set words_in_transaction [expr {min($maximum_words_per_transaction, $word_count - $word_index)}]
    set byte_offset [expr {$word_index * 4}]
    set bytes_to_read [expr {min($words_in_transaction * 4, $payload_size - $byte_offset)}]
    set payload_chunk [read $payload_handle $bytes_to_read]
    if {[string length $payload_chunk] != $bytes_to_read} {
      error "short payload read at byte offset $byte_offset"
    }
    set words [payload_words $payload_chunk 0 $words_in_transaction]
    set transaction [transaction_name payload_write]
    create_hw_axi_txn $transaction $axi \
      -address [format %08x [expr {$ddr_base_address + 4 * $word_index}]] \
      -data $words -len $words_in_transaction -type WRITE
    lappend queue_transactions [get_hw_axi_txns $transaction]
    set word_index [expr {$word_index + $words_in_transaction}]
    if {[llength $queue_transactions] == $configured_write_queue_length || $word_index == $word_count} {
      if {[llength $queue_transactions] == 1} {
        # Synchronous execution is required here.  Vivado's -queue form may
        # return after admission rather than completion, which allowed the
        # following readback to race the DDR write and eventually saturated
        # the JTAG AXI queue during large payloads.
        run_hw_axi [lindex $queue_transactions 0]
      } else {
        run_hw_axi -queue {*}$queue_transactions
      }
      check_axi_response $axi STATUS.BRESP "payload write queue"
      foreach transaction $queue_transactions {
        delete_hw_axi_txn $transaction
      }
      set queue_transactions {}
      set chunk_address [expr {$ddr_base_address + $byte_offset}]
      set verified 0
      for {set attempt 1} {$attempt <= 3 && !$verified} {incr attempt} {
        set actual_words [read_words $axi $chunk_address $words_in_transaction \
          "payload chunk verify"]
        if {$actual_words eq $words} {
          set verified 1
        } elseif {$attempt < 3} {
          puts [format "JTAG_PAYLOAD_RETRY address=0x%08x attempt=%d" $chunk_address $attempt]
          write_words $axi $chunk_address $words "payload chunk retry"
        }
      }
      if {!$verified} {
        error [format "payload chunk mismatch after retries at 0x%08x" $chunk_address]
      }
      set written_bytes [expr {min($word_index * 4, $payload_size)}]
      if {$written_bytes == $payload_size ||
          $written_bytes - $last_progress_bytes >= $progress_interval_bytes} {
        puts [format "JTAG_PAYLOAD_WRITE_PROGRESS bytes=%d/%d" \
          $written_bytes $payload_size]
        set last_progress_bytes $written_bytes
      }
    }
  }
  set payload_write_elapsed_ms [expr {max(1, [clock milliseconds] - $payload_write_start_ms)}]
  set payload_write_bytes_per_second [expr {($payload_size * 1000) / $payload_write_elapsed_ms}]
  puts [format "JTAG_PAYLOAD_WRITE_RATE bytes=%d elapsed_ms=%d bytes_per_second=%d" \
    $payload_size $payload_write_elapsed_ms $payload_write_bytes_per_second]

  if {$word_count == 1} {
    set sample_indices {0}
  } else {
    set effective_sample_count [expr {max(2, $sample_count)}]
    set sample_indices {}
    for {set index 0} {$index < $effective_sample_count} {incr index} {
      lappend sample_indices [expr {(($word_count - 1) * $index) / ($effective_sample_count - 1)}]
    }
  }
  foreach sample_index [lsort -integer -unique $sample_indices] {
    set expected [payload_word $payload_handle $sample_index]
    set address [expr {$ddr_base_address + 4 * $sample_index}]
    set actual [read_word $axi $address "payload sample read"]
    if {$actual ne $expected} {
      error [format "payload mismatch at 0x%08x: expected 0x%s got 0x%s" $address $expected $actual]
    }
  }
  puts [format "JTAG_PAYLOAD_VERIFY_PASS samples=%d bytes=%d" \
    [llength [lsort -integer -unique $sample_indices]] $payload_size]

  if {$capture_mode eq "hold"} {
    puts [format "JTAG_LINUX_LOAD_HOLD_PASS payload=%s bytes=%d" $payload_file $payload_size]
    return
  }

  write_words $axi $control_address {00000000} "CPU reset release"
  # Do not issue any JTAG AXI transaction after releasing the CPU.  The loader
  # interconnect hands DDR ownership to the CPU at this point, so a status read
  # can block before Vivado reaches the ILA upload.
  set cpu_capture_file [file join [file dirname $payload_file] \
    [expr {$capture_mode eq "kernel-park" ? "rv64-linux-kernel-park.csv" :
           ($capture_mode eq "panic" ? "rv64-linux-panic.csv" :
           ($capture_mode eq "first-s-illegal" ? "rv64-linux-first-s-illegal.csv" :
           ($capture_mode eq "first-s-trap" ? "rv64-linux-first-s-trap.csv" :
           ($capture_mode eq "first-trap" ? "rv64-linux-first-trap.csv" :
            "rv64-linux-cpu-startup.csv"))))}]]
  file delete -force $cpu_capture_file
  # Vivado interprets this timeout in minutes.  Panic capture is expected to
  # trigger quickly once the kernel reaches the watchdog path; keep a bounded
  # one-minute diagnostic wait so a missed trigger cannot strand the session.
  wait_on_hw_ila -timeout [expr {$capture_mode eq "startup" ? 1 :
                                  ($capture_mode eq "panic" ? 1 : 60)}] $ila
  set cpu_capture [upload_hw_ila_data $ila]
  if {[llength $cpu_capture] == 0} {
    error "CPU startup ILA did not produce a triggered capture"
  }
  write_hw_ila_data -force -csv_file $cpu_capture_file $cpu_capture
  set capture_handle [open $cpu_capture_file r]
  set capture_lines [split [read $capture_handle] "\n"]
  close $capture_handle
  set nonempty_capture_lines 0
  foreach capture_line $capture_lines {
    if {[string trim $capture_line] ne ""} {
      incr nonempty_capture_lines
    }
  }
  if {$nonempty_capture_lines <= 2} {
    error "CPU startup ILA capture contains no samples: $cpu_capture_file"
  }
  puts "JTAG_CPU_ILA_CAPTURE $cpu_capture_file"
  puts [format "JTAG_LINUX_LOAD_PASS payload=%s bytes=%d" $payload_file $payload_size]
} finally {
  close $payload_handle
  if {$target_open} {
    close_hw_target
  }
  if {$server_connected} {
    disconnect_hw_server
  }
  if {$manager_open} {
    close_hw_manager
  }
}
