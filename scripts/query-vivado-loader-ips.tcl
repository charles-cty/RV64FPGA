create_project -in_memory loader_ip_query -part xc7k480tffg1156-2

foreach pattern {
  xilinx.com:ip:jtag_axi:*
  xilinx.com:ip:smartconnect:*
  xilinx.com:ip:axi_interconnect:*
  xilinx.com:ip:ila:*
} {
  set matches [lsort [get_ipdefs -all $pattern]]
  if {[llength $matches] == 0} {
    puts "IP_MISSING pattern=$pattern"
  } else {
    foreach match $matches {
      puts "IP_AVAILABLE pattern=$pattern definition=$match"
    }
  }
}

puts "LOADER_IP_QUERY_PASS"
close_project
