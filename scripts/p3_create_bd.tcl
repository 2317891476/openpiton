# p3_create_bd.tcl
# Create Vivado Block Design for OpenPiton single-core on HuaPro P3 (Versal VP1902)
#
# Usage: vivado -mode batch -source scripts/p3_create_bd.tcl
#
# This script creates a new Vivado project with a Block Design containing:
#   - Clock Wizard (100 MHz diff in -> 30 MHz chipset + 30 MHz SD clocks)
#   - AXI NoC + DDRMC (DDR4 SODIMM)
#   - ps_wizard (Versal PMC init)
#   - proc_sys_reset (synchronized reset)
#   - OpenPiton chipset as HDL module reference
#   - ILA for debug
#
# The OpenPiton RTL is instantiated as a module_ref (black-box wrapper).
# Verilog source files must be added to the project separately.

set script_dir [file dirname [info script]]
set proj_dir [file normalize "${script_dir}/../huaprop3_openpiton"]
set proj_name "huaprop3_openpiton"
set bd_name "openpiton_top"
set part "xcvp1902-vsva6865-1MP-e-S"

# Reference project for DDR4 XDC
set ref_xdc_dir [file normalize "${script_dir}/../huaprop3onecore/huaprop3onecore.srcs/constrs_1"]
set piton_root [file normalize "${script_dir}/.."]

puts "=========================================="
puts " P3 OpenPiton Block Design Creator"
puts " Project: ${proj_dir}"
puts " Part: ${part}"
puts "=========================================="

# ============================================================================
# 1. Create Project
# ============================================================================
create_project ${proj_name} ${proj_dir} -part ${part} -force
set_property target_language Verilog [current_project]

# ============================================================================
# 2. Create Block Design
# ============================================================================
create_bd_design ${bd_name}

# ============================================================================
# 3. Add External Interface Ports
# ============================================================================

# System clock: 100 MHz LVDS15 differential
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 diff_sysclock
set_property CONFIG.FREQ_HZ 100000000 [get_bd_intf_ports diff_sysclock]

# DDR4 memory clock: 100 MHz LVDS15 differential (separate ref clock for DDRMC)
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 diff_memclock
set_property CONFIG.FREQ_HZ 100000000 [get_bd_intf_ports diff_memclock]

# DDR4 SODIMM interface
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 ddr4_rtl_0

# Reset (active-HIGH from P3 push button)
create_bd_port -dir I -type rst reset
set_property CONFIG.POLARITY ACTIVE_HIGH [get_bd_ports reset]

# (UART, SD, LEDs are NOT in the BD — they connect directly in p3_top.v)

# ============================================================================
# 4. Add IP: Clock Wizard
# ============================================================================
# 100 MHz diff input -> 30 MHz chipset_clk, 30 MHz sd_sys_clk
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wizard:1.0 clk_wizard_0
set_property -dict [list \
    CONFIG.PRIM_SOURCE {Differential_clock_capable_pin} \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.USE_RESET {true} \
    CONFIG.CLKOUT_USED {true,true,false,false,false,false,false} \
    CONFIG.CLKOUT_PORT {chipset_clk,sd_sys_clk,clk_out3,clk_out4,clk_out5,clk_out6,clk_out7} \
    CONFIG.CLKOUT_REQUESTED_OUT_FREQUENCY {30.000,30.000,100.000,100.000,100.000,100.000,100.000} \
    CONFIG.CLKOUT_REQUESTED_PHASE {0.000,0.000,0.000,0.000,0.000,0.000,0.000} \
    CONFIG.CLKOUT_REQUESTED_DUTY_CYCLE {50.000,50.000,50.000,50.000,50.000,50.000,50.000} \
] [get_bd_cells clk_wizard_0]

