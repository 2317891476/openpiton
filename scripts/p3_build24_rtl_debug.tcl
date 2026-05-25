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

set ariane_unread_impl_src "${repo_root}/piton/design/xilinx/huaprop3/unread_vivado_impl.sv"
if {![file exists $ariane_unread_impl_src]} {
    puts "ERROR: missing Vivado unread implementation shim: $ariane_unread_impl_src"
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

# Vivado treats Ariane/common_cells' intentionally empty unread module as a
# black box in this project. Use a tiny real LUT sink for implementation.
foreach old_unread [get_files -quiet *common_cells/src/unread.sv] {
    remove_files $old_unread
}
foreach old_unread_impl [get_files -quiet *unread_vivado_impl.sv] {
    remove_files $old_unread_impl
}
add_files -fileset sources_1 -norecurse $ariane_unread_impl_src
set_property file_type "SystemVerilog" [get_files $ariane_unread_impl_src]

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

set debug_xdc_dir "${project_dir}/${project_name}.srcs/constrs_1/imports"
file mkdir $debug_xdc_dir
set debug_xdc "${debug_xdc_dir}/p3_top_rtl_debug.xdc"
puts "Writing RTL debug XDC: $debug_xdc"
set fh [open $debug_xdc w]
puts $fh "########################################################################"
puts $fh "# Build 24 RTL debug ILA constraints."
puts $fh "# Generated by scripts/p3_build24_rtl_debug.tcl."
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
puts $fh "connect_debug_port u_ila_0/clk \[get_nets \[list {chipset_clk} \]\]"
p3_write_debug_probe $fh probe0 128 "p3_debug_bus" p3_debug_bus
p3_write_debug_probe $fh probe1 32  "p3_debug_seen" p3_debug_seen
p3_write_debug_probe $fh probe2 32  "p3_top_status" p3_top_status
p3_write_debug_probe $fh probe3 64  "dbg_m_axi_araddr" dbg_m_axi_araddr
p3_write_debug_probe $fh probe4 64  "dbg_m_axi_awaddr" dbg_m_axi_awaddr
close $fh

add_files -fileset constrs_1 -norecurse $debug_xdc
set_property used_in_synthesis false [get_files $debug_xdc]
set_property used_in_implementation true [get_files $debug_xdc]

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
