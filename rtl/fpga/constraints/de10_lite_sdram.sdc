# First implementation: 50 MHz single domain, SDRAM output clock inverted.
create_clock -name clk50 -period 20.000 [get_ports MAX10_CLK1_50]
create_generated_clock -name sdram_clk -source [get_ports MAX10_CLK1_50] -invert [get_ports DRAM_CLK]
derive_clock_uncertainty
# Provisional board trace budget, not post-layout/board calibration evidence.
# Setup/hold and tAC plus trace margin must be checked against fitted I/O paths.
set_output_delay -clock sdram_clk -max 2.0 [get_ports {DRAM_ADDR[*] DRAM_BA[*] DRAM_CAS_N DRAM_RAS_N DRAM_WE_N DRAM_CS_N DRAM_CKE DRAM_LDQM DRAM_UDQM DRAM_DQ[*]}]
set_output_delay -clock sdram_clk -min -1.0 [get_ports {DRAM_ADDR[*] DRAM_BA[*] DRAM_CAS_N DRAM_RAS_N DRAM_WE_N DRAM_CS_N DRAM_CKE DRAM_LDQM DRAM_UDQM DRAM_DQ[*]}]
set_input_delay -clock sdram_clk -max 7.5 [get_ports {DRAM_DQ[*]}]
set_input_delay -clock sdram_clk -min 2.5 [get_ports {DRAM_DQ[*]}]
set_false_path -from [get_ports {KEY[*]}]
set_false_path -from [get_ports UART_RX] -to [get_registers {*u_uart_rx*rx_meta *u_boot_uart_rx*rx_meta}]
set_false_path -to [get_ports {UART_TX LEDR[*]}]
