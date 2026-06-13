# HuaPro P3 (Versal VP1902) Pin Constraints
# Based on reference project shell.xdc (huaprop3onecore)
# PHC3 daughter card on Bank 705, all LVCMOS15
#
# XPPHC logical pin → FPGA PACKAGE_PIN mapping from reference XDC:
#   A0=CV57  A1=CW57  A2=DB57  A3=DC61(p3_io.md)
#   A4=DC56  A5=DC55  A6=CY56  A7=CY55
#   A10=DA55 A11=DB56
#   B2=CW59  B3=CW58

# =============================================================================
# System Clock -- 100 MHz LVDS15
# =============================================================================
set_property PACKAGE_PIN CE6 [get_ports diff_sysclock_clk_p]
set_property PACKAGE_PIN CF6 [get_ports diff_sysclock_clk_n]
set_property IOSTANDARD LVDS15 [get_ports diff_sysclock_clk_p]
set_property IOSTANDARD LVDS15 [get_ports diff_sysclock_clk_n]

create_clock -period 10.000 -name sys_clk [get_ports diff_sysclock_clk_p]

# =============================================================================
# Reset -- Active HIGH (A6, LVCMOS15)
# =============================================================================
set_property PACKAGE_PIN A6 [get_ports reset]
set_property IOSTANDARD LVCMOS15 [get_ports reset]

# =============================================================================
# UART -- FT232HQ on PHC3 daughter card (XPPHC B2/B3)
# =============================================================================
set_property PACKAGE_PIN CW58 [get_ports uart_tx]
set_property PACKAGE_PIN CW59 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS15 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS15 [get_ports uart_rx]

# =============================================================================
# SD Card -- PHC3 daughter card
# Pin assignments from reference project shell.xdc (proven working).
# The OpenPiton native SD controller leaves CMD/DAT high-Z between transfers,
# so enable weak pull-ups on the idle command/data lines used during init.
# =============================================================================
# SD_CLK (XPPHC A0)
set_property PACKAGE_PIN CV57 [get_ports sd_clk_out]
set_property IOSTANDARD LVCMOS15 [get_ports sd_clk_out]

# SD_CMD (XPPHC A2) -- bidirectional in OpenPiton (MOSI + response)
set_property PACKAGE_PIN DB57 [get_ports sd_cmd]
set_property IOSTANDARD LVCMOS15 [get_ports sd_cmd]
set_property PULLTYPE PULLUP [get_ports sd_cmd]

# SD_DAT[0] (XPPHC A4) -- MISO in SPI mode
set_property PACKAGE_PIN DC56 [get_ports {sd_dat[0]}]
set_property IOSTANDARD LVCMOS15 [get_ports {sd_dat[0]}]
set_property PULLTYPE PULLUP [get_ports {sd_dat[0]}]

# SD_DAT[1] (XPPHC A5)
set_property PACKAGE_PIN DC55 [get_ports {sd_dat[1]}]
set_property IOSTANDARD LVCMOS15 [get_ports {sd_dat[1]}]
set_property PULLTYPE PULLUP [get_ports {sd_dat[1]}]

# SD_DAT[2] (XPPHC A6)
set_property PACKAGE_PIN CY56 [get_ports {sd_dat[2]}]
set_property IOSTANDARD LVCMOS15 [get_ports {sd_dat[2]}]
set_property PULLTYPE PULLUP [get_ports {sd_dat[2]}]

# SD_DAT[3] (XPPHC A7) -- CS in SPI mode
set_property PACKAGE_PIN CY55 [get_ports {sd_dat[3]}]
set_property IOSTANDARD LVCMOS15 [get_ports {sd_dat[3]}]
set_property PULLTYPE PULLUP [get_ports {sd_dat[3]}]

# SD Card Detect (XPPHC A3) -- active-low, PHC3/Bank 705 from p3_io.md
set_property PACKAGE_PIN DC61 [get_ports sd_cd]
set_property IOSTANDARD LVCMOS15 [get_ports sd_cd]

# =============================================================================
# SD Control Signals -- PHC3 daughter card power/mode control
# =============================================================================
# VSD_EN: enable SD card power (XPPHC A1)
set_property PACKAGE_PIN CW57 [get_ports sd_vsd_en]
set_property IOSTANDARD LVCMOS15 [get_ports sd_vsd_en]

