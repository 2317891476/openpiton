# p3_build24_direct_flow.tcl -- Build 24 fallback flow without Vivado run manager.
# Usage: vivado -mode batch -source scripts/p3_build24_direct_flow.tcl
#
# This is intentionally separate from p3_build24_rtl_debug.tcl.  The normal
# project run flow can stall inside launch_runs/open_checkpoint on this VP1902
# design.  This script reuses the generated synth_1 Tcl file, keeps the
# synthesized design in memory, then runs implementation commands directly.

set repo_root "Z:/home/illya/openpiton"
set project_dir [file normalize "/home/illya/openpiton/huaprop3_openpiton"]
set project_name "huaprop3_openpiton"
set tmp_dir "Z:/tmp"
set xdc_file "${tmp_dir}/huaprop3_constraints.xdc"
set output_dir "${project_dir}/debug_build"
set direct_dir "${project_dir}/debug_build/build24_direct"
set synth_tcl "${project_dir}/${project_name}.runs/synth_1/p3_top.tcl"
set synth_dont_touch "${project_dir}/${project_name}.runs/synth_1/dont_touch.xdc"
set synth_dcp "${direct_dir}/p3_top.dcp"

set reuse_synth_dcp 0
foreach arg $argv {
    switch -- $arg {
        -reuse_synth {
            set reuse_synth_dcp 1
        }
        default {
            puts "ERROR: unknown argument: $arg"
            puts "Usage: vivado -mode batch -source scripts/p3_build24_direct_flow.tcl ?-tclargs -reuse_synth?"
            exit 1
        }
    }
}

puts "=========================================="
puts " Build 24: direct synth/impl fallback"
puts "=========================================="
if {$reuse_synth_dcp} {
    puts "Mode: reuse existing synthesis checkpoint"
}

file mkdir $tmp_dir
file mkdir $output_dir
if {!$reuse_synth_dcp} {
    file delete -force $direct_dir
}
file mkdir $direct_dir

foreach {src dst} [list \
    "${repo_root}/piton/design/xilinx/huaprop3/constraints.xdc" "${xdc_file}" \
    "${repo_root}/piton/design/xilinx/huaprop3/p3_top.v" "${tmp_dir}/p3_top.v" \
    "${repo_root}/piton/design/xilinx/huaprop3/openpiton_wrapper.v" "${tmp_dir}/openpiton_wrapper.v" \
    "${repo_root}/piton/design/rtl/system.v" "${tmp_dir}/system.v" \
    "${repo_root}/piton/design/include/piton_system.vh" "${tmp_dir}/piton_system.vh" \
] {
    if {![file exists $src]} {
        puts "ERROR: missing source file: $src"
        exit 1
    }
    file copy -force $src $dst
}

foreach required [list \
    $synth_tcl \
    $synth_dont_touch \
    "${repo_root}/piton/design/chip/rtl/chip.tmp.v" \
    "${repo_root}/piton/design/chip/tile/rtl/tile.tmp.v" \
    "${repo_root}/piton/design/chipset/rtl/chipset_impl.tmp.v" \
    "${repo_root}/piton/design/xilinx/huaprop3/unread_vivado_impl.sv" \
] {
    if {![file exists $required]} {
        puts "ERROR: missing required Build 24 file: $required"
        exit 1
    }
}

proc p3_debug_net_list {base width} {
    set names {}
    for {set i 0} {$i < $width} {incr i} {
        lappend names "{${base}\[${i}\]}"
    }
    return [join $names " "]
}

proc p3_write_debug_probe {fh port width label base} {
    puts "  ${port}: ${label} (${base}\\[${width}-1:0\\])"
    if {$port ne "probe0"} {
        puts $fh "create_debug_port u_ila_0 probe"
    }
    puts $fh "set_property port_width $width \[get_debug_ports u_ila_0/${port}\]"
    puts $fh "set_property PROBE_TYPE DATA_AND_TRIGGER \[get_debug_ports u_ila_0/${port}\]"
    puts $fh "connect_debug_port u_ila_0/${port} \[get_nets \[list [p3_debug_net_list $base $width] \]\]"
}

