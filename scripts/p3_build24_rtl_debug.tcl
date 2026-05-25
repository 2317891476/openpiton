# p3_build24_rtl_debug.tcl -- RTL-exported Ariane/OpenPiton debug bus + ILA.
# Usage: vivado -mode batch -source scripts/p3_build24_rtl_debug.tcl

set project_dir [file normalize "/home/illya/openpiton/huaprop3_openpiton"]
set project_name "huaprop3_openpiton"
set repo_root "Z:/home/illya/openpiton"
set tmp_dir "Z:/tmp"
set xdc_file "${tmp_dir}/huaprop3_constraints.xdc"
set output_dir "${project_dir}/debug_build"

puts "=========================================="
puts " Build 24: RTL-level P3 Ariane debug"
puts "=========================================="

file mkdir $tmp_dir
file mkdir $output_dir

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

foreach generated [list \
    "${repo_root}/piton/design/chip/rtl/chip.tmp.v" \
    "${repo_root}/piton/design/chip/tile/rtl/tile.tmp.v" \
    "${repo_root}/piton/design/chipset/rtl/chipset_impl.tmp.v" \
] {
    if {![file exists $generated]} {
        puts "ERROR: missing generated RTL: $generated"
        puts "Run pyhp.py on the corresponding .v.pyv templates before this build."
        exit 1
    }
}

set ariane_unread_src "${repo_root}/piton/design/chip/tile/ariane/common/submodules/common_cells/src/unread.sv"
if {![file exists $ariane_unread_src]} {
    puts "ERROR: missing Ariane common_cells source: $ariane_unread_src"
    exit 1
}

open_project "${project_dir}/${project_name}.xpr"

proc set_run_property_if_present {run prop value} {
    if {[lsearch -exact [list_property $run] $prop] >= 0} {
        if {[catch {set_property $prop $value $run} err]} {
            puts "ERROR: could not set $prop on $run to '$value': $err"
            exit 1
        }
        puts "  $prop = [get_property $prop $run]"
    }
}

proc disable_synth_incremental {run_name project_dir project_name} {
    set synth_run [get_runs $run_name]
    puts "Disabling stale incremental synthesis for ${run_name}..."
    set_run_property_if_present $synth_run AUTO_INCREMENTAL_CHECKPOINT 0
    set_run_property_if_present $synth_run INCREMENTAL_CHECKPOINT ""
    set_run_property_if_present $synth_run AUTO_INCREMENTAL_DIR ""

    set imported_dcp [file normalize "${project_dir}/${project_name}.srcs/utils_1/imports/${run_name}/p3_top.dcp"]
    set imported_dcp_file [get_files -quiet $imported_dcp]
    if {$imported_dcp_file ne ""} {
        puts "  removing imported incremental checkpoint from project: $imported_dcp"
        remove_files $imported_dcp_file
    }
}

disable_synth_incremental synth_1 $project_dir $project_name

