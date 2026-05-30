# p3_prepare_build43_uart_live_narrow_ila.tcl -- Prepare Build 43 UART ILAs.
# Usage:
#   vivado -mode batch -source scripts/p3_prepare_build43_uart_live_narrow_ila.tcl

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]
set project_name "huaprop3_build43_asm_uart16550"
set project_dir [file normalize "${repo_dir}/${project_name}"]
set bd_name "openpiton_top"
set bd_file "${project_dir}/${project_name}.srcs/sources_1/bd/${bd_name}/${bd_name}.bd"
set tmp_dir "Z:/tmp"
set p3_uart_ila_data_depth 1024
set p3_uart_ila_input_pipe_stages 0

puts "=========================================="
puts " Build 43 prepare: AXI16550 live-narrow UART ILAs"
puts " Project: ${project_dir}/${project_name}.xpr"
puts " BD: ${bd_file}"
puts "=========================================="

proc p3_require_file {path label} {
    if {![file exists $path]} {
        puts "ERROR: missing ${label}: ${path}"
        exit 1
    }
}

proc p3_require_tokens {path label tokens} {
    p3_require_file $path $label
    set fh [open $path r]
    set data [read $fh]
    close $fh
    foreach token $tokens {
        if {[string first $token $data] < 0} {
            puts "ERROR: ${label} is missing expected Build 43 token: ${token}"
            puts "       File: ${path}"
            exit 1
        }
    }
}

proc p3_copy_tmp_rtl {repo_dir tmp_dir} {
    file mkdir $tmp_dir
    foreach {src dst label} [list \
        "${repo_dir}/piton/design/xilinx/huaprop3/p3_top.v" "${tmp_dir}/p3_top.v" "P3 top RTL" \
        "${repo_dir}/piton/design/xilinx/huaprop3/openpiton_wrapper.v" "${tmp_dir}/openpiton_wrapper.v" "OpenPiton wrapper RTL" \
        "${repo_dir}/piton/design/rtl/system.v" "${tmp_dir}/system.v" "system RTL" \
        "${repo_dir}/piton/design/include/piton_system.vh" "${tmp_dir}/piton_system.vh" "piton_system include" \
    ] {
        p3_require_file $src $label
        file copy -force $src $dst
        puts "Synced ${label}: ${src} -> ${dst}"
    }

    p3_require_tokens "${tmp_dir}/p3_top.v" "synced P3 top RTL" \
        [list "P3_BD_UART_DEBUG_ILA" "p3_dbg_uart_seen16_i" "p3_dbg_uart_bus64_i"]
}

proc p3_create_port_if_missing {name args} {
    if {[llength [get_bd_ports -quiet $name]] == 0} {
        create_bd_port {*}$args $name
    }
}

proc p3_disconnect_bd_pin_if_connected {pin} {
    foreach net [get_bd_nets -quiet -of_objects $pin] {
        disconnect_bd_net $net $pin
    }
}

proc p3_disconnect_ila_pins {cell_name} {
    foreach pin [get_bd_pins -quiet ${cell_name}/clk] {
        p3_disconnect_bd_pin_if_connected $pin
    }
    foreach pin [get_bd_pins -quiet ${cell_name}/probe*] {
        p3_disconnect_bd_pin_if_connected $pin
    }
}

proc p3_connect_bd_net_fresh {driver sink} {
    p3_disconnect_bd_pin_if_connected $sink
    connect_bd_net $driver $sink
}

proc p3_delete_bd_port_if_present {name} {
    set port [get_bd_ports -quiet $name]
    if {[llength $port] != 0} {
        delete_bd_objs $port
    }
}

p3_copy_tmp_rtl $repo_dir $tmp_dir
p3_require_tokens "${repo_dir}/piton/design/chipset/io_ctrl/rtl/uart_top.v" "UART top RTL" \
    [list "P3_BD_UART_LIVE_NARROW_DEBUG_ILA" \
          "PITON_UART16550" \
          "s_axi_wdata\[7:0\]" \
          "core_axi_awaddr\[7:0\]"]

