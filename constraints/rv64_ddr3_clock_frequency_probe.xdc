set_property PACKAGE_PIN AA28 [get_ports clk_50]
set_property IOSTANDARD LVCMOS33 [get_ports clk_50]
create_clock -name clk_50 -period 20.000 [get_ports clk_50]

set_property PACKAGE_PIN R28 [get_ports reset_n]
set_property IOSTANDARD LVCMOS18 [get_ports reset_n]

set_property PACKAGE_PIN P30 [get_ports {led[0]}]
set_property PACKAGE_PIN M30 [get_ports {led[1]}]
set_property PACKAGE_PIN N30 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[*]}]

set_property PACKAGE_PIN AH27 [get_ports sys_clk_p]
set_property PACKAGE_PIN AH28 [get_ports sys_clk_n]
set_property IOSTANDARD DIFF_SSTL15 [get_ports {sys_clk_p sys_clk_n}]
set_property DIFF_TERM FALSE [get_ports {sys_clk_p sys_clk_n}]
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 12 [current_design]