proc p3_run_step {label cmd checkpoint} {
    puts "---- ${label} ----"
    set t0 [clock seconds]
    if {[catch {uplevel 1 $cmd} err opts]} {
        puts "ERROR during ${label}: $err"
        puts [dict get $opts -errorinfo]
        exit 1
    }
    set dt [expr {[clock seconds] - $t0}]
    puts "${label} complete in ${dt}s"
    if {$checkpoint ne ""} {
        write_checkpoint -force $checkpoint
    }
}

proc p3_read_ip_dcp {cell dcp} {
    if {![file exists $dcp]} {
        puts "ERROR: missing IP DCP for ${cell}: $dcp"
        exit 1
    }
    set matches [get_cells -hier -quiet $cell]
    if {[llength $matches] != 1} {
        puts "ERROR: expected one black-box cell for ${cell}, got [llength $matches]"
        exit 1
    }
    puts "Reading IP DCP into ${cell}: $dcp"
    read_checkpoint -cell $cell $dcp
}

proc p3_find_blackbox_by_ref {ref_name} {
    set matches [get_cells -hier -quiet -filter "REF_NAME == $ref_name"]
    if {[llength $matches] != 1} {
        puts "ERROR: expected one black-box cell with REF_NAME=${ref_name}, got [llength $matches]"
        if {[llength $matches] > 0} {
            foreach cell $matches { puts "  $cell" }
        } else {
            puts "Current black-box cells:"
            foreach cell [get_cells -hier -quiet -filter {IS_BLACKBOX}] {
                set ref [get_property REF_NAME $cell]
                puts "  $cell (REF_NAME=$ref)"
            }
        }
        exit 1
    }
    return [lindex $matches 0]
}

proc p3_read_ip_dcp_by_ref {ref_name dcp} {
    if {![file exists $dcp]} {
        puts "ERROR: missing IP DCP for ${ref_name}: $dcp"
        exit 1
    }
    set cell [p3_find_blackbox_by_ref $ref_name]
    puts "Reading IP DCP into ${cell} (REF_NAME=${ref_name}): $dcp"
    read_checkpoint -cell $cell $dcp
}

proc p3_blackbox_ref_allowed {ref_name allowed_patterns} {
    foreach pattern $allowed_patterns {
        if {[string match $pattern $ref_name]} {
            return 1
        }
    }
    return 0
}