open_project "${project_dir}/${project_name}.xpr"
open_bd_design $bd_file

foreach ila_cell [list axis_ila_0 axis_ila_1] {
    if {[llength [get_bd_cells -quiet $ila_cell]] == 0} {
        create_bd_cell -type ip -vlnv xilinx.com:ip:axis_ila:1.3 $ila_cell
    }
    p3_disconnect_ila_pins $ila_cell
}

set_property -dict [list \
    CONFIG.C_MON_TYPE {Net_Probes} \
    CONFIG.C_NUM_OF_PROBES {3} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {16} \
    CONFIG.C_PROBE2_WIDTH {16} \
    CONFIG.C_DATA_DEPTH $p3_uart_ila_data_depth \
    CONFIG.C_EN_STRG_QUAL {0} \
    CONFIG.C_ADV_TRIGGER {false} \
    CONFIG.C_INPUT_PIPE_STAGES $p3_uart_ila_input_pipe_stages \
    CONFIG.ALL_PROBE_SAME_MU {true} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {2} \
] [get_bd_cells axis_ila_0]

set_property -dict [list \
    CONFIG.C_MON_TYPE {Net_Probes} \
    CONFIG.C_NUM_OF_PROBES {1} \
    CONFIG.C_PROBE0_WIDTH {64} \
    CONFIG.C_DATA_DEPTH $p3_uart_ila_data_depth \
    CONFIG.C_EN_STRG_QUAL {0} \
    CONFIG.C_ADV_TRIGGER {false} \
    CONFIG.C_INPUT_PIPE_STAGES $p3_uart_ila_input_pipe_stages \
    CONFIG.ALL_PROBE_SAME_MU {true} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {2} \
] [get_bd_cells axis_ila_1]

p3_create_port_if_missing p3_dbg_heartbeat_i -dir I -from 31 -to 0
p3_create_port_if_missing p3_dbg_status_i    -dir I -from 31 -to 0

foreach old_port [list \
    p3_dbg_seen_i \
    p3_dbg_top_status_i \
    p3_dbg_bus_i \
    p3_dbg_axi_araddr_i \
    p3_dbg_axi_awaddr_i \
    p3_dbg_seen15_i \
    p3_dbg_core_bus32_i \
    p3_dbg_axi_bus64_i \
    p3_dbg_chipset_seen16_i \
    p3_dbg_chipset_bus64_i \
    p3_dbg_chip_seen16_i \
    p3_dbg_b41_core_bus64_i \
    p3_dbg_b41_chipset_bus64_i \
] {
    p3_delete_bd_port_if_present $old_port
}

p3_create_port_if_missing p3_dbg_heartbeat_bit_i -dir I -from 0  -to 0
p3_create_port_if_missing p3_dbg_top_status16_i  -dir I -from 15 -to 0
p3_create_port_if_missing p3_dbg_uart_seen16_i   -dir I -from 15 -to 0
p3_create_port_if_missing p3_dbg_uart_bus64_i    -dir I -from 63 -to 0

p3_connect_bd_net_fresh [get_bd_pins clk_wizard_0/chipset_clk] [get_bd_pins axis_ila_0/clk]
p3_connect_bd_net_fresh [get_bd_ports p3_dbg_heartbeat_bit_i]  [get_bd_pins axis_ila_0/probe0]
p3_connect_bd_net_fresh [get_bd_ports p3_dbg_top_status16_i]   [get_bd_pins axis_ila_0/probe1]
p3_connect_bd_net_fresh [get_bd_ports p3_dbg_uart_seen16_i]    [get_bd_pins axis_ila_0/probe2]