# SD_SEL: voltage select, 0=3.3V (XPPHC A11)
set_property PACKAGE_PIN DB56 [get_ports sd_sel]
set_property IOSTANDARD LVCMOS15 [get_ports sd_sel]

# SD_RESET#: SD card reset, active-low (XPPHC A10)
set_property PACKAGE_PIN DA55 [get_ports sd_resetn]
set_property IOSTANDARD LVCMOS15 [get_ports sd_resetn]

# =============================================================================
# LEDs -- PHC3 daughter card
# =============================================================================
set_property PACKAGE_PIN CF60 [get_ports {leds[0]}]
set_property PACKAGE_PIN CF59 [get_ports {leds[1]}]
set_property IOSTANDARD LVCMOS15 [get_ports {leds[0]}]
set_property IOSTANDARD LVCMOS15 [get_ports {leds[1]}]

# =============================================================================
# DDR4 Memory Reference Clock -- 100 MHz LVDS15 (separate from system clock)
# =============================================================================
set_property PACKAGE_PIN CP83 [get_ports diff_memclock_clk_p]
set_property PACKAGE_PIN CP82 [get_ports diff_memclock_clk_n]
set_property IOSTANDARD LVDS15 [get_ports diff_memclock_clk_p]
set_property IOSTANDARD LVDS15 [get_ports diff_memclock_clk_n]

# =============================================================================
# DDR4 SODIMM -- 72-bit (64 data + 8 ECC), dual-rank
# DDRMC PHY handles IO standards internally; top-level ports must have correct
# directions (output for addr/ctrl, inout for data, input for alert) to avoid
# SSTL12/POD12 bank conflicts.
# =============================================================================

# Address [16:0]
set_property PACKAGE_PIN CV77 [get_ports {ddr4_rtl_0_adr[0]}]
set_property PACKAGE_PIN CW74 [get_ports {ddr4_rtl_0_adr[1]}]
set_property PACKAGE_PIN DC76 [get_ports {ddr4_rtl_0_adr[2]}]
set_property PACKAGE_PIN CM76 [get_ports {ddr4_rtl_0_adr[3]}]
set_property PACKAGE_PIN CL76 [get_ports {ddr4_rtl_0_adr[4]}]
set_property PACKAGE_PIN CR77 [get_ports {ddr4_rtl_0_adr[5]}]
set_property PACKAGE_PIN CR76 [get_ports {ddr4_rtl_0_adr[6]}]
set_property PACKAGE_PIN CV76 [get_ports {ddr4_rtl_0_adr[7]}]
set_property PACKAGE_PIN DC77 [get_ports {ddr4_rtl_0_adr[8]}]
set_property PACKAGE_PIN CW75 [get_ports {ddr4_rtl_0_adr[9]}]
set_property PACKAGE_PIN CU76 [get_ports {ddr4_rtl_0_adr[10]}]
set_property PACKAGE_PIN CM78 [get_ports {ddr4_rtl_0_adr[11]}]
set_property PACKAGE_PIN CT75 [get_ports {ddr4_rtl_0_adr[12]}]
set_property PACKAGE_PIN DA76 [get_ports {ddr4_rtl_0_adr[13]}]
set_property PACKAGE_PIN CN77 [get_ports {ddr4_rtl_0_adr[14]}]
set_property PACKAGE_PIN CJ77 [get_ports {ddr4_rtl_0_adr[15]}]
set_property PACKAGE_PIN DB76 [get_ports {ddr4_rtl_0_adr[16]}]

# Bank Group [1:0]
set_property PACKAGE_PIN CT74 [get_ports {ddr4_rtl_0_bg[0]}]
set_property PACKAGE_PIN CY76 [get_ports {ddr4_rtl_0_bg[1]}]

# Bank Address [1:0]
set_property PACKAGE_PIN CT78 [get_ports {ddr4_rtl_0_ba[0]}]
set_property PACKAGE_PIN CW77 [get_ports {ddr4_rtl_0_ba[1]}]