# ============================================================================
# 5. Add IP: AXI NoC with DDRMC
# ============================================================================
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_noc:1.1 axi_noc_0
set_property -dict [list \
    CONFIG.NUM_MC {1} \
    CONFIG.NUM_MI {0} \
    CONFIG.MC_CHAN_REGION0 {DDR_LOW0} \
    CONFIG.MC_DATAWIDTH {72} \
    CONFIG.MC_DDR4_2T {Enable} \
    CONFIG.MC_MEMORY_DEVICETYPE {SODIMMs} \
    CONFIG.MC_MEMORY_SPEEDGRADE {DDR4-2933Y(21-21-21)} \
    CONFIG.MC_MEMORY_TIMEPERIOD0 {682} \
    CONFIG.MC_PARITY {true} \
    CONFIG.MC_RANK {2} \
    CONFIG.MC_ROWADDRESSWIDTH {17} \
    CONFIG.MC_REF_AND_PER_CAL_INTF {FALSE} \
] [get_bd_cells axi_noc_0]

# Configure AXI slave port for OpenPiton's AXI4 interface
# OpenPiton noc_axi4_bridge: 512-bit data, 64-bit addr, 6-bit ID
set_property -dict [list \
    CONFIG.CONNECTIONS {MC_0 {read_bw {500} write_bw {500} read_avg_burst {4} write_avg_burst {4}}} \
    CONFIG.CATEGORY {pl} \
] [get_bd_intf_pins axi_noc_0/S00_AXI]

# ============================================================================
# 6. Add IP: ps_wizard (Versal PMC/PS initialization)
# ============================================================================
create_bd_cell -type ip -vlnv xilinx.com:ip:ps_wizard:1.0 ps_wizard_0
# Minimal config — just enough for PL fabric to work
# Copy reference project's PS_PMC_CONFIG for SD/SMAP settings
set_property -dict [list \
    CONFIG.PS_PMC_CONFIG { \
        PMC_SMAP_PERIPHERAL {PRIMARY_ENABLE 1 IO 8_Bit} \
        SMON_INTERFACE_TO_USE {PMBus} \
        SMON_PMBUS_ADDRESS {0x18} \
    } \
] [get_bd_cells ps_wizard_0]

# ============================================================================
# 7. Add IP: Processor System Reset
# ============================================================================
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0

# ============================================================================
# 8. Add IP: BD-Owned Minimal Debug ILA
# ============================================================================
# Keep this ILA in the block design so Versal debug hub/address-path generation
# follows the same BD-owned route as the validated huaprop3onecore reference.
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_ila:1.3 axis_ila_0
set_property -dict [list \
    CONFIG.C_MON_TYPE {Net_Probes} \
    CONFIG.C_NUM_OF_PROBES {2} \
    CONFIG.C_PROBE0_WIDTH {32} \
    CONFIG.C_PROBE1_WIDTH {32} \
    CONFIG.C_DATA_DEPTH {2048} \
    CONFIG.C_EN_STRG_QUAL {0} \
    CONFIG.C_ADV_TRIGGER {false} \
    CONFIG.C_INPUT_PIPE_STAGES {0} \
    CONFIG.ALL_PROBE_SAME_MU {true} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {2} \
] [get_bd_cells axis_ila_0]

# ============================================================================
# 9. Add OpenPiton Wrapper as Module Reference
# ============================================================================
# openpiton_wrapper.v is a thin wrapper around system.v that exposes only the
# ports active for HUAPROP3_BOARD: AXI4 master, clocks, reset, UART, SD, LEDs.
# It will be added as a module_ref after RTL source files are loaded.
# The module_ref cell is created here as a placeholder.

# NOTE: Vivado create_bd_cell -type module_ref requires the RTL to be in the
# project first. Since RTL is added in section 14 (after BD creation), we
# defer the module_ref instantiation to a separate step.
# Instead, we document the intended connections here, and the actual
# module_ref creation + wiring happens after RTL is loaded.

# ============================================================================
# 10. Connect Clock and Reset (infrastructure only, no OpenPiton yet)
# ============================================================================

# System clock -> Clock Wizard input
connect_bd_intf_net [get_bd_intf_ports diff_sysclock] [get_bd_intf_pins clk_wizard_0/CLK_IN1_D]

# Memory ref clock -> AXI NoC
connect_bd_intf_net [get_bd_intf_ports diff_memclock] [get_bd_intf_pins axi_noc_0/sys_clk0]

