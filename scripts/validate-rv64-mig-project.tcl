if {$argc != 2} {
  error "usage: validate-rv64-mig-project.tcl <source-root> <project-directory>"
}

set source_root [file normalize [lindex $argv 0]]
set project_directory [file normalize [lindex $argv 1]]
set part_name xc7k480tffg1156-2
set project_name rv64_mig_soc

if {![file isdirectory $source_root]} {
  error "source root does not exist: $source_root"
}

create_project $project_name $project_directory -part $part_name -force

set rtl_files [list \
  [file join $source_root rtl riscv_pkg.sv] \
  [file join $source_root rtl rv64_alu.sv] \
  [file join $source_root rtl rv64_decoder.sv] \
  [file join $source_root rtl rv64_imm_gen.sv] \
  [file join $source_root rtl rv64_regfile.sv] \
  [file join $source_root rtl rv64_csr.sv] \
  [file join $source_root rtl rv64_atomic_unit.sv] \
  [file join $source_root rtl rv64_divider.sv] \
  [file join $source_root rtl rv64_clint.sv] \
  [file join $source_root rtl rv64_plic.sv] \
  [file join $source_root rtl rv64_mmu.sv] \
  [file join $source_root rtl rv64_cache.sv] \
  [file join $source_root rtl rv64_ddr3_model.sv] \
  [file join $source_root rtl rv64_ddr3_arbiter.sv] \
  [file join $source_root rtl rv64_async_memory_bridge.sv] \
  [file join $source_root rtl rv64_ddr3_axi_adapter.sv] \
  [file join $source_root rtl rv64_ddr3_mig_path.sv] \
  [file join $source_root rtl rv64_startup_reset.sv] \
  [file join $source_root rtl rv64_jtag_console.sv] \
  [file join $source_root rtl rv64_jtag_axi_loader.sv] \
  [file join $source_root rtl rv64_uart.sv] \
  [file join $source_root rtl rv64_core.sv] \
  [file join $source_root rtl rv64_bram_soc.sv] \
  [file join $source_root rtl rv64_mig_soc_top.sv]
]

foreach rtl_file $rtl_files {
  if {![file exists $rtl_file]} {
    error "required RTL file does not exist: $rtl_file"
  }
}
add_files -norecurse $rtl_files

set xdc_file [file join $source_root constraints rv64_mig_soc_top.xdc]
if {![file exists $xdc_file]} {
  error "top-level constraints do not exist: $xdc_file"
}
add_files -fileset constrs_1 -norecurse $xdc_file

set xci_file [file join $source_root ip rv64_mig_ch0 rv64_mig_ch0 rv64_mig_ch0.xci]
if {![file exists $xci_file]} {
  error "generated MIG XCI does not exist: $xci_file"
}
read_ip $xci_file

set jtag_xci_file [file join $source_root ip rv64_jtag_axi rv64_jtag_axi rv64_jtag_axi.xci]
if {![file exists $jtag_xci_file]} {
  error "generated JTAG AXI XCI does not exist: $jtag_xci_file"
}
read_ip $jtag_xci_file

set debug_ila_xci_file [file join $source_root ip rv64_debug_ila rv64_debug_ila rv64_debug_ila.xci]
if {![file exists $debug_ila_xci_file]} {
  error "generated debug ILA XCI does not exist: $debug_ila_xci_file"
}
read_ip $debug_ila_xci_file

set_property top rv64_mig_soc_top [current_fileset]
update_compile_order -fileset sources_1
set top_file [file join $source_root rtl rv64_mig_soc_top.sv]
if {[get_property top [current_fileset] ] ne "rv64_mig_soc_top"} {
  error "unexpected project top"
}
if {[llength [get_files -quiet $top_file]] == 0} {
  error "top-level RTL file is not in the project"
}
report_compile_order -fileset sources_1

set source_count [llength [get_files -of_objects [get_filesets sources_1]]]
set constraint_count [llength [get_files -of_objects [get_filesets constrs_1]]]
set ip_count [llength [get_ips]]
puts "RV64_MIG_PROJECT_VALID part=$part_name top=rv64_mig_soc_top sources=$source_count constraints=$constraint_count ips=$ip_count"
puts "RV64_MIG_PROJECT_NO_SYNTHESIS"
close_project