# Control signals
set_property PACKAGE_PIN CR83 [get_ports {ddr4_rtl_0_reset_n}]
set_property PACKAGE_PIN CY75 [get_ports {ddr4_rtl_0_act_n}]
set_property PACKAGE_PIN CU74 [get_ports {ddr4_rtl_0_ck_t[0]}]
set_property PACKAGE_PIN CV74 [get_ports {ddr4_rtl_0_ck_c[0]}]
set_property PACKAGE_PIN CY77 [get_ports {ddr4_rtl_0_ck_t[1]}]
set_property PACKAGE_PIN DA78 [get_ports {ddr4_rtl_0_ck_c[1]}]
set_property PACKAGE_PIN DC75 [get_ports {ddr4_rtl_0_cke[0]}]
set_property PACKAGE_PIN DA75 [get_ports {ddr4_rtl_0_cke[1]}]
set_property PACKAGE_PIN DB77 [get_ports {ddr4_rtl_0_cs_n[0]}]
set_property PACKAGE_PIN CP77 [get_ports {ddr4_rtl_0_cs_n[1]}]
set_property PACKAGE_PIN CP78 [get_ports {ddr4_rtl_0_odt[0]}]
set_property PACKAGE_PIN CU77 [get_ports {ddr4_rtl_0_odt[1]}]
set_property PACKAGE_PIN CR78 [get_ports {ddr4_rtl_0_par}]