proc p3_write_ddr_io_xdc {path} {
    puts "Writing top-level DDR IO constraints: $path"
    set fh [open $path w]
    puts $fh "########################################################################"
    puts $fh "# Build 24 top-level DDR IO standards for direct checkpoint flow."
    puts $fh "# Generated by scripts/p3_build24_direct_flow.tcl."
    puts $fh "########################################################################"
    puts $fh ""
    puts $fh {set_property IOSTANDARD POD12 [get_ports {ddr4_rtl_0_dq[*]}]}
    puts $fh {set_property IOSTANDARD DIFF_POD12 [get_ports {ddr4_rtl_0_dqs_t[*] ddr4_rtl_0_dqs_c[*]}]}
    puts $fh {set_property ODT RTT_40 [get_ports {ddr4_rtl_0_dq[*] ddr4_rtl_0_dqs_t[*] ddr4_rtl_0_dqs_c[*]}]}
    puts $fh {set_property IOSTANDARD SSTL12 [get_ports {ddr4_rtl_0_adr[*] ddr4_rtl_0_act_n ddr4_rtl_0_cs_n[*] ddr4_rtl_0_ba[*] ddr4_rtl_0_bg[*] ddr4_rtl_0_cke[*] ddr4_rtl_0_odt[*]}]}
    puts $fh {set_property IOSTANDARD DIFF_SSTL12 [get_ports {ddr4_rtl_0_ck_t[*] ddr4_rtl_0_ck_c[*]}]}
    puts $fh {set_property IOSTANDARD LVCMOS12 [get_ports {ddr4_rtl_0_reset_n}]}
    puts $fh {set_property DRIVE 8 [get_ports {ddr4_rtl_0_reset_n}]}
    puts $fh {set_property IOSTANDARD SSTL12 [get_ports {ddr4_rtl_0_par}]}
    puts $fh {set_property IOSTANDARD POD12 [get_ports {ddr4_rtl_0_alert_n}]}
    puts $fh {set_property SLEW FAST [get_ports {ddr4_rtl_0_par}]}
    puts $fh {set_property OUTPUT_IMPEDANCE RDRV_40_40 [get_ports {ddr4_rtl_0_par}]}
    puts $fh {set_property IOSTANDARD POD12 [get_ports {ddr4_rtl_0_dm_n[*]}]}
    puts $fh {set_property ODT RTT_40 [get_ports {ddr4_rtl_0_dm_n[*]}]}
    puts $fh {set_property SLEW FAST [get_ports {ddr4_rtl_0_dm_n[*]}]}
    puts $fh {set_property OUTPUT_IMPEDANCE RDRV_40_40 [get_ports {ddr4_rtl_0_dm_n[*]}]}
    puts $fh {set_property EQUALIZATION EQ_LEVEL2 [get_ports {ddr4_rtl_0_dm_n[*]}]}
    puts $fh {set_property OFFSET_CNTRL CNTRL_NONE [get_ports {ddr4_rtl_0_dm_n[*]}]}
    puts $fh {set_property EQUALIZATION EQ_LEVEL2 [get_ports {ddr4_rtl_0_dq[*] ddr4_rtl_0_dqs_t[*] ddr4_rtl_0_dqs_c[*]}]}
    puts $fh {set_property OFFSET_CNTRL CNTRL_NONE [get_ports {ddr4_rtl_0_dq[*] ddr4_rtl_0_dqs_t[*] ddr4_rtl_0_dqs_c[*]}]}
    puts $fh {set_property SLEW FAST [get_ports {ddr4_rtl_0_adr[*] ddr4_rtl_0_act_n ddr4_rtl_0_cke[*] ddr4_rtl_0_cs_n[*] ddr4_rtl_0_ba[*] ddr4_rtl_0_bg[*] ddr4_rtl_0_ck_t[*] ddr4_rtl_0_ck_c[*] ddr4_rtl_0_odt[*] ddr4_rtl_0_dq[*] ddr4_rtl_0_dqs_t[*] ddr4_rtl_0_dqs_c[*]}]}
    puts $fh {set_property OUTPUT_IMPEDANCE RDRV_40_40 [get_ports {ddr4_rtl_0_adr[*] ddr4_rtl_0_act_n ddr4_rtl_0_cke[*] ddr4_rtl_0_cs_n[*] ddr4_rtl_0_ba[*] ddr4_rtl_0_bg[*] ddr4_rtl_0_ck_t[*] ddr4_rtl_0_ck_c[*] ddr4_rtl_0_odt[*] ddr4_rtl_0_dq[*] ddr4_rtl_0_dqs_t[*] ddr4_rtl_0_dqs_c[*]}]}
    close $fh
}

proc p3_force_launch_runs_jobs {jobs} {
    set ::p3_launch_runs_jobs $jobs
    if {[llength [info commands ::p3_real_launch_runs]] != 0} {
        return
    }
    if {[llength [info commands ::launch_runs]] == 0} {
        puts "WARNING: launch_runs command is unavailable; cannot force -jobs $jobs"
        return
    }

    rename ::launch_runs ::p3_real_launch_runs
    proc ::launch_runs {args} {
        set filtered_args {}
        set skip_next 0
        foreach arg $args {
            if {$skip_next} {
                set skip_next 0
                continue
            }
            if {$arg eq "-jobs"} {
                set skip_next 1
                continue
            }
            lappend filtered_args $arg
        }

        if {$::p3_launch_runs_jobs > 0} {
            lappend filtered_args -jobs $::p3_launch_runs_jobs
            puts "P3 direct flow forcing launch_runs -jobs $::p3_launch_runs_jobs: [join $filtered_args { }]"
        }
        return [uplevel 1 [list ::p3_real_launch_runs {*}$filtered_args]]
    }
}