set defs [get_property verilog_define [current_fileset]]
foreach required_define [list \
    P3_RTL_DEBUG \
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

# Swap XDC and the top-level files that previously suffered from stale /tmp copies.
set old_xdc [get_files -quiet *constraints.xdc]
if {$old_xdc ne ""} { remove_files $old_xdc }
set stale_debug_xdc [get_files -quiet -of_objects [get_filesets constrs_1] *debug*]
if {$stale_debug_xdc ne ""} { remove_files $stale_debug_xdc }
add_files -fileset constrs_1 -norecurse $xdc_file

set old_top [get_files -quiet *p3_top.v]
if {$old_top ne ""} { remove_files $old_top }
add_files -fileset sources_1 -norecurse "${tmp_dir}/p3_top.v"
set_property file_type "Verilog" [get_files "${tmp_dir}/p3_top.v"]

set old_wrap [get_files -quiet *openpiton_wrapper.v]
if {$old_wrap ne ""} { remove_files $old_wrap }
add_files -fileset sources_1 -norecurse "${tmp_dir}/openpiton_wrapper.v"
set_property file_type "Verilog" [get_files "${tmp_dir}/openpiton_wrapper.v"]

set old_sys [get_files -quiet *system.v]
if {$old_sys ne ""} { remove_files $old_sys }
add_files -fileset sources_1 -norecurse "${tmp_dir}/system.v"
set_property file_type "Verilog" [get_files "${tmp_dir}/system.v"]

set old_vh [get_files -quiet *piton_system.vh]
if {$old_vh ne ""} { remove_files $old_vh }
add_files -fileset sources_1 -norecurse "${tmp_dir}/piton_system.vh"
set_property file_type "Verilog Header" [get_files "${tmp_dir}/piton_system.vh"]
set_property is_global_include true [get_files "${tmp_dir}/piton_system.vh"]

# Vivado can otherwise synthesize Ariane's unread instances as black boxes and
# fail later at opt_design with DRC INBB-3.
set old_unread [get_files -quiet *common_cells/src/unread.sv]
if {$old_unread eq ""} {
    add_files -fileset sources_1 -norecurse $ariane_unread_src
}
set_property file_type "SystemVerilog" [get_files $ariane_unread_src]

update_compile_order -fileset sources_1

catch {reset_run impl_1}
catch {reset_run synth_1}
disable_synth_incremental synth_1 $project_dir $project_name

puts "Launching synthesis..."
launch_runs synth_1 -jobs 8
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "Synthesis Status: $synth_status"
if {[string match "*fail*" [string tolower $synth_status]]} {
    puts "ERROR: Synthesis failed!"
    close_project
    exit 1
}

proc get_one_net {net_name} {
    set direct [get_nets -quiet $net_name]
    if {[llength $direct] == 1} {
        return [lindex $direct 0]
    }
    if {[llength $direct] > 1} {
        puts "ERROR: ambiguous top-level net ${net_name}: [llength $direct] matches"
        return ""
    }

    set found [get_nets -quiet -hier $net_name]
    if {[llength $found] == 1} {
        return [lindex $found 0]
    }
    if {[llength $found] == 0} {
        puts "ERROR: missing net ${net_name}"
        return ""
    }

    puts "ERROR: ambiguous hierarchical net ${net_name}: [llength $found] matches"
    foreach candidate [lrange $found 0 20] {
        puts "  candidate: [get_property NAME $candidate]"
    }
    if {[llength $found] > 20} {
        puts "  ..."
    }
    return ""
}

proc get_debug_bus_nets {base width} {
    set nets {}
    for {set i 0} {$i < $width} {incr i} {
        set net_name "${base}\[$i\]"
        set found [get_one_net $net_name]
        if {$found eq ""} {
            return {}
        }
        lappend nets $found
    }
    return $nets
}

proc connect_probe_bus {ila port width label base} {
    if {$port ne "probe0"} {
        create_debug_port $ila probe
    }
    set dbg_port [get_debug_ports ${ila}/${port}]
    set_property port_width $width $dbg_port
    set nets [get_debug_bus_nets $base $width]
    puts "  ${port}: ${label} (${base}\\[${width}-1:0\\])"
    if {[llength $nets] != $width} {
        puts "ERROR: expected $width nets for ${base}, got [llength $nets]"
        exit 1
    }
    connect_debug_port $dbg_port $nets
}

puts "Opening synthesized design..."
open_run synth_1 -name synth_1

puts "Creating ILA debug core..."
create_debug_core u_ila_0 ila
set_property C_DATA_DEPTH 4096 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 2 [get_debug_cores u_ila_0]

puts "Connecting ILA clock..."
set ila_clk_net [get_one_net chipset_clk]
if {$ila_clk_net eq ""} {
    puts "ERROR: could not resolve a single ILA clock net"
    exit 1
}
puts "  clk: [get_property NAME $ila_clk_net]"
connect_debug_port u_ila_0/clk $ila_clk_net

puts "Adding RTL debug probes..."
connect_probe_bus u_ila_0 probe0 128 "p3_debug_bus" p3_debug_bus
connect_probe_bus u_ila_0 probe1 32  "p3_debug_seen" p3_debug_seen
connect_probe_bus u_ila_0 probe2 32  "p3_top_status" p3_top_status
connect_probe_bus u_ila_0 probe3 64  "dbg_m_axi_araddr" dbg_m_axi_araddr
connect_probe_bus u_ila_0 probe4 64  "dbg_m_axi_awaddr" dbg_m_axi_awaddr

puts "Saving debug constraints..."
catch {write_debug_probes -force ${output_dir}/p3_top_rtl_debug.ltx}
save_constraints -force
close_design

puts "Launching implementation and PDI generation..."
catch {reset_run impl_1}
launch_runs impl_1 -to_step write_device_image -jobs 8
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]
puts "Implementation Status: $impl_status"
puts "Implementation Progress: $impl_progress"
if {$impl_progress != "100%"} {
    puts "ERROR: Implementation did not complete!"
    close_project
    exit 1
}

set impl_dir "${project_dir}/${project_name}.runs/impl_1"
if {[file exists "${impl_dir}/p3_top.pdi"]} {
    file copy -force "${impl_dir}/p3_top.pdi" "${output_dir}/p3_top_rtl_debug.pdi"
    puts "PDI: ${output_dir}/p3_top_rtl_debug.pdi"
} else {
    puts "ERROR: PDI not found in ${impl_dir}"
    close_project
    exit 1
}

if {[file exists "${impl_dir}/p3_top.ltx"]} {
    file copy -force "${impl_dir}/p3_top.ltx" "${output_dir}/p3_top_rtl_debug.ltx"
    puts "LTX: ${output_dir}/p3_top_rtl_debug.ltx"
}

close_project
puts "=========================================="
puts " Build 24 complete"
puts "=========================================="