# Data [71:0] (64 data + 8 ECC)
set_property PACKAGE_PIN CK73 [get_ports {ddr4_rtl_0_dq[0]}]
set_property PACKAGE_PIN CK72 [get_ports {ddr4_rtl_0_dq[1]}]
set_property PACKAGE_PIN CJ72 [get_ports {ddr4_rtl_0_dq[2]}]
set_property PACKAGE_PIN CJ73 [get_ports {ddr4_rtl_0_dq[3]}]
set_property PACKAGE_PIN CL73 [get_ports {ddr4_rtl_0_dq[4]}]
set_property PACKAGE_PIN CM73 [get_ports {ddr4_rtl_0_dq[5]}]
set_property PACKAGE_PIN CN72 [get_ports {ddr4_rtl_0_dq[6]}]
set_property PACKAGE_PIN CM72 [get_ports {ddr4_rtl_0_dq[7]}]
set_property PACKAGE_PIN CP73 [get_ports {ddr4_rtl_0_dq[8]}]
set_property PACKAGE_PIN CP72 [get_ports {ddr4_rtl_0_dq[9]}]
set_property PACKAGE_PIN CP74 [get_ports {ddr4_rtl_0_dq[10]}]
set_property PACKAGE_PIN CR73 [get_ports {ddr4_rtl_0_dq[11]}]
set_property PACKAGE_PIN CR71 [get_ports {ddr4_rtl_0_dq[12]}]
set_property PACKAGE_PIN CR72 [get_ports {ddr4_rtl_0_dq[13]}]
set_property PACKAGE_PIN CT70 [get_ports {ddr4_rtl_0_dq[14]}]
set_property PACKAGE_PIN CT71 [get_ports {ddr4_rtl_0_dq[15]}]
set_property PACKAGE_PIN CW69 [get_ports {ddr4_rtl_0_dq[16]}]
set_property PACKAGE_PIN CW70 [get_ports {ddr4_rtl_0_dq[17]}]
set_property PACKAGE_PIN CY73 [get_ports {ddr4_rtl_0_dq[18]}]
set_property PACKAGE_PIN CW73 [get_ports {ddr4_rtl_0_dq[19]}]
set_property PACKAGE_PIN CY72 [get_ports {ddr4_rtl_0_dq[20]}]
set_property PACKAGE_PIN DA73 [get_ports {ddr4_rtl_0_dq[21]}]
set_property PACKAGE_PIN DA69 [get_ports {ddr4_rtl_0_dq[22]}]
set_property PACKAGE_PIN DA70 [get_ports {ddr4_rtl_0_dq[23]}]
set_property PACKAGE_PIN CK76 [get_ports {ddr4_rtl_0_dq[24]}]
set_property PACKAGE_PIN CK75 [get_ports {ddr4_rtl_0_dq[25]}]
set_property PACKAGE_PIN CL75 [get_ports {ddr4_rtl_0_dq[26]}]
set_property PACKAGE_PIN CL74 [get_ports {ddr4_rtl_0_dq[27]}]
set_property PACKAGE_PIN CN76 [get_ports {ddr4_rtl_0_dq[28]}]
set_property PACKAGE_PIN CN75 [get_ports {ddr4_rtl_0_dq[29]}]
set_property PACKAGE_PIN CP75 [get_ports {ddr4_rtl_0_dq[30]}]
set_property PACKAGE_PIN CR75 [get_ports {ddr4_rtl_0_dq[31]}]
set_property PACKAGE_PIN DA81 [get_ports {ddr4_rtl_0_dq[32]}]
set_property PACKAGE_PIN CY82 [get_ports {ddr4_rtl_0_dq[33]}]
set_property PACKAGE_PIN CW82 [get_ports {ddr4_rtl_0_dq[34]}]
set_property PACKAGE_PIN CW83 [get_ports {ddr4_rtl_0_dq[35]}]
set_property PACKAGE_PIN DA79 [get_ports {ddr4_rtl_0_dq[36]}]
set_property PACKAGE_PIN DA80 [get_ports {ddr4_rtl_0_dq[37]}]
set_property PACKAGE_PIN DC79 [get_ports {ddr4_rtl_0_dq[38]}]
set_property PACKAGE_PIN DB79 [get_ports {ddr4_rtl_0_dq[39]}]
set_property PACKAGE_PIN CU83 [get_ports {ddr4_rtl_0_dq[40]}]
set_property PACKAGE_PIN CT83 [get_ports {ddr4_rtl_0_dq[41]}]
set_property PACKAGE_PIN CU81 [get_ports {ddr4_rtl_0_dq[42]}]
set_property PACKAGE_PIN CT81 [get_ports {ddr4_rtl_0_dq[43]}]
set_property PACKAGE_PIN CV79 [get_ports {ddr4_rtl_0_dq[44]}]
set_property PACKAGE_PIN CU79 [get_ports {ddr4_rtl_0_dq[45]}]
set_property PACKAGE_PIN CV80 [get_ports {ddr4_rtl_0_dq[46]}]
set_property PACKAGE_PIN CV81 [get_ports {ddr4_rtl_0_dq[47]}]
set_property PACKAGE_PIN CM81 [get_ports {ddr4_rtl_0_dq[48]}]
set_property PACKAGE_PIN CM82 [get_ports {ddr4_rtl_0_dq[49]}]
set_property PACKAGE_PIN CN82 [get_ports {ddr4_rtl_0_dq[50]}]
set_property PACKAGE_PIN CM83 [get_ports {ddr4_rtl_0_dq[51]}]
set_property PACKAGE_PIN CN81 [get_ports {ddr4_rtl_0_dq[52]}]
set_property PACKAGE_PIN CN80 [get_ports {ddr4_rtl_0_dq[53]}]
set_property PACKAGE_PIN CP79 [get_ports {ddr4_rtl_0_dq[54]}]
set_property PACKAGE_PIN CP80 [get_ports {ddr4_rtl_0_dq[55]}]
set_property PACKAGE_PIN CJ83 [get_ports {ddr4_rtl_0_dq[56]}]
set_property PACKAGE_PIN CJ82 [get_ports {ddr4_rtl_0_dq[57]}]
set_property PACKAGE_PIN CK80 [get_ports {ddr4_rtl_0_dq[58]}]
set_property PACKAGE_PIN CJ80 [get_ports {ddr4_rtl_0_dq[59]}]
set_property PACKAGE_PIN CK82 [get_ports {ddr4_rtl_0_dq[60]}]
set_property PACKAGE_PIN CK81 [get_ports {ddr4_rtl_0_dq[61]}]
set_property PACKAGE_PIN CL79 [get_ports {ddr4_rtl_0_dq[62]}]
set_property PACKAGE_PIN CK78 [get_ports {ddr4_rtl_0_dq[63]}]
set_property PACKAGE_PIN DB73 [get_ports {ddr4_rtl_0_dq[64]}]
set_property PACKAGE_PIN DC74 [get_ports {ddr4_rtl_0_dq[65]}]
set_property PACKAGE_PIN DB74 [get_ports {ddr4_rtl_0_dq[66]}]
set_property PACKAGE_PIN DA74 [get_ports {ddr4_rtl_0_dq[67]}]
set_property PACKAGE_PIN DB69 [get_ports {ddr4_rtl_0_dq[68]}]
set_property PACKAGE_PIN DC69 [get_ports {ddr4_rtl_0_dq[69]}]
set_property PACKAGE_PIN DC70 [get_ports {ddr4_rtl_0_dq[70]}]
set_property PACKAGE_PIN DC71 [get_ports {ddr4_rtl_0_dq[71]}]