set ddr_io_xdc "${direct_dir}/p3_top_ddr_io.xdc"
p3_write_ddr_io_xdc $ddr_io_xdc

set debug_xdc "${direct_dir}/p3_top_rtl_debug.xdc"
puts "Writing RTL debug XDC: $debug_xdc"
set fh [open $debug_xdc w]
puts $fh "########################################################################"
puts $fh "# Build 24 RTL debug ILA constraints."
puts $fh "# Generated by scripts/p3_build24_direct_flow.tcl."
puts $fh "########################################################################"
puts $fh ""
puts $fh "create_debug_core u_ila_0 ila"
puts $fh "set_property ALL_PROBE_SAME_MU true \[get_debug_cores u_ila_0\]"
puts $fh "set_property ALL_PROBE_SAME_MU_CNT 2 \[get_debug_cores u_ila_0\]"
puts $fh "set_property C_ADV_TRIGGER false \[get_debug_cores u_ila_0\]"
puts $fh "set_property C_DATA_DEPTH 4096 \[get_debug_cores u_ila_0\]"
puts $fh "set_property C_EN_STRG_QUAL true \[get_debug_cores u_ila_0\]"
puts $fh "set_property C_INPUT_PIPE_STAGES 0 \[get_debug_cores u_ila_0\]"
puts $fh "set_property C_MEMORY_TYPE 0 \[get_debug_cores u_ila_0\]"
puts $fh "set_property C_NUM_OF_PROBES 5 \[get_debug_cores u_ila_0\]"
puts $fh "set_property C_TRIGIN_EN false \[get_debug_cores u_ila_0\]"
puts $fh "set_property C_TRIGOUT_EN false \[get_debug_cores u_ila_0\]"
puts $fh "if {\[catch {connect_debug_port dbg_hub/clk \[get_nets \[list {chipset_clk} \]\]} p3_dbg_hub_clk_err\]} {"
puts $fh "    catch {connect_debug_port dbg_hub/aclk \[get_nets \[list {chipset_clk} \]\]} p3_dbg_hub_aclk_err"
puts $fh "}"
puts $fh "connect_debug_port u_ila_0/clk \[get_nets \[list {chipset_clk} \]\]"
p3_write_debug_probe $fh probe0 128 "p3_debug_bus" p3_debug_bus
p3_write_debug_probe $fh probe1 32  "p3_debug_seen" p3_debug_seen
p3_write_debug_probe $fh probe2 32  "p3_top_status" p3_top_status
p3_write_debug_probe $fh probe3 64  "dbg_m_axi_araddr" dbg_m_axi_araddr
p3_write_debug_probe $fh probe4 64  "dbg_m_axi_awaddr" dbg_m_axi_awaddr
close $fh

file copy -force $synth_dont_touch "${direct_dir}/dont_touch.xdc"
cd $direct_dir

set t0 [clock seconds]
if {$reuse_synth_dcp} {
    if {![file exists $synth_dcp]} {
        puts "ERROR: missing synthesis checkpoint for -reuse_synth: $synth_dcp"
        exit 1
    }
    puts "Opening existing synthesis checkpoint: $synth_dcp"
    if {[catch {open_checkpoint $synth_dcp} err opts]} {
        puts "ERROR: opening synthesis checkpoint failed: $err"
        puts [dict get $opts -errorinfo]
        exit 1
    }
    puts "Synthesis checkpoint open complete in [expr {[clock seconds] - $t0}]s"
} else {
    puts "Running generated synthesis Tcl in-process: $synth_tcl"
    if {[catch {source $synth_tcl} err opts]} {
        puts "ERROR: in-process synthesis failed: $err"
        puts [dict get $opts -errorinfo]
        exit 1
    }
    puts "In-process synthesis complete in [expr {[clock seconds] - $t0}]s"
}