# DDR4 interface -> external port
connect_bd_intf_net [get_bd_intf_pins axi_noc_0/CH0_DDR4_0] [get_bd_intf_ports ddr4_rtl_0]

# Reset -> Clock Wizard reset input
connect_bd_net [get_bd_ports reset] [get_bd_pins clk_wizard_0/reset]

# Reset -> proc_sys_reset external reset
connect_bd_net [get_bd_ports reset] [get_bd_pins proc_sys_reset_0/ext_reset_in]

# Clock Wizard chipset_clk -> proc_sys_reset slowest_sync_clk
connect_bd_net [get_bd_pins clk_wizard_0/chipset_clk] [get_bd_pins proc_sys_reset_0/slowest_sync_clk]

# Clock Wizard chipset_clk -> AXI NoC aclk0
connect_bd_net [get_bd_pins clk_wizard_0/chipset_clk] [get_bd_pins axi_noc_0/aclk0]

# Clock Wizard chipset_clk -> BD-owned ILA clock
connect_bd_net [get_bd_pins clk_wizard_0/chipset_clk] [get_bd_pins axis_ila_0/clk]

# Versal clk_wizard does not expose a 'locked' pin like 7-series clk_wiz.
# Tie dcm_locked to VCC so proc_sys_reset doesn't wait for lock.
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_locked
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] [get_bd_cells const_locked]
connect_bd_net [get_bd_pins const_locked/dout] [get_bd_pins proc_sys_reset_0/dcm_locked]

# ============================================================================
# 11. Validate and Save (initial, before RTL)
# ============================================================================
regenerate_bd_layout
save_bd_design

# ============================================================================
# 12. Add Constraint Files
# ============================================================================
set xdc_file "${piton_root}/piton/design/xilinx/huaprop3/constraints.xdc"
if {[file exists $xdc_file]} {
    add_files -fileset constrs_1 -norecurse $xdc_file
    puts "Added OpenPiton constraints: ${xdc_file}"
}

# ============================================================================
# 13. Add OpenPiton RTL Source Files
# ============================================================================
# Source the canonical file list from protosyn infrastructure.
# This sets SYSTEM_RTL_IMPL_FILES, CHIP_RTL_IMPL_FILES, CHIPSET_RTL_IMPL_FILES,
# GLOBAL_INCLUDE_FILES, GLOBAL_INCLUDE_DIRS, and board-specific macros.

set DV_ROOT "${piton_root}/piton"

# Board variable must be set before sourcing rtl_setup.tcl (it uses $BOARD for IP paths)
set BOARD "huaprop3"
set BOARD_DIR "${DV_ROOT}/design/xilinx/${BOARD}"

source "${DV_ROOT}/tools/src/proto/common/rtl_setup.tcl"

# Board-specific macros
source "${DV_ROOT}/tools/src/proto/${BOARD}/board.tcl"

# PyHP preprocessing: resolve .pyv files to .tmp.v/.tmp.h outputs.
# Uses pre-existing .tmp files (generated by previous protosyn run or manual pyhp).
# Falls back to running pyhp.py if .tmp files don't exist.
source "${DV_ROOT}/tools/src/proto/common/pyhp_preprocess.tcl"

set all_rtl_files [list]
foreach f $SYSTEM_RTL_IMPL_FILES { lappend all_rtl_files $f }
foreach f $CHIP_RTL_IMPL_FILES   { lappend all_rtl_files $f }
foreach f $CHIPSET_RTL_IMPL_FILES { lappend all_rtl_files $f }

set all_rtl_files [pyhp_preprocess $all_rtl_files]
set ALL_INCLUDE_FILES [pyhp_preprocess $GLOBAL_INCLUDE_FILES]

# Add RTL source files to project (bulk add for performance)
set existing_rtl_files [list]
set missing_count 0
foreach f $all_rtl_files {
    if {[file exists $f]} {
        lappend existing_rtl_files $f
    } else {
        puts "WARNING: RTL file not found: $f"
        incr missing_count
    }
}
if {[llength $existing_rtl_files] > 0} {
    add_files -norecurse $existing_rtl_files
}
set added_count [llength $existing_rtl_files]
puts "Added ${added_count} RTL source files (${missing_count} missing)"

