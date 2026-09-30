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

proc collect_verilog_files {directory} {
    set files {}
    foreach entry [glob -nocomplain -directory $directory *] {
        if {[file isdirectory $entry]} {
            lappend files {*}[collect_verilog_files $entry]
        } elseif {[string match *.v $entry]} {
            lappend files $entry
        }
    }
    return $files
}

foreach generated_file [collect_verilog_files $output_directory] {
    set input [open $generated_file r]
    fconfigure $input -translation binary
    set contents [read $input]
    close $input
    set updated [string map {
        {parameter DIFF_TERM_SYSCLK = "TRUE"} {parameter DIFF_TERM_SYSCLK = "FALSE"}
        {parameter DIFF_TERM_SYSCLK      = "TRUE"} {parameter DIFF_TERM_SYSCLK      = "FALSE"}
    } $contents]
    if {$updated ne $contents} {
        set output [open $generated_file w]
        fconfigure $output -translation binary
        puts -nonewline $output $updated
        close $output
    }
}
close_project
