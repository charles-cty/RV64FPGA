if {$argc != 1} {
  error "usage: create-rv64-jtag-axi-ip.tcl <output-directory>"
}

set output_directory [file normalize [lindex $argv 0]]
set part_name xc7k480tffg1156-2
file mkdir $output_directory

create_project -in_memory rv64_jtag_axi_ip -part $part_name
set xci_file [file join $output_directory rv64_jtag_axi rv64_jtag_axi.xci]
if {[file exists $xci_file]} {
  read_ip $xci_file
} else {
  create_ip -name jtag_axi -vendor xilinx.com -library ip -version 1.2 \
    -module_name rv64_jtag_axi -dir $output_directory
}
set_property -dict [list \
  CONFIG.WR_TXN_QUEUE_LENGTH {16} \
  CONFIG.RD_TXN_QUEUE_LENGTH {16}] [get_ips rv64_jtag_axi]
generate_target all [get_ips rv64_jtag_axi]
puts "RV64_JTAG_AXI_IP_READY xci=[get_property IP_FILE [get_ips rv64_jtag_axi]]"
close_project
