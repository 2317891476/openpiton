# p3_build41_fetch_debug.tcl -- Build P3 OpenPiton for Build 41
# and narrow transaction-level debug ILAs for fetch/bootrom debug.
#
# Usage:
#   vivado -mode batch -source scripts/p3_build41_fetch_debug.tcl -tclargs -jobs 1

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]
set project_name "huaprop3_build41_debug"
set project_dir [file normalize "${repo_dir}/${project_name}"]
set output_dir "${project_dir}/debug_build"
set create_tcl [file normalize "${script_dir}/p3_create_bd_build41.tcl"]
set synth_run "synth_1"
set impl_run "impl_1"
set pdi_basename "p3_top_build41_fetch_debug"
set run_create 1
set jobs 1

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    switch -- $arg {
        -skip_create {
            set run_create 0
        }
        -jobs {
            incr i
            if {$i >= [llength $argv]} {
                puts "ERROR: -jobs requires a value"
                exit 1
            }
            set jobs [lindex $argv $i]
        }
        default {
            puts "ERROR: unknown argument: $arg"
            exit 1
        }
    }
}

proc p3_runmgr_check_status {run_name phase} {
    set status [get_property STATUS [get_runs $run_name]]
    puts "${phase} status for ${run_name}: ${status}"
    if {[string match -nocase "*fail*" $status] ||
        [string match -nocase "*error*" $status] ||
        ![string match "*Complete*" $status]} {
        puts "ERROR: ${phase} did not complete successfully"
        exit 1
    }
}

proc p3_find_latest_file {dir pattern} {
    set files [glob -nocomplain -directory $dir $pattern]
    if {[llength $files] == 0} {
        return ""
    }
    set best [lindex $files 0]
    foreach file $files {
        if {[file mtime $file] > [file mtime $best]} {
            set best $file
        }
    }
    return $best
}

proc p3_copy_run_output {run_dir output_dir pdi_basename} {
    set pdi_src [p3_find_latest_file $run_dir "*.pdi"]
    set ltx_src [p3_find_latest_file $run_dir "*.ltx"]
    if {$pdi_src eq ""} {
        puts "ERROR: missing PDI in ${run_dir}"
        exit 1
    }
    if {$ltx_src eq ""} {
        puts "ERROR: missing LTX in ${run_dir}"
        exit 1
    }

    set fh [open $ltx_src r]
    set ltx_data [read $fh]
    close $fh
    foreach token [list \
        "0x000003FFC0000000" \
        "PMC_AXI_NOC0" \
        "axis_ila_0" \
        "axis_ila_1" \
        "axis_ila_2" \
        "p3_dbg_uart_seen16_i" \
        "p3_dbg_chip_seen16_i" \
        "p3_dbg_b41_core_bus64_i" \
        "p3_dbg_b41_chipset_bus64_i" \
    ] {
        if {[string first $token $ltx_data] < 0} {
            puts "ERROR: Build 41 LTX missing token: ${token}"
            exit 1
        }
    }

    file mkdir $output_dir
    set pdi_dst "${output_dir}/${pdi_basename}.pdi"
    set ltx_dst "${output_dir}/${pdi_basename}.ltx"
    file copy -force $pdi_src $pdi_dst
    file copy -force $ltx_src $ltx_dst
    puts "Published Build 41 PDI: ${pdi_dst}"
    puts "Published Build 41 LTX: ${ltx_dst}"
}

puts "=========================================="
puts " Build 41: P3 Fetch debug ILAs"
puts " Project: ${project_dir}/${project_name}.xpr"
puts " Jobs: ${jobs}"
puts "=========================================="

if {$run_create} {
    source $create_tcl
} else {
    puts "Skipping project creation step."
}

open_project "${project_dir}/${project_name}.xpr"

set defs [get_property verilog_define [current_fileset]]
set cleaned_defs {}
foreach define $defs {
    if {$define ne "PITON_UART16550" &&
        $define ne "P3_BD_UART_DEBUG_ILA" &&
        $define ne "P3_BD_SIFIVE_DEBUG_ILA" &&
        $define ne "P3_SIFIVE_UART_DEBUG_ILA"} {
        lappend cleaned_defs $define
    }
}
set defs $cleaned_defs
foreach required_define [list \
    P3_SIFIVE_UART \
    P3_RTL_DEBUG \
    P3_BD_BUILD41_DEBUG_ILA \
    P3_SIFIVE_UART_DEBUG_ILA \
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

reset_run $synth_run
launch_runs $synth_run -jobs $jobs
wait_on_run $synth_run
p3_runmgr_check_status $synth_run "Synthesis"

reset_run $impl_run
launch_runs $impl_run -to_step write_device_image -jobs $jobs
wait_on_run $impl_run
p3_runmgr_check_status $impl_run "Implementation"

set run_dir [get_property DIRECTORY [get_runs $impl_run]]
if {$run_dir eq ""} {
    set run_dir "${project_dir}/${project_name}.runs/${impl_run}"
}
p3_copy_run_output $run_dir $output_dir $pdi_basename

close_project
puts "=========================================="
puts " Build 41 Fetch debug flow complete"
puts "=========================================="