p3_connect_bd_net_fresh [get_bd_pins clk_wizard_0/chipset_clk] [get_bd_pins axis_ila_1/clk]
p3_connect_bd_net_fresh [get_bd_ports p3_dbg_uart_bus64_i]     [get_bd_pins axis_ila_1/probe0]

regenerate_bd_layout
save_bd_design
validate_bd_design

puts "Generating BD output products for openpiton_top..."
generate_target all [get_files $bd_file]

make_wrapper -files [get_files ${bd_name}.bd] -top
set wrapper_file "${project_dir}/${project_name}.gen/sources_1/bd/${bd_name}/hdl/${bd_name}_wrapper.v"
if {[llength [get_files -quiet $wrapper_file]] == 0} {
    add_files -norecurse $wrapper_file
}

set defs [get_property verilog_define [current_fileset]]
set cleaned_defs {}
foreach define $defs {
    if {$define ne "P3_BD_RTL_DEBUG_ILA" &&
        $define ne "P3_BD_SPLIT_DEBUG_ILA" &&
        $define ne "P3_BD_CHIPSET_DEBUG_ILA" &&
        $define ne "P3_BD_BUILD41_DEBUG_ILA" &&
        $define ne "P3_BD_UART_WR_DEBUG_ILA" &&
        $define ne "P3_BD_UART_WR_NARROW_DEBUG_ILA" &&
        $define ne "P3_BD_UART_RAW_DEBUG_ILA" &&
        $define ne "P3_BD_SIFIVE_DEBUG_ILA" &&
        $define ne "P3_SIFIVE_UART" &&
        $define ne "P3_SIFIVE_UART_DEBUG_ILA"} {
        lappend cleaned_defs $define
    }
}
set defs $cleaned_defs

foreach required_define [list \
    PITON_UART16550 \
    P3_RTL_DEBUG \
    P3_BD_UART_DEBUG_ILA \
    P3_BD_UART_LIVE_NARROW_DEBUG_ILA \
    PITON_ARIANE \
    PITON_RV64_PLATFORM \
    PITON_RV64_DEBUGUNIT \
    PITON_RV64_CLINT \
    PITON_RV64_PLIC \
    WT_DCACHE \
] {
    if {[lsearch -exact $defs $required_define] < 0} {
        lappend defs $required_define
    }
}
set_property verilog_define $defs [current_fileset]
puts "Verilog defines: [get_property verilog_define [current_fileset]]"

update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -scripts_only
puts "Generated synth_1 scripts for Build 43."

foreach {run_name dcp_file} [list \
    openpiton_top_axis_ila_0_0_synth_1 "${project_dir}/${project_name}.gen/sources_1/bd/${bd_name}/ip/openpiton_top_axis_ila_0_0/openpiton_top_axis_ila_0_0.dcp" \
    openpiton_top_axis_ila_1_0_synth_1 "${project_dir}/${project_name}.gen/sources_1/bd/${bd_name}/ip/openpiton_top_axis_ila_1_0/openpiton_top_axis_ila_1_0.dcp" \
] {
    set ila_run [get_runs -quiet $run_name]
    if {[llength $ila_run] == 0 && [file exists $dcp_file]} {
        puts "Build 43 BD ILA OOC DCP already available without run object: $dcp_file"
        continue
    }
    if {[llength $ila_run] != 1} {
        puts "ERROR: expected one ${run_name} run or cached DCP ${dcp_file}, got [llength $ila_run] runs"
        exit 1
    }
    puts "Launching Build 43 BD ILA OOC run: $ila_run"
    reset_run $ila_run
    launch_runs $ila_run -jobs 1
    wait_on_run $ila_run
    set ila_status [get_property STATUS $ila_run]
    puts "Build 43 BD ILA OOC run status for ${run_name}: $ila_status"
    if {![string match "*Complete*" $ila_status]} {
        puts "ERROR: ${run_name} did not complete"
        exit 1
    }
}

close_project

puts "=========================================="
puts " Build 43 prepare complete."
puts "=========================================="