# Data Strobes [8:0] (differential pairs)
set_property PACKAGE_PIN CJ70 [get_ports {ddr4_rtl_0_dqs_t[0]}]
set_property PACKAGE_PIN CK71 [get_ports {ddr4_rtl_0_dqs_c[0]}]
set_property PACKAGE_PIN CN71 [get_ports {ddr4_rtl_0_dqs_t[1]}]
set_property PACKAGE_PIN CN70 [get_ports {ddr4_rtl_0_dqs_c[1]}]
set_property PACKAGE_PIN CV72 [get_ports {ddr4_rtl_0_dqs_t[2]}]
set_property PACKAGE_PIN CW72 [get_ports {ddr4_rtl_0_dqs_c[2]}]
set_property PACKAGE_PIN CJ75 [get_ports {ddr4_rtl_0_dqs_t[3]}]
set_property PACKAGE_PIN CJ74 [get_ports {ddr4_rtl_0_dqs_c[3]}]
set_property PACKAGE_PIN CW80 [get_ports {ddr4_rtl_0_dqs_t[4]}]
set_property PACKAGE_PIN CW79 [get_ports {ddr4_rtl_0_dqs_c[4]}]
set_property PACKAGE_PIN CT80 [get_ports {ddr4_rtl_0_dqs_t[5]}]
set_property PACKAGE_PIN CT79 [get_ports {ddr4_rtl_0_dqs_c[5]}]
set_property PACKAGE_PIN CL81 [get_ports {ddr4_rtl_0_dqs_t[6]}]
set_property PACKAGE_PIN CL80 [get_ports {ddr4_rtl_0_dqs_c[6]}]
set_property PACKAGE_PIN CJ79 [get_ports {ddr4_rtl_0_dqs_t[7]}]
set_property PACKAGE_PIN CJ78 [get_ports {ddr4_rtl_0_dqs_c[7]}]
set_property PACKAGE_PIN DA71 [get_ports {ddr4_rtl_0_dqs_t[8]}]
set_property PACKAGE_PIN DB71 [get_ports {ddr4_rtl_0_dqs_c[8]}]

# Data Mask [8:0]
set_property PACKAGE_PIN CL71 [get_ports {ddr4_rtl_0_dm_n[0]}]
set_property PACKAGE_PIN CP70 [get_ports {ddr4_rtl_0_dm_n[1]}]
set_property PACKAGE_PIN CY71 [get_ports {ddr4_rtl_0_dm_n[2]}]
set_property PACKAGE_PIN CM74 [get_ports {ddr4_rtl_0_dm_n[3]}]
set_property PACKAGE_PIN CY81 [get_ports {ddr4_rtl_0_dm_n[4]}]
set_property PACKAGE_PIN CU82 [get_ports {ddr4_rtl_0_dm_n[5]}]
set_property PACKAGE_PIN CM79 [get_ports {ddr4_rtl_0_dm_n[6]}]
set_property PACKAGE_PIN CK83 [get_ports {ddr4_rtl_0_dm_n[7]}]
set_property PACKAGE_PIN DB72 [get_ports {ddr4_rtl_0_dm_n[8]}]

# Alert
set_property PACKAGE_PIN CR82 [get_ports {ddr4_rtl_0_alert_n}]

# =============================================================================
# Timing Constraints
# =============================================================================

# False path for async resets and slow control signals
set_false_path -from [get_ports reset]
set_false_path -to [get_ports {leds[*]}]
set_false_path -to [get_ports sd_vsd_en]
set_false_path -to [get_ports sd_sel]
set_false_path -to [get_ports sd_resetn]

# The native SD debug sampler observes the generated SD clock only for ILA
# status. Constrain the asynchronous input to the first synchronizer stage;
# the second stage and all functional SD paths remain timed normally.
set p3_sd_debug_sync_d [get_pins -quiet -hier -filter {NAME =~ */p3_sd_clk_sample_q_reg/D}]
if {[llength $p3_sd_debug_sync_d] > 0} {
    set_false_path -to $p3_sd_debug_sync_d
}
unset p3_sd_debug_sync_d
