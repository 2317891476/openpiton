# p3_probe_build67_project.tcl -- read-only sanity check for the repo-local
# Build 67 2x1 Vivado project.

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]

if {[info exists env(P3_BUILD67_WORK_DIR)] && $env(P3_BUILD67_WORK_DIR) ne ""} {
    set project_dir [file normalize $env(P3_BUILD67_WORK_DIR)]
} else {
    set project_dir [file normalize "${repo_dir}/p3b67_2x1"]
}
set project_name "huaprop3_build67_2x1_baseline"
set bd_name "openpiton_top"
set xpr "${project_dir}/${project_name}.xpr"
set bd_file "${project_dir}/${project_name}.srcs/sources_1/bd/${bd_name}/${bd_name}.bd"

puts "=========================================="
puts " Build 67 project probe"
puts " Project: ${xpr}"
puts " BD: ${bd_file}"
puts "=========================================="

if {![file exists $xpr]} {
    puts "ERROR: missing project: ${xpr}"
    exit 1
}
if {![file exists $bd_file]} {
    puts "ERROR: missing BD: ${bd_file}"
    exit 1
}

open_project $xpr
puts "Current project: [current_project]"
puts "Top: [get_property top [current_fileset]]"
puts "Verilog defines: [get_property verilog_define [current_fileset]]"
puts "Sources count: [llength [get_files -of_objects [get_filesets sources_1]]]"
puts "Constr count: [llength [get_files -of_objects [get_filesets constrs_1]]]"
puts "Runs: [get_runs]"

open_bd_design $bd_file
puts "BD cells: [get_bd_cells]"
puts "BD ports: [get_bd_ports]"
foreach ila_cell [list axis_ila_0 axis_ila_1 axis_ila_2 axis_ila_3] {
    set cells [get_bd_cells -quiet $ila_cell]
    puts "${ila_cell}: count=[llength $cells]"
    if {[llength $cells] != 0} {
        puts "  probes=[get_property CONFIG.C_NUM_OF_PROBES $cells] depth=[get_property CONFIG.C_DATA_DEPTH $cells]"
    }
}

close_project
puts "Build 67 project probe complete."
