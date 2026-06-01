# HuaPro P3 standalone SD dual-pin dual-protocol probe constraints.

set_property PACKAGE_PIN CE6 [get_ports diff_sysclock_clk_p]
set_property PACKAGE_PIN CF6 [get_ports diff_sysclock_clk_n]
set_property IOSTANDARD LVDS15 [get_ports diff_sysclock_clk_p]
set_property IOSTANDARD LVDS15 [get_ports diff_sysclock_clk_n]

set_property PACKAGE_PIN A6 [get_ports reset]
set_property IOSTANDARD LVCMOS15 [get_ports reset]

# Shared card-detect pin. Both candidate maps agree on DC61.
set_property PACKAGE_PIN DC61 [get_ports sd_cd]
set_property IOSTANDARD LVCMOS15 [get_ports sd_cd]

# Reference project / current OpenPiton SD pin map.
set_property PACKAGE_PIN CV57 [get_ports sd_ref_clk]
set_property PACKAGE_PIN DB57 [get_ports sd_ref_cmd]
set_property PACKAGE_PIN DC56 [get_ports {sd_ref_dat[0]}]
set_property PACKAGE_PIN DC55 [get_ports {sd_ref_dat[1]}]
set_property PACKAGE_PIN CY56 [get_ports {sd_ref_dat[2]}]
set_property PACKAGE_PIN CY55 [get_ports {sd_ref_dat[3]}]
set_property PACKAGE_PIN CW57 [get_ports sd_ref_vsd_en]
set_property PACKAGE_PIN DB56 [get_ports sd_ref_sel]
set_property PACKAGE_PIN DA55 [get_ports sd_ref_resetn]

set_property IOSTANDARD LVCMOS15 [get_ports sd_ref_clk]
set_property IOSTANDARD LVCMOS15 [get_ports sd_ref_cmd]
set_property IOSTANDARD LVCMOS15 [get_ports {sd_ref_dat[*]}]
set_property IOSTANDARD LVCMOS15 [get_ports sd_ref_vsd_en]
set_property IOSTANDARD LVCMOS15 [get_ports sd_ref_sel]
set_property IOSTANDARD LVCMOS15 [get_ports sd_ref_resetn]
set_property PULLTYPE PULLUP [get_ports sd_ref_cmd]
set_property PULLTYPE PULLUP [get_ports {sd_ref_dat[*]}]

# p3_io.md PHC3 / Bank 705 native SD pin map.
set_property PACKAGE_PIN CW60 [get_ports sd_phc3_clk]
set_property PACKAGE_PIN DB61 [get_ports sd_phc3_cmd]
set_property PACKAGE_PIN DC60 [get_ports {sd_phc3_dat[0]}]
set_property PACKAGE_PIN DC59 [get_ports {sd_phc3_dat[1]}]
set_property PACKAGE_PIN CY58 [get_ports {sd_phc3_dat[2]}]
set_property PACKAGE_PIN DA58 [get_ports {sd_phc3_dat[3]}]
set_property PACKAGE_PIN CY60 [get_ports sd_phc3_vsd_en]
set_property PACKAGE_PIN DA59 [get_ports sd_phc3_sel]
set_property PACKAGE_PIN DA60 [get_ports sd_phc3_resetn]

set_property IOSTANDARD LVCMOS15 [get_ports sd_phc3_clk]
set_property IOSTANDARD LVCMOS15 [get_ports sd_phc3_cmd]
set_property IOSTANDARD LVCMOS15 [get_ports {sd_phc3_dat[*]}]
set_property IOSTANDARD LVCMOS15 [get_ports sd_phc3_vsd_en]
set_property IOSTANDARD LVCMOS15 [get_ports sd_phc3_sel]
set_property IOSTANDARD LVCMOS15 [get_ports sd_phc3_resetn]
set_property PULLTYPE PULLUP [get_ports sd_phc3_cmd]
set_property PULLTYPE PULLUP [get_ports {sd_phc3_dat[*]}]
