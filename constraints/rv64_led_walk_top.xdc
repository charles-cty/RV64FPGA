set_property PACKAGE_PIN AA28 [get_ports clk_50]
set_property IOSTANDARD LVCMOS33 [get_ports clk_50]
create_clock -name clk_50 -period 20.000 [get_ports clk_50]

set_property PACKAGE_PIN P30 [get_ports {led[0]}]
set_property PACKAGE_PIN M30 [get_ports {led[1]}]
set_property PACKAGE_PIN N30 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[*]}]
set_property DRIVE 8 [get_ports {led[*]}]
set_property SLEW SLOW [get_ports {led[*]}]
set_false_path -to [get_ports {led[*]}]

set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