puts "Applying implementation constraints and RTL debug core..."
read_xdc $xdc_file
read_xdc $ddr_io_xdc
source $debug_xdc

p3_read_ip_dcp_by_ref "openpiton_top_axi_noc_0_0" \
    "${project_dir}/${project_name}.runs/openpiton_top_axi_noc_0_0_synth_1/openpiton_top_axi_noc_0_0.dcp"
p3_read_ip_dcp_by_ref "openpiton_top_clk_wizard_0_0" \
    "${project_dir}/${project_name}.gen/sources_1/bd/openpiton_top/ip/openpiton_top_clk_wizard_0_0/openpiton_top_clk_wizard_0_0.dcp"
p3_read_ip_dcp_by_ref "openpiton_top_proc_sys_reset_0_0" \
    "${project_dir}/${project_name}.gen/sources_1/bd/openpiton_top/ip/openpiton_top_proc_sys_reset_0_0/openpiton_top_proc_sys_reset_0_0.dcp"
p3_read_ip_dcp_by_ref "uart_16550" \
    "${project_dir}/${project_name}.runs/uart_16550_synth_1/uart_16550.dcp"

puts "Reapplying top-level DDR IO constraints after IP DCP stitching..."
read_xdc $ddr_io_xdc

set blackboxes {}
foreach cell [get_cells -hier -quiet *] {
    if {[catch {get_property IS_BLACKBOX $cell} is_blackbox] == 0 && $is_blackbox} {
        lappend blackboxes $cell
    }
}
set allowed_blackbox_ref_patterns [list \
    axi_dbg_hub axi_dbg_hub_CV \
    axi_noc axi_noc_CV \
    ila ila_CV u_ila_*_CV \
    proc_sys_reset proc_sys_reset_CV \
]
set unexpected_blackboxes {}
if {[llength $blackboxes] != 0} {
    puts "Black boxes after IP/debug stitching:"
    foreach cell $blackboxes {
        set ref [get_property REF_NAME $cell]
        puts "  $cell (REF_NAME=$ref)"
        if {![p3_blackbox_ref_allowed $ref $allowed_blackbox_ref_patterns]} {
            lappend unexpected_blackboxes $cell
        }
    }
}
if {[llength $unexpected_blackboxes] != 0} {
    puts "ERROR: unexpected unresolved black boxes remain:"
    foreach cell $unexpected_blackboxes {
        set ref [get_property REF_NAME $cell]
        puts "  $cell (REF_NAME=$ref)"
    }
    exit 1
}

set route_dcp "${direct_dir}/p3_top_route.dcp"
set pdi_file "${output_dir}/p3_top_rtl_debug.pdi"
set ltx_file "${output_dir}/p3_top_rtl_debug.ltx"

p3_force_launch_runs_jobs 1

p3_run_step "opt_design" {opt_design} "${direct_dir}/p3_top_opt.dcp"
p3_run_step "power_opt_design" {power_opt_design} "${direct_dir}/p3_top_power_opt.dcp"
p3_run_step "place_design" {place_design} "${direct_dir}/p3_top_place.dcp"
p3_run_step "phys_opt_design" {phys_opt_design} "${direct_dir}/p3_top_phys_opt.dcp"
p3_run_step "route_design" {route_design} $route_dcp
p3_run_step "post_route_phys_opt_design" {phys_opt_design} "${direct_dir}/p3_top_post_route_phys_opt.dcp"

report_route_status -file "${direct_dir}/p3_top_route_status.rpt"
report_timing_summary -file "${direct_dir}/p3_top_timing_summary.rpt"
report_utilization -file "${direct_dir}/p3_top_utilization_impl.rpt"

puts "Writing debug probes: $ltx_file"
write_debug_probes -force $ltx_file

puts "Writing PDI: $pdi_file"
write_device_image -force $pdi_file

puts "=========================================="
puts " Build 24 direct flow complete"
puts " PDI: $pdi_file"
puts " LTX: $ltx_file"
puts " Route checkpoint: $route_dcp"
puts "=========================================="