# Add include files and mark as Verilog Headers (required for MODULE reference scanning)
# First add GLOBAL_INCLUDE_FILES
set existing_inc_files [list]
foreach f $ALL_INCLUDE_FILES {
    if {[file exists $f]} {
        lappend existing_inc_files $f
    }
}

# Also add ALL .h/.vh/.svh files from include directories AND extra chipset dirs
# (MODULE reference scanner traces full hierarchy and needs every header)
set all_glob_dirs [concat [split $GLOBAL_INCLUDE_DIRS] [list \
    "${DV_ROOT}/design/chipset/noc_axi4_bridge/rtl" \
    "${DV_ROOT}/design/chipset/noc_sd_bridge/rtl" \
    "${DV_ROOT}/design/chipset/axi_sd_bridge/rtl" \
]]
foreach inc_dir $all_glob_dirs {
    if {$inc_dir eq ""} { continue }
    foreach pattern {*.h *.vh} {
        foreach f [glob -nocomplain -directory $inc_dir $pattern] {
            if {[lsearch -exact $existing_inc_files $f] == -1} {
                lappend existing_inc_files $f
            }
        }
    }
}

if {[llength $existing_inc_files] > 0} {
    add_files -norecurse $existing_inc_files
    foreach inc_file $existing_inc_files {
        set file_obj [get_files -of_objects [current_fileset] [list "$inc_file"]]
        set_property "file_type" "Verilog Header" $file_obj
        set_property "is_global_include" "1" $file_obj
    }
}
puts "Added [llength $existing_inc_files] include/header files"

# Mark .h/.vh in RTL set as headers; .sv as SystemVerilog
# Do NOT mark .svh as global include — tracer .svh files contain SV class
# syntax that fails when parsed as Verilog Header. The .svh files that matter
# are resolved via `include directives through include_dirs.
foreach f $existing_rtl_files {
    set ext [file extension $f]
    if {$ext eq ".h" || $ext eq ".vh"} {
        set file_obj [get_files -of_objects [current_fileset] [list "$f"]]
        set_property "file_type" "Verilog Header" $file_obj
        set_property "is_global_include" "1" $file_obj
    } elseif {$ext eq ".sv"} {
        set file_obj [get_files -of_objects [current_fileset] [list "$f"]]
        set_property "file_type" "SystemVerilog" $file_obj
    }
}

# Set include directories for synthesis
# Add chipset sub-block include dirs that aren't in GLOBAL_INCLUDE_DIRS
# (noc_axi4_bridge_define.vh, sd_defines.h, piton_sd_define.vh, etc.)
set extra_inc_dirs [list \
    "${DV_ROOT}/design/chipset/noc_axi4_bridge/rtl" \
    "${DV_ROOT}/design/chipset/noc_sd_bridge/rtl" \
    "${DV_ROOT}/design/chipset/axi_sd_bridge/rtl" \
]
set all_inc_dirs [concat [split $GLOBAL_INCLUDE_DIRS] $extra_inc_dirs]
set_property include_dirs $all_inc_dirs [current_fileset]

# Add the Xilinx AXI UART 16550 IP used by uart_top.v when PITON_UART16550 is
# enabled. The huaprop3 board currently reuses the checked-in OpenPiton
# generated IP from genesys2; without importing it, a clean project rebuild
# reaches top synthesis with an unresolved uart_16550 module.
set uart16550_xci ""
foreach candidate [list \
    "${DV_ROOT}/design/chipset/io_ctrl/xilinx/${BOARD}/ip_cores/uart_16550/uart_16550.xci" \
    "${DV_ROOT}/design/chipset/io_ctrl/xilinx/genesys2/ip_cores/uart_16550/uart_16550.xci" \
] {
    if {[file exists $candidate]} {
        set uart16550_xci $candidate
        break
    }
}

if {$uart16550_xci eq ""} {
    puts "ERROR: uart_16550.xci not found for ${BOARD} or genesys2 fallback"
    exit 1
}

