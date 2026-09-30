if {$argc != 1} {
  error "usage: create-rv64-debug-ila-ip.tcl <output-directory>"
}

set output_directory [file normalize [lindex $argv 0]]
set part_name xc7k480tffg1156-2
file mkdir $output_directory

create_project -in_memory rv64_debug_ila_ip -part $part_name
set xci_file [file join $output_directory rv64_debug_ila rv64_debug_ila.xci]
if {[file exists $xci_file]} {
  read_ip $xci_file
} else {
  create_ip -name ila -vendor xilinx.com -library ip -version 6.2 \
    -module_name rv64_debug_ila -dir $output_directory
}
set_property -dict [list \
  CONFIG.C_DATA_DEPTH {4096} \
  CONFIG.C_NUM_OF_PROBES {5} \
  CONFIG.C_PROBE0_WIDTH {1} \
  CONFIG.C_PROBE1_WIDTH {1} \
  CONFIG.C_PROBE2_WIDTH {6} \
  CONFIG.C_PROBE3_WIDTH {226} \
  CONFIG.C_PROBE4_WIDTH {130} \
] [get_ips rv64_debug_ila]
generate_target all [get_ips rv64_debug_ila]
puts "RV64_DEBUG_ILA_IP_READY xci=[get_property IP_FILE [get_ips rv64_debug_ila]]"
close_project
