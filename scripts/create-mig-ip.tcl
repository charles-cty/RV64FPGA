if {$argc != 3} {
    error "usage: create-mig-ip.tcl <module-name> <mig-config.prj> <output-directory>"
}

set module_name [lindex $argv 0]
set config_file [file normalize [lindex $argv 1]]
set output_directory [file normalize [lindex $argv 2]]

if {![file exists $config_file]} {
    error "MIG configuration file does not exist: $config_file"
}

file mkdir $output_directory
create_project -in_memory -part xc7k480tffg1156-2 $module_name
create_ip \
    -name mig_7series \
    -vendor xilinx.com \
    -library ip \
    -version 4.2 \
    -module_name $module_name \
    -dir $output_directory

set mig_ip [get_ips $module_name]
set_property -dict [list \
    CONFIG.XML_INPUT_FILE $config_file \
    CONFIG.RESET_BOARD_INTERFACE {Custom} \
    CONFIG.MIG_DONT_TOUCH_PARAM {Custom} \
    CONFIG.BOARD_MIG_PARAM {Custom} \
] $mig_ip

generate_target all $mig_ip
export_ip_user_files -of_objects $mig_ip -no_script -force
report_ip_status -name ${module_name}_ip_status -of_objects $mig_ip
close_project
