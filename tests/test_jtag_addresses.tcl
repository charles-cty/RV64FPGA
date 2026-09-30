# Run with tclsh or Vivado -mode batch -source (Windows Tcl is essential).
source [file join [file dirname [info script]] .. scripts rv64-jtag-addresses.tcl]
proc expect {actual expected} {
  if {$actual ne $expected} { error "expected $expected, got $actual" }
}
expect [rv64_diag::words_value {fffedb08 00000000}] 4294892296
set offset [rv64_diag::words_value {9e3b0000 ffffffd6}]
expect [rv64_diag::hex64 $offset] ffffffd69e3b0000
set live [expr {(0xffffffff80c3cbc0 + $offset) & 0xffffffffffffffff}]
expect [rv64_diag::hex64 $live] ffffffd61efecbc0
expect [format %08x [rv64_diag::linear_pa $live]] 9efecbc0
expect [format %08x [rv64_diag::kernel_pa 0xffffffff81409940]] 81609940
expect [rv64_diag::hex64 [rv64_diag::words_value {ffffffff ffffffff}]] ffffffffffffffff
expect [catch {rv64_diag::linear_pa 0x1efecbc0}] 1
expect [catch {rv64_diag::words_value {bad}}] 1
puts "RV64_JTAG_ADDRESSES_PASS"
