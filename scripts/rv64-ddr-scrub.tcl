# Shared by the Linux loader. Requires write_words/read_words/payload_words.
# The tiny M-mode program writes all DDR except its initialized 64 KiB image.
proc rv64_scrub_ddr {axi ila image capture_file} {
  if {![file isfile $image] || [file size $image] != 136} {
    error "missing/invalid DDR scrub image; run scripts/build-ddr-scrub.sh: $image"
  }
  set f [open $image rb]
  set bytes [read $f]
  close $f
  set zeros [lrepeat 256 00000000]
  set first [payload_words $bytes 0 256]
  for {set off 0} {$off < 65536} {incr off 1024} {
    set words [expr {$off == 0 ? $first : $zeros}]
    write_words $axi [expr {0x80000000+$off}] $words "scrub image initialization"
    if {[read_words $axi [expr {0x80000000+$off}] 256 "scrub image verify"] ne $words} {
      error "DDR scrub image mismatch at offset $off"
    }
  }
  reset_hw_ila $ila
  foreach probe [get_hw_probes -of_objects $ila] {
    set width [get_property WIDTH $probe]
    set_property TRIGGER_COMPARE_VALUE [format "eq%d'b%s" $width [string repeat X $width]] $probe
  }
  set trace [lindex [get_hw_probes -of_objects $ila -filter {NAME == "debug_commit_trace"}] 0]
  set status [lindex [get_hw_probes -of_objects $ila -filter {NAME == "debug_status"}] 0]
  set_property CONTROL.DATA_DEPTH 4096 $ila
  set_property CONTROL.TRIGGER_POSITION 2048 $ila
  set_property CONTROL.TRIGGER_CONDITION AND $ila
  # M-mode, committed instruction, no trap, exact completion PC.
  set_property TRIGGER_COMPARE_VALUE [format "eq226'b%s11%s%s" [string repeat X 64] [string repeat X 96] [format %064llb 0x80000080]] $trace
  set_property TRIGGER_COMPARE_VALUE {eq6'bX01XXX} $status
  run_hw_ila $ila
  puts "JTAG_DDR_SCRUB_START bytes=536870912"
  flush stdout
  try {
    write_words $axi 0x7fffff00 {00000000} "run DDR scrub"
    wait_on_hw_ila -timeout 10 $ila
    set data [upload_hw_ila_data $ila]
    if {[llength $data] == 0} {error "DDR scrub completion was not captured"}
    write_hw_ila_data -force -csv_file $capture_file $data
  } finally {
    # Never return to a caller with the temporary scrub program running.
    write_words $axi 0x7fffff00 {00000001} "hold after DDR scrub"
    after 200
  }
  # Test endpoints, former fault buffers, and distant banks after completion.
  foreach address {0x80010000 0x81a80000 0x81a83000 0x88000000 0x90000000 0x98000000 0x9fffffc0} {
    if {[read_words $axi $address 16 "scrub sample"] ne [lrepeat 16 00000000]} {
      error [format "DDR scrub sample mismatch at %08x" $address]
    }
  }
  puts "JTAG_DDR_SCRUB_PASS bytes=536870912 CPU_HELD"
  flush stdout
}