puts "Importing UART 16550 IP: ${uart16550_xci}"
if {[catch {import_ip -files $uart16550_xci -name uart_16550} uart_import_err]} {
    puts "ERROR: failed to import UART 16550 IP: ${uart_import_err}"
    exit 1
}
set uart16550_ip [get_ips uart_16550]
generate_target all $uart16550_ip
export_ip_user_files -of_objects $uart16550_ip -no_script -sync -force -quiet
puts "Added UART 16550 IP: ${uart16550_ip}"

# Set Verilog defines
# P3 uses PITON_FULL_SYSTEM (enables PITONSYS_IOCTRL, PITONSYS_UART, PITONSYS_SPI)
# but piton_system.vh HUAPROP3_BOARD block then:
#   - undefs PITON_CHIPSET_CLKS_GEN (clocks from external BD, not internal MMCM)
#   - defines PITONSYS_AXI4_MEM (AXI4 memory interface, not DDR pin interface)
# PITON_FPGA_MC_DDR3 is still needed to enable the noc_axi4_bridge path.
set DESIGN_DEFAULT_VERILOG_MACROS "PITON_FULL_SYSTEM PITON_FPGA_NO_DMBR MERGE_L1_DCACHE FPGA_SYN_1THREAD FPGA_FORCE_SRAM_ICACHE_TAG FPGA_FORCE_SRAM_LSU_ICACHE FPGA_FORCE_SRAM_DCACHE_TAG FPGA_FORCE_SRAM_LSU_DCACHE FPGA_FORCE_SRAM_RF16X160 FPGA_FORCE_SRAM_RF32X80 CONFIG_DISABLE_BIST_CLEAR"
set PROTOSYN_VERILOG_MACROS "NO_RTL_CSM PITON_FPGA_MC_DDR3 PITON_NO_CHIP_BRIDGE PITONSYS_MEM_ZEROER PITON_FPGA_SD_BOOT PITONSYS_UART_BOOT PITON_UART16550 PITONSYS_AXI4_MEM"
set all_macros "${GLOBAL_DEFAULT_VERILOG_MACROS} ${DESIGN_DEFAULT_VERILOG_MACROS} ${BOARD_DEFAULT_VERILOG_MACROS} ${PROTOSYN_VERILOG_MACROS}"
set defines_list [list]
foreach m $all_macros {
    if {$m ne ""} { lappend defines_list $m }
}
set_property verilog_define $defines_list [current_fileset]
puts "Verilog defines: $defines_list"

# ============================================================================
# 14. Expose BD Internal Signals as External Ports (for top-level connection)
# ============================================================================
# Instead of MODULE reference (which can't handle mixed Verilog+SystemVerilog),
# we expose the BD infrastructure signals as ports. A separate top-level file
# (p3_top.v) instantiates both the BD wrapper and openpiton_wrapper.

# Expose chipset_clk and sd_sys_clk as BD output ports
create_bd_port -dir O chipset_clk_o
create_bd_port -dir O sd_sys_clk_o
connect_bd_net [get_bd_pins clk_wizard_0/chipset_clk] [get_bd_ports chipset_clk_o]
connect_bd_net [get_bd_pins clk_wizard_0/sd_sys_clk]  [get_bd_ports sd_sys_clk_o]

# Expose synchronized reset as BD output port (active-low)
create_bd_port -dir O -from 0 -to 0 peripheral_aresetn_o
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_ports peripheral_aresetn_o]

# Feed top-level minimal debug signals into the BD-owned ILA.
create_bd_port -dir I -from 31 -to 0 p3_dbg_heartbeat_i
create_bd_port -dir I -from 31 -to 0 p3_dbg_status_i
connect_bd_net [get_bd_ports p3_dbg_heartbeat_i] [get_bd_pins axis_ila_0/probe0]
connect_bd_net [get_bd_ports p3_dbg_status_i]    [get_bd_pins axis_ila_0/probe1]

