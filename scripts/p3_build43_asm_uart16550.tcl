# p3_build43_asm_uart16550.tcl -- Build P3 OpenPiton with a no-stack
# assembly bootrom that exercises the original Xilinx AXI UART16550 path.
#
# Usage:
#   vivado -mode batch -source scripts/p3_build43_asm_uart16550.tcl -tclargs -jobs 1
#   vivado -mode batch -source scripts/p3_build43_asm_uart16550.tcl -tclargs -skip_create -skip_prepare -reuse_synth -jobs 1
#
# By default this build uses C:/p3b43 as the Vivado work directory to avoid
# Windows 260-byte path failures in Versal debug child-IP generation. Override
# with P3_BUILD43_WORK_DIR if needed. Published PDI/LTX files still land under
# the repository's huaprop3_build43_asm_uart16550/debug_build directory.

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]
set project_name "huaprop3_build43_asm_uart16550"
set output_project_dir [file normalize "${repo_dir}/${project_name}"]
if {[info exists env(P3_BUILD43_WORK_DIR)] && $env(P3_BUILD43_WORK_DIR) ne ""} {
    set project_dir [file normalize $env(P3_BUILD43_WORK_DIR)]
} else {
    set project_dir [file normalize "C:/p3b43"]
}
set output_dir "${output_project_dir}/debug_build"
set create_tcl [file normalize "${script_dir}/p3_create_bd_build43_asm_uart16550.tcl"]
set prepare_tcl [file normalize "${script_dir}/p3_prepare_build43_uart_live_narrow_ila.tcl"]
set bootrom_rebuild_sh [file normalize "${script_dir}/p3_rebuild_build43_asm_uart16550.sh"]
set ariane_unread_impl_src [file normalize "${repo_dir}/piton/design/xilinx/huaprop3/unread_vivado_impl.sv"]
set synth_run "synth_1"
set impl_run "impl_1"
set pdi_basename "p3_top_build43_asm_uart16550"
set run_create 1
set run_prepare 1
set reuse_synth 0
set jobs 1

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    switch -- $arg {
        -skip_create {
            set run_create 0
        }
        -skip_prepare {
            set run_prepare 0
        }
        -reuse_synth {
            set reuse_synth 1
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

proc p3_dir_has_files {dir required_files} {
    foreach required_file $required_files {
        if {![file exists "${dir}/${required_file}"]} {
            return 0
        }
    }
    return 1
}

proc p3_unique_dir_append {var_name dir} {
    upvar 1 $var_name dirs
    if {$dir eq ""} {
        return
    }
    if {[lsearch -exact $dirs $dir] < 0} {
        lappend dirs $dir
    }
}

proc p3_seed_project_ip_cache {label project_dir project_name repo_dir cache_rel required_files} {
    set project_cache_dir "${project_dir}/${project_name}.cache/ip/${cache_rel}"
    set candidate_dirs {}

    p3_unique_dir_append candidate_dirs $project_cache_dir
    p3_unique_dir_append candidate_dirs "${repo_dir}/.cache/ip/${cache_rel}"
    p3_unique_dir_append candidate_dirs "${repo_dir}/huaprop3_build42a_asm_uart/huaprop3_build42a_asm_uart.cache/ip/${cache_rel}"
    p3_unique_dir_append candidate_dirs "${repo_dir}/huaprop3_build42b_bram_stack/huaprop3_build42b_bram_stack.cache/ip/${cache_rel}"
    p3_unique_dir_append candidate_dirs "${repo_dir}/huaprop3_build41_debug/huaprop3_build41_debug.cache/ip/${cache_rel}"
    p3_unique_dir_append candidate_dirs "${repo_dir}/huaprop3_openpiton/huaprop3_openpiton.cache/ip/${cache_rel}"

    set source_cache_dir ""
    foreach dir $candidate_dirs {
        if {[p3_dir_has_files $dir $required_files]} {
            set source_cache_dir $dir
            break
        }
    }

    if {$source_cache_dir eq ""} {
        puts "WARNING: ${label} IP cache ${cache_rel} not found; implementation may regenerate this child IP."
        puts "         Expected cache files:"
        foreach required_file $required_files {
            puts "           ${required_file}"
        }
        return 0
    }

    if {$source_cache_dir ne $project_cache_dir} {
        puts "Seeding ${label} IP cache:"
        puts "  source: $source_cache_dir"
        puts "  target: $project_cache_dir"
        file mkdir [file dirname $project_cache_dir]
        file delete -force $project_cache_dir
        file copy -force $source_cache_dir $project_cache_dir
    } else {
        puts "${label} IP cache already present: $project_cache_dir"
    }

    return 1
}

proc p3_seed_build43_impl_caches {project_dir project_name repo_dir} {
    p3_seed_project_ip_cache "DDR PHY" $project_dir $project_name $repo_dir \
        "2024.2.2/f/1/f19a7ef233cf09e1" \
        [list bd_c5b9_MC0_ddrc_0_phy.dcp f19a7ef233cf09e1.xci]

    if {[catch {current_project} current_project_name] == 0 && $current_project_name ne ""} {
        set project_ip_repo "${project_dir}/${project_name}.cache/ip"
        puts "Using project IP output repo for implementation child IP cache: $project_ip_repo"
        set_property ip_output_repo $project_ip_repo [current_project]
        set_property ip_cache_permissions {read write} [current_project]
    }

    foreach param [list synth.maxThreads synth.maxClusterJobsRunCount] {
        if {[catch {get_param $param} old_value] == 0} {
            puts "Build 43 setting ${param} from ${old_value} to 1 for implementation child IP generation."
            catch {set_param $param 1}
        }
    }
}

proc p3_set_run_property_if_present {run prop value} {
    if {[lsearch -exact [list_property $run] $prop] >= 0} {
        set_property $prop $value $run
        puts "  $prop = [get_property $prop $run]"
    }
}

proc p3_disable_synth_incremental {run_name project_dir project_name} {
    set synth_run [get_runs $run_name]
    puts "Disabling stale incremental synthesis for ${run_name}..."
    p3_set_run_property_if_present $synth_run AUTO_INCREMENTAL_CHECKPOINT 0
    p3_set_run_property_if_present $synth_run INCREMENTAL_CHECKPOINT ""
    p3_set_run_property_if_present $synth_run AUTO_INCREMENTAL_DIR ""

    set imported_dcp [file normalize "${project_dir}/${project_name}.srcs/utils_1/imports/${run_name}/p3_top.dcp"]
    set imported_dcp_file [get_files -quiet $imported_dcp]
    if {$imported_dcp_file ne ""} {
        puts "  removing imported incremental checkpoint from project: $imported_dcp"
        remove_files $imported_dcp_file
    }
}

proc p3_use_ariane_unread_vivado_shim {shim_src} {
    if {![file exists $shim_src]} {
        puts "ERROR: missing Vivado unread implementation shim: $shim_src"
        exit 1
    }
    foreach old_unread [get_files -quiet *common_cells/src/unread.sv] {
        remove_files $old_unread
    }
    foreach old_unread_impl [get_files -quiet *unread_vivado_impl.sv] {
        remove_files $old_unread_impl
    }
    add_files -fileset sources_1 -norecurse $shim_src
    set_property file_type "SystemVerilog" [get_files $shim_src]
    puts "Using Vivado unread implementation shim: $shim_src"
}

proc p3_to_wsl_path {path} {
    set norm [string map {"\\" "/"} $path]
    if {[regexp {^[A-Za-z]:/(home/.*)$} $norm -> rest]} {
        return "/$rest"
    }
    if {[regexp {^//wsl\.localhost/[^/]+(/.*)$} $norm -> rest]} {
        return $rest
    }
    if {[regexp {^//wsl\$/[^/]+(/.*)$} $norm -> rest]} {
        return $rest
    }
    return $norm
}

proc p3_copy_run_output {run_dir output_dir pdi_basename} {
    set pdi_src [p3_find_latest_file $run_dir "*.pdi"]
    set ltx_src [p3_find_latest_file $run_dir "*.ltx"]
    if {$pdi_src eq "" || $ltx_src eq ""} {
        puts "ERROR: missing PDI or LTX in ${run_dir}"
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
        "p3_dbg_uart_seen16_i" \
        "p3_dbg_uart_bus64_i" \
    ] {
        if {[string first $token $ltx_data] < 0} {
            puts "ERROR: Build 43 LTX missing token: ${token}"
            exit 1
        }
    }

    file mkdir $output_dir
    set pdi_dst "${output_dir}/${pdi_basename}.pdi"
    set ltx_dst "${output_dir}/${pdi_basename}.ltx"
    file copy -force $pdi_src $pdi_dst
    file copy -force $ltx_src $ltx_dst
    puts "Published Build 43 PDI: ${pdi_dst}"
    puts "Published Build 43 LTX: ${ltx_dst}"
}

puts "=========================================="
puts " Build 43: P3 no-stack AXI16550 ASM UART"
puts " Work project: ${project_dir}/${project_name}.xpr"
puts " Output dir: ${output_dir}"
puts " Jobs: ${jobs}"
puts " Reuse synth: ${reuse_synth}"
puts " Prepare BD/ILA: ${run_prepare}"
puts "=========================================="

if {![file exists $bootrom_rebuild_sh]} {
    puts "ERROR: missing Build 43 bootrom rebuild script: $bootrom_rebuild_sh"
    exit 1
}
puts "Regenerating Build 43 bootrom before Vivado project creation..."
set bootrom_rebuild_exec_path [p3_to_wsl_path $bootrom_rebuild_sh]
puts "Bootrom rebuild script path for bash: ${bootrom_rebuild_exec_path}"
if {[catch {exec bash $bootrom_rebuild_exec_path 2>@1} bootrom_rebuild_log]} {
    puts $bootrom_rebuild_log
    puts "ERROR: Build 43 bootrom regeneration failed"
    exit 1
}
puts $bootrom_rebuild_log

if {$run_create} {
    set P3_PROJECT_NAME $project_name
    set P3_PROJECT_DIR $project_dir
    source $create_tcl
} else {
    puts "Skipping project creation step."
}

if {$run_prepare} {
    set P3_PROJECT_NAME $project_name
    set P3_PROJECT_DIR $project_dir
    source $prepare_tcl
} else {
    puts "Skipping Build 43 prepare step."
}

open_project "${project_dir}/${project_name}.xpr"

set defs [get_property verilog_define [current_fileset]]
set cleaned_defs {}
foreach define $defs {
    if {$define ne "P3_SIFIVE_UART" &&
        $define ne "P3_BD_SIFIVE_DEBUG_ILA" &&
        $define ne "P3_SIFIVE_UART_DEBUG_ILA" &&
        $define ne "P3_BD_UART_RAW_DEBUG_ILA" &&
        $define ne "P3_BD_BUILD41_DEBUG_ILA" &&
        $define ne "P3_BD_UART_WR_DEBUG_ILA" &&
        $define ne "P3_BD_UART_WR_NARROW_DEBUG_ILA"} {
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

if {[lsearch -exact $defs "P3_SIFIVE_UART"] >= 0 ||
    [lsearch -exact $defs "P3_SIFIVE_UART_DEBUG_ILA"] >= 0} {
    puts "ERROR: Build 43 must not enable SiFive UART macros"
    exit 1
}

p3_use_ariane_unread_vivado_shim $ariane_unread_impl_src
update_compile_order -fileset sources_1

if {$reuse_synth && $run_prepare} {
    puts "ERROR: -reuse_synth requires -skip_prepare because prepare regenerates synth_1 scripts and resets the run."
    exit 1
}

if {$reuse_synth} {
    set synth_progress [get_property PROGRESS [get_runs $synth_run]]
    puts "Reusing existing synthesis run ${synth_run}; progress=${synth_progress}"
    if {$synth_progress ne "100%"} {
        puts "ERROR: ${synth_run} is not complete; rerun without -reuse_synth."
        exit 1
    }
    p3_runmgr_check_status $synth_run "Synthesis"
} else {
    reset_run $synth_run
    p3_disable_synth_incremental $synth_run $project_dir $project_name
    launch_runs $synth_run -jobs $jobs
    wait_on_run $synth_run
    p3_runmgr_check_status $synth_run "Synthesis"
}

p3_seed_build43_impl_caches $project_dir $project_name $repo_dir

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
puts " Build 43 no-stack AXI16550 ASM UART flow complete"
puts "=========================================="
