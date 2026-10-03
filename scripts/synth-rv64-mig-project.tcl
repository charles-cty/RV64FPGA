if {$argc < 4 || $argc > 5} {
  error "usage: synth-rv64-mig-project.tcl <source-root> <project-directory> <report-directory> <boot-rom-image> ?top?"
}

set source_root [file normalize [lindex $argv 0]]
set project_directory [file normalize [lindex $argv 1]]
set report_directory [file normalize [lindex $argv 2]]
set boot_rom_image [file normalize [lindex $argv 3]]
set top_name rv64_mig_soc_top
if {$argc == 5} {
  set top_name [lindex $argv 4]
}
set part_name xc7k480tffg1156-2
set project_name rv64_mig_soc

if {![file isdirectory $source_root]} {
  error "source root does not exist: $source_root"
}

file mkdir $report_directory
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
  [file join $source_root rtl rv64_ddr3_diag_controller.sv] \
  [file join $source_root rtl rv64_uart.sv] \
  [file join $source_root rtl rv64_core.sv] \
  [file join $source_root rtl rv64_bram_soc.sv] \
  [file join $source_root rtl rv64_mig_soc_top.sv] \
  [file join $source_root rtl rv64_mig_ddr3_diag_top.sv]
]

foreach rtl_file $rtl_files {
  if {![file exists $rtl_file]} {
    error "required RTL file does not exist: $rtl_file"
  }
}
add_files -norecurse $rtl_files
if {$top_name eq "rv64_mig_soc_top"} {
  if {![file exists $boot_rom_image]} {
    error "boot ROM image does not exist: $boot_rom_image"
  }
  add_files -norecurse $boot_rom_image
  set_property file_type {Memory File} [get_files $boot_rom_image]
}

set xdc_file [file join $source_root constraints rv64_mig_soc_top.xdc]
if {![file exists $xdc_file]} {
  error "top-level constraints do not exist: $xdc_file"
}
add_files -fileset constrs_1 -norecurse $xdc_file

set xci_file [file join $source_root ip rv64_mig_ch0 rv64_mig_ch0 rv64_mig_ch0.xci]
if {![file exists $xci_file]} {
  error "generated MIG XCI does not exist: $xci_file"
}
set mig_output_directory [file dirname $xci_file]
set mig_synth_checkpoint [file join $mig_output_directory rv64_mig_ch0.dcp]
if {[file exists $mig_synth_checkpoint]} {
  file delete -force $mig_synth_checkpoint
}
read_ip $xci_file
generate_target all [get_ips]

set jtag_xci_file [file join $source_root ip rv64_jtag_axi rv64_jtag_axi rv64_jtag_axi.xci]
if {![file exists $jtag_xci_file]} {
  error "generated JTAG AXI XCI does not exist: $jtag_xci_file"
}
read_ip $jtag_xci_file
generate_target all [get_ips rv64_jtag_axi]

set debug_ila_xci_file [file join $source_root ip rv64_debug_ila rv64_debug_ila rv64_debug_ila.xci]
if {![file exists $debug_ila_xci_file]} {
  error "generated debug ILA XCI does not exist: $debug_ila_xci_file"
}
read_ip $debug_ila_xci_file
generate_target all [get_ips rv64_debug_ila]

set_property top $top_name [current_fileset]
if {$top_name eq "rv64_mig_soc_top"} {
  set_property generic [format {BOOT_ROM_INIT_FILE="%s"} $boot_rom_image] [current_fileset]
}
update_compile_order -fileset sources_1
report_compile_order -fileset sources_1 -file [file join $report_directory compile_order.rpt]

launch_runs synth_1 -jobs 8
wait_on_run synth_1

set synth_run [get_runs synth_1]
set synth_status [get_property STATUS $synth_run]
if {$synth_status ne "synth_design Complete!"} {
  error "synthesis did not complete successfully: $synth_status"
}

open_run synth_1
report_utilization -hierarchical -file [file join $report_directory utilization_hierarchical.rpt]
report_timing_summary -max_paths 10 -file [file join $report_directory timing_summary.rpt]
report_clock_interaction -file [file join $report_directory clock_interaction.rpt]
check_timing -verbose -file [file join $report_directory check_timing.rpt]
report_drc -file [file join $report_directory drc_synth.rpt]
write_checkpoint -force [file join $report_directory rv64_mig_soc_synth.dcp]

puts "RV64_MIG_SYNTH_PASS part=$part_name top=$top_name status=$synth_status reports=$report_directory"
close_project