# Create AXI4 Slave port on BD for OpenPiton to connect to
# This connects to AXI NoC S00_AXI
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI_MEM
set_property -dict [list \
    CONFIG.DATA_WIDTH {512} \
    CONFIG.ADDR_WIDTH {64} \
    CONFIG.ID_WIDTH {6} \
    CONFIG.HAS_REGION {1} \
    CONFIG.HAS_QOS {1} \
    CONFIG.FREQ_HZ {30000000} \
] [get_bd_intf_ports S_AXI_MEM]
connect_bd_intf_net [get_bd_intf_ports S_AXI_MEM] [get_bd_intf_pins axi_noc_0/S00_AXI]

# ============================================================================
# 15. Address Map
# ============================================================================
# OpenPiton's storage_addr_trans_unified subtracts 0x80000000 from CPU addresses
# before outputting on AXI, so AXI-side DDR starts at 0x0.
# Map to DDR_LOW0 in AXI NoC at offset 0x0, range 2 GB.
assign_bd_address [get_bd_addr_segs {axi_noc_0/S00_AXI/C0_DDR_LOW0}]
set_property offset 0x00000000 [get_bd_addr_segs {S_AXI_MEM/SEG_axi_noc_0_C0_DDR_LOW0}]
set_property range 2G [get_bd_addr_segs {S_AXI_MEM/SEG_axi_noc_0_C0_DDR_LOW0}]

# ============================================================================
# 16. Final Validate and Save
# ============================================================================
regenerate_bd_layout
save_bd_design

# Try validation — may have warnings on first pass
if {[catch {validate_bd_design} err]} {
    puts "WARNING: BD validation reported issues:"
    puts $err
    puts "Review and fix in Vivado GUI before synthesis."
} else {
    puts "Block Design validation passed."
}

# Generate HDL wrapper
make_wrapper -files [get_files ${bd_name}.bd] -top
add_files -norecurse ${proj_dir}/${proj_name}.gen/sources_1/bd/${bd_name}/hdl/${bd_name}_wrapper.v
update_compile_order -fileset sources_1

# ============================================================================
# 16b. Add Required IP Wrappers
# ============================================================================
# afifo_w64_d128_std: Async FIFO (64-bit, 128 deep) for NoC<->memory clock crossing.
# Used by noc_bidir_afifo.v. On 7-series boards this is a fifo_generator IP, but
# fifo_generator is not available on Versal. We use an XPM-based wrapper instead.
set afifo_file "${piton_root}/piton/design/chipset/xilinx/huaprop3/ip_cores/afifo_w64_d128_std.v"
if {[file exists $afifo_file]} {
    add_files -norecurse $afifo_file
    puts "Added XPM FIFO wrapper: ${afifo_file}"
} else {
    puts "WARNING: afifo_w64_d128_std.v not found at ${afifo_file}"
}

# ============================================================================
# 17. Add OpenPiton RTL and Top-Level, Set Synthesis Top
# ============================================================================
# Add the openpiton_wrapper
set wrapper_file "${piton_root}/piton/design/xilinx/huaprop3/openpiton_wrapper.v"
if {[file exists $wrapper_file]} {
    add_files -norecurse $wrapper_file
    puts "Added wrapper: ${wrapper_file}"
}

# Add the top-level file that connects BD + OpenPiton
set top_file "${piton_root}/piton/design/xilinx/huaprop3/p3_top.v"
if {[file exists $top_file]} {
    add_files -norecurse $top_file
    puts "Added top: ${top_file}"
}

# Set project top to p3_top (NOT the BD wrapper)
set_property top p3_top [current_fileset]
update_compile_order -fileset sources_1

puts "=========================================="
puts " Block Design '${bd_name}' complete."
puts " RTL sources: ${added_count} files added"
puts " Top module: p3_top (BD infra + OpenPiton)"
puts " DDR map: 0x00000000, 2 GB (DDR_LOW0)"
puts ""
puts " NEXT STEPS:"
puts " 1. Open project in Vivado GUI: open_project ${proj_dir}/${proj_name}.xpr"
puts " 2. Run synthesis: launch_runs synth_1 -jobs 8"
puts " 3. Run implementation: launch_runs impl_1 -to_step write_device_image"
puts " 4. Program FPGA: source scripts/p3_program.tcl"
puts "=========================================="

close_project
