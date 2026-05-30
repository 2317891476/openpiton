# HuaPro P3 standalone AXI UART16550 interaction-test constraints.

set_property PACKAGE_PIN CE6 [get_ports diff_sysclock_clk_p]
set_property PACKAGE_PIN CF6 [get_ports diff_sysclock_clk_n]
set_property IOSTANDARD LVDS15 [get_ports diff_sysclock_clk_p]
set_property IOSTANDARD LVDS15 [get_ports diff_sysclock_clk_n]

set_property PACKAGE_PIN A6 [get_ports reset]
set_property IOSTANDARD LVCMOS15 [get_ports reset]

set_property PACKAGE_PIN CW58 [get_ports uart_tx]
set_property PACKAGE_PIN CW59 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS15 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS15 [get_ports uart_rx]
