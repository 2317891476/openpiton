# p3_build52_sd_cd_mask.tcl -- Build P3 OpenPiton with the no-stack
# AXI16550 UART + direct SD read bootrom and four small BD-owned ILAs.
#
# Usage:
#   vivado -mode batch -source scripts/p3_build52_sd_cd_mask.tcl -tclargs -jobs 1
#   vivado -mode batch -source scripts/p3_build52_sd_cd_mask.tcl -tclargs -skip_create -skip_prepare -reuse_synth -jobs 1
#
# By default this build uses D:/p3b52 as the Vivado work directory to avoid
# Windows 260-byte path failures in Versal debug child-IP generation. Override
# with P3_BUILD52_WORK_DIR if needed. Published PDI/LTX files still land under
# the repository's huaprop3_build52_sd_cd_mask/debug_build directory.

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]

proc p3_default_env {name value} {
    if {![info exists ::env($name)] || $::env($name) eq ""} {
        set ::env($name) $value
    }
}

proc p3_bool {value} {
    set value_lc [string tolower [string trim $value]]
    return [expr {$value_lc eq "1" || $value_lc eq "true" || $value_lc eq "yes" || $value_lc eq "on"}]
}

p3_default_env PITON_X_TILES 1
p3_default_env PITON_Y_TILES 1
if {![info exists ::env(PITON_NUM_TILES)] || $::env(PITON_NUM_TILES) eq ""} {
    set ::env(PITON_NUM_TILES) [expr {$::env(PITON_X_TILES) * $::env(PITON_Y_TILES)}]
}
foreach tile_env [list PITON_X_TILES PITON_Y_TILES PITON_NUM_TILES] {
    if {![string is integer -strict $::env($tile_env)] || $::env($tile_env) < 1} {
        puts "ERROR: ${tile_env} must be a positive integer, got '$::env($tile_env)'"
        exit 1
    }
}
set p3_expected_num_tiles [expr {$::env(PITON_X_TILES) * $::env(PITON_Y_TILES)}]
if {$::env(PITON_NUM_TILES) != $p3_expected_num_tiles} {
    puts "ERROR: PITON_NUM_TILES=$::env(PITON_NUM_TILES) does not match PITON_X_TILES*PITON_Y_TILES=${p3_expected_num_tiles}"
    exit 1
}

if {[info exists env(P3_BUILD52_PROJECT_NAME)] && $env(P3_BUILD52_PROJECT_NAME) ne ""} {
    set project_name $env(P3_BUILD52_PROJECT_NAME)
} else {
    set project_name "huaprop3_build52_sd_cd_mask"
}
set output_project_dir [file normalize "${repo_dir}/${project_name}"]
if {[info exists env(P3_BUILD52_WORK_DIR)] && $env(P3_BUILD52_WORK_DIR) ne ""} {
    set project_dir [file normalize $env(P3_BUILD52_WORK_DIR)]
} else {
    set project_dir [file normalize "D:/p3b52"]
}
set output_dir "${output_project_dir}/debug_build"
set create_tcl [file normalize "${script_dir}/p3_create_bd_build52_sd_cd_mask.tcl"]
set prepare_tcl [file normalize "${script_dir}/p3_prepare_build52_sd_cd_mask_ila.tcl"]
set post_synth_tcl ""
if {[info exists env(P3_BUILD52_POST_SYNTH_TCL)] && $env(P3_BUILD52_POST_SYNTH_TCL) ne ""} {
    set post_synth_tcl [file normalize $env(P3_BUILD52_POST_SYNTH_TCL)]
}
if {[info exists env(P3_BUILD52_BOOTROM_REBUILD_SH)] && $env(P3_BUILD52_BOOTROM_REBUILD_SH) ne ""} {
    set bootrom_rebuild_sh [file normalize $env(P3_BUILD52_BOOTROM_REBUILD_SH)]
} else {
    set bootrom_rebuild_sh [file normalize "${script_dir}/p3_rebuild_build52_sd_cd_mask.sh"]
}
set ariane_unread_impl_src [file normalize "${repo_dir}/piton/design/xilinx/huaprop3/unread_vivado_impl.sv"]
set synth_run "synth_1"
set impl_run "impl_1"
if {[info exists env(P3_BUILD52_PDI_BASENAME)] && $env(P3_BUILD52_PDI_BASENAME) ne ""} {
    set pdi_basename $env(P3_BUILD52_PDI_BASENAME)
} else {
    set pdi_basename "p3_top_build52_sd_cd_mask"
}
set p3_extra_defines {}
if {[info exists env(P3_BUILD52_EXTRA_DEFINES)] && $env(P3_BUILD52_EXTRA_DEFINES) ne ""} {
    set p3_extra_defines [split $env(P3_BUILD52_EXTRA_DEFINES)]
}
if {[info exists env(P3_SELF_CONTAINED_SOURCES)] && $env(P3_SELF_CONTAINED_SOURCES) ne ""} {
    set p3_self_contained_sources [p3_bool $env(P3_SELF_CONTAINED_SOURCES)]
} else {
    set p3_self_contained_sources 0
}
set run_create 1
set run_prepare 1
set reuse_synth 0
if {[info exists env(P3_BUILD52_DEFAULT_JOBS)] && $env(P3_BUILD52_DEFAULT_JOBS) ne ""} {
    set jobs $env(P3_BUILD52_DEFAULT_JOBS)
} else {
    set jobs 1
}

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
if {![string is integer -strict $jobs] || $jobs < 1} {
    puts "ERROR: -jobs must be a positive integer, got '$jobs'"
    exit 1
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
    p3_unique_dir_append candidate_dirs "${repo_dir}/huaprop3_build59_spi_sd_mosi_idle_high/huaprop3_build59_spi_sd_mosi_idle_high.cache/ip/${cache_rel}"
    p3_unique_dir_append candidate_dirs "${repo_dir}/huaprop3_openpiton/huaprop3_openpiton.cache/ip/${cache_rel}"
    p3_unique_dir_append candidate_dirs "${repo_dir}/p3b66_validated_snapshot/huaprop3_build66_normal_spi_sd_boot.cache/ip/${cache_rel}"
    p3_unique_dir_append candidate_dirs "D:/p3b59/huaprop3_build59_spi_sd_mosi_idle_high.cache/ip/${cache_rel}"
    p3_unique_dir_append candidate_dirs "D:/p3b66/huaprop3_build66_normal_spi_sd_boot.cache/ip/${cache_rel}"
    p3_unique_dir_append candidate_dirs "D:/p3_cleanup_archive/2026-06-04-build66-baseline/workspaces/p3b59/huaprop3_build59_spi_sd_mosi_idle_high.cache/ip/${cache_rel}"

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

proc p3_seed_build52_impl_caches {project_dir project_name repo_dir} {
    p3_seed_project_ip_cache "DDR PHY" $project_dir $project_name $repo_dir \
        "2024.2.2/f/1/f19a7ef233cf09e1" \
        [list bd_c5b9_MC0_ddrc_0_phy.dcp f19a7ef233cf09e1.xci]

    p3_seed_project_ip_cache "DDR PHY Build 59 generated" $project_dir $project_name $repo_dir \
        "2024.2.2/d/d/dddc3f069a736d89" \
        [list bd_c5b9_MC0_ddrc_0_phy.dcp dddc3f069a736d89.xci]

    if {[catch {current_project} current_project_name] == 0 && $current_project_name ne ""} {
        set project_ip_repo "${project_dir}/${project_name}.cache/ip"
        puts "Using project IP output repo for implementation child IP cache: $project_ip_repo"
        set_property ip_output_repo $project_ip_repo [current_project]
        set_property ip_cache_permissions {read write} [current_project]
    }

    foreach param [list synth.maxThreads synth.maxClusterJobsRunCount] {
        if {[catch {get_param $param} old_value] == 0} {
            puts "Build 52 setting ${param} from ${old_value} to 1 for implementation child IP generation."
            catch {set_param $param 1}
        }
    }
}

proc p3_set_vivado_thread_params {threads phase} {
    foreach param [list general.maxThreads synth.maxThreads] {
        if {[catch {get_param $param} old_value] == 0} {
            if {$old_value ne $threads} {
                puts "Setting ${param} from ${old_value} to ${threads} for ${phase}."
            } else {
                puts "${param} already ${threads} for ${phase}."
            }
            if {[catch {set_param $param $threads} err]} {
                puts "WARNING: failed to set ${param}=${threads}: $err"
            }
        } else {
            puts "WARNING: Vivado parameter ${param} is unavailable; cannot set it to ${threads}"
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

proc p3_slash_path {path} {
    return [string map {"\\" "/"} [file normalize $path]]
}

proc p3_self_contained_forbidden_patterns {repo_dir} {
    set repo_path [p3_slash_path $repo_dir]
    return [list \
        "\$PPRDIR/../piton/" \
        "${repo_path}/piton/" \
        "Z:/tmp" \
        "D:/p3b" \
        "/mnt/d/p3b" \
    ]
}

proc p3_validate_self_contained_xpr {project_dir project_name repo_dir} {
    set xpr_file "${project_dir}/${project_name}.xpr"
    if {![file exists $xpr_file]} {
        puts "ERROR: self-contained validation cannot find XPR: ${xpr_file}"
        exit 1
    }

    set fh [open $xpr_file r]
    set data [read $fh]
    close $fh

    foreach pattern [p3_self_contained_forbidden_patterns $repo_dir] {
        if {[string first $pattern $data] >= 0} {
            puts "ERROR: self-contained project XPR contains forbidden live-source path pattern: ${pattern}"
            puts "       XPR: ${xpr_file}"
            exit 1
        }
    }

    set snapshot_dir "${project_dir}/source_snapshot"
    foreach required_rel [list \
        "piton/design/xilinx/huaprop3/p3_top.v" \
        "piton/design/xilinx/huaprop3/openpiton_wrapper.v" \
        "piton/design/xilinx/huaprop3/constraints.xdc" \
        "piton/design/xilinx/huaprop3/unread_vivado_impl.sv" \
        "piton/design/chipset/rv64_platform/bootrom/baremetal/bootrom.sv" \
        "piton/design/chipset/rv64_platform/bootrom/linux/bootrom_linux.sv" \
    ] {
        set required_path "${snapshot_dir}/${required_rel}"
        if {![file exists $required_path]} {
            puts "ERROR: self-contained source snapshot missing required file: ${required_path}"
            exit 1
        }
    }

    puts "Self-contained XPR path validation passed: ${xpr_file}"
}

proc p3_validate_self_contained_fileset {project_dir repo_dir} {
    set project_path [p3_slash_path $project_dir]
    set snapshot_prefix "${project_path}/source_snapshot/"
    set xpr_snapshot_prefix "\$PPRDIR/source_snapshot/"
    set rel_snapshot_prefix "source_snapshot/"

    foreach file_obj [get_files -of_objects [current_fileset] -quiet] {
        set file_name [get_property NAME $file_obj]
        if {$file_name eq ""} {
            continue
        }
        set file_path [string map {"\\" "/"} $file_name]
        if {[string first "/piton/" $file_path] >= 0 &&
            [string first $snapshot_prefix $file_path] < 0 &&
            [string first $xpr_snapshot_prefix $file_path] < 0 &&
            [string first $rel_snapshot_prefix $file_path] < 0 &&
            [string first "${project_path}/" $file_path] < 0} {
            puts "ERROR: self-contained fileset contains live OpenPiton source path: ${file_path}"
            exit 1
        }
        foreach pattern [p3_self_contained_forbidden_patterns $repo_dir] {
            if {[string first $pattern $file_path] >= 0} {
                puts "ERROR: self-contained fileset contains forbidden path pattern ${pattern}: ${file_path}"
                exit 1
            }
        }
    }

    set inc_dirs [get_property include_dirs [current_fileset]]
    foreach inc_dir $inc_dirs {
        set inc_path [string map {"\\" "/"} $inc_dir]
        if {[string first "/piton/" $inc_path] >= 0 &&
            [string first $snapshot_prefix $inc_path] < 0 &&
            [string first $xpr_snapshot_prefix $inc_path] < 0 &&
            [string first $rel_snapshot_prefix $inc_path] < 0 &&
            [string first "${project_path}/" $inc_path] < 0} {
            puts "ERROR: self-contained include_dirs contains live OpenPiton source path: ${inc_path}"
            exit 1
        }
        foreach pattern [p3_self_contained_forbidden_patterns $repo_dir] {
            if {[string first $pattern $inc_path] >= 0} {
                puts "ERROR: self-contained include_dirs contains forbidden path pattern ${pattern}: ${inc_path}"
                exit 1
            }
        }
    }

    puts "Self-contained fileset path validation passed for ${project_dir}"
}

proc p3_snapshot_file_path {project_dir rel_path fallback} {
    set snapshot_path [file normalize "${project_dir}/source_snapshot/${rel_path}"]
    if {[file exists $snapshot_path]} {
        return $snapshot_path
    }
    return $fallback
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

proc p3_read_verilog_define_int {file_path macro_name} {
    if {![file exists $file_path]} {
        puts "ERROR: missing generated Verilog header: ${file_path}"
        exit 1
    }

    set fh [open $file_path r]
    set data [read $fh]
    close $fh

    set pattern [format {`define[ \t]+%s[ \t]+([0-9]+)} $macro_name]
    if {![regexp $pattern $data -> value]} {
        puts "ERROR: generated Verilog header ${file_path} does not define ${macro_name}"
        exit 1
    }
    return $value
}

proc p3_validate_tile_define_file {define_file x_tiles y_tiles num_tiles} {
    set got_x [p3_read_verilog_define_int $define_file PITON_X_TILES]
    set got_y [p3_read_verilog_define_int $define_file PITON_Y_TILES]
    set got_num [p3_read_verilog_define_int $define_file PITON_NUM_TILES]

    if {$got_x != $x_tiles || $got_y != $y_tiles || $got_num != $num_tiles} {
        puts "ERROR: generated tile defines in ${define_file} do not match this build"
        puts "       expected PITON_X_TILES=${x_tiles}, PITON_Y_TILES=${y_tiles}, PITON_NUM_TILES=${num_tiles}"
        puts "       got      PITON_X_TILES=${got_x}, PITON_Y_TILES=${got_y}, PITON_NUM_TILES=${got_num}"
        exit 1
    }

    puts "Tile define validation passed for ${define_file}: ${got_x}x${got_y} (${got_num} tiles)"
}

proc p3_validate_ariane_memory_aperture {repo_dir tile_file} {
    set repo_wsl [p3_to_wsl_path $repo_dir]
    set validator_wsl "${repo_wsl}/scripts/p3_validate_tile_aperture.py"
    set device_map_wsl "${repo_wsl}/piton/design/xilinx/huaprop3/devices_ariane.xml"
    set tile_wsl [p3_to_wsl_path $tile_file]
    set cmd "set -e; python3 ${validator_wsl} --device-map ${device_map_wsl} --tile-rtl ${tile_wsl}"
    if {[catch {exec bash -lc $cmd 2>@1} validation_log]} {
        puts $validation_log
        puts "ERROR: generated CVA6 aperture validation failed for ${tile_file}"
        exit 1
    }
    puts $validation_log
}

proc p3_regenerate_pyhp_tmp {repo_dir} {
    set repo_wsl [p3_to_wsl_path $repo_dir]
    set pyhp_wsl "${repo_wsl}/piton/tools/bin/pyhp.py"
    set x_tiles $::env(PITON_X_TILES)
    set y_tiles $::env(PITON_Y_TILES)
    set num_tiles $::env(PITON_NUM_TILES)
    set pyhp_pairs [list \
        "${repo_dir}/piton/design/include/define.h.pyv" \
        "${repo_dir}/piton/design/include/define.tmp.h" \
        "${repo_dir}/piton/design/chip/rtl/chip.v.pyv" \
        "${repo_dir}/piton/design/chip/rtl/chip.tmp.v" \
        "${repo_dir}/piton/design/chip/tile/rtl/tile.v.pyv" \
        "${repo_dir}/piton/design/chip/tile/rtl/tile.tmp.v" \
        "${repo_dir}/piton/design/chipset/rtl/chipset_impl.v.pyv" \
        "${repo_dir}/piton/design/chipset/rtl/chipset_impl.tmp.v" \
        "${repo_dir}/piton/design/chip/tile/common/rtl/flat_id_to_xy.v.pyv" \
        "${repo_dir}/piton/design/chip/tile/common/rtl/flat_id_to_xy.tmp.v" \
        "${repo_dir}/piton/design/chip/tile/common/rtl/xy_to_flat_id.v.pyv" \
        "${repo_dir}/piton/design/chip/tile/common/rtl/xy_to_flat_id.tmp.v" \
    ]

    if {[info exists ::env(P3_BUILD52_EXTRA_PYHP_TEMPLATES)] &&
        $::env(P3_BUILD52_EXTRA_PYHP_TEMPLATES) ne ""} {
        foreach rel_src [split $::env(P3_BUILD52_EXTRA_PYHP_TEMPLATES)] {
            if {$rel_src eq ""} {
                continue
            }
            if {![regexp {\.v\.pyv$} $rel_src]} {
                puts "ERROR: extra PyHP template must end in .v.pyv: ${rel_src}"
                exit 1
            }
            set rel_dst [regsub {\.v\.pyv$} $rel_src {.tmp.v}]
            set src [file normalize "${repo_dir}/${rel_src}"]
            set dst [file normalize "${repo_dir}/${rel_dst}"]
            if {![file exists $src]} {
                puts "ERROR: extra PyHP template not found: ${src}"
                exit 1
            }
            if {[lsearch -exact $pyhp_pairs $src] < 0} {
                lappend pyhp_pairs $src $dst
            }
        }
    }

    for {set i 0} {$i < [llength $pyhp_pairs]} {incr i 2} {
        set src [lindex $pyhp_pairs $i]
        set dst [lindex $pyhp_pairs [expr {$i + 1}]]
        set src_wsl [p3_to_wsl_path $src]
        set dst_wsl [p3_to_wsl_path $dst]
        puts "Regenerating PyHP output: ${src_wsl} -> ${dst_wsl}"
        set cmd "set -e; export PITON_ROOT=${repo_wsl}; export DV_ROOT=${repo_wsl}/piton; export PROTOSYN_RUNTIME_DESIGN_PATH=${repo_wsl}/piton/design/xilinx; export PROTOSYN_RUNTIME_BOARD=huaprop3; export PITON_X_TILES=${x_tiles}; export PITON_Y_TILES=${y_tiles}; export PITON_NUM_TILES=${num_tiles}; export PITON_ARIANE=1; export PITON_RV64_PLATFORM=1; python3 ${pyhp_wsl} ${src_wsl} > ${dst_wsl}"
        if {[catch {exec bash -lc $cmd 2>@1} pyhp_log]} {
            puts $pyhp_log
            puts "ERROR: P3 PyHP regeneration failed for ${src_wsl}"
            exit 1
        }
        if {$pyhp_log ne ""} {
            puts $pyhp_log
        }
        if {![file exists $dst] || [file size $dst] == 0} {
            puts "ERROR: P3 PyHP output is missing or empty: ${dst}"
            exit 1
        }
    }

    p3_validate_tile_define_file "${repo_dir}/piton/design/include/define.tmp.h" \
        $x_tiles $y_tiles $num_tiles
    p3_validate_ariane_memory_aperture $repo_dir \
        "${repo_dir}/piton/design/chip/tile/rtl/tile.tmp.v"
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
    set required_ltx_tokens [list \
        "0x000003FFC0000000" \
        "PMC_AXI_NOC0" \
        "axis_ila_0" \
        "axis_ila_1" \
        "axis_ila_2" \
        "axis_ila_3" \
        "p3_dbg_core_seen16_i" \
        "p3_dbg_uart_seen16_i" \
        "p3_dbg_ddr_seen16_i" \
        "p3_dbg_core_bus64_i" \
        "p3_dbg_uart_bus64_i" \
        "p3_dbg_ddr_bus64_i" \
    ]
    if {[info exists ::env(P3_BUILD52_REQUIRED_LTX_TOKENS)] &&
        $::env(P3_BUILD52_REQUIRED_LTX_TOKENS) ne ""} {
        foreach token [split $::env(P3_BUILD52_REQUIRED_LTX_TOKENS)] {
            if {$token ne ""} {
                lappend required_ltx_tokens $token
            }
        }
    }
    foreach token $required_ltx_tokens {
        if {[string first $token $ltx_data] < 0} {
            puts "ERROR: Build 52 LTX missing token: ${token}"
            exit 1
        }
    }

    file mkdir $output_dir
    set pdi_dst "${output_dir}/${pdi_basename}.pdi"
    set ltx_dst "${output_dir}/${pdi_basename}.ltx"
    file copy -force $pdi_src $pdi_dst
    file copy -force $ltx_src $ltx_dst
    puts "Published Build 52 PDI: ${pdi_dst}"
    puts "Published Build 52 LTX: ${ltx_dst}"
}

puts "=========================================="
puts " Build 52: P3 no-stack AXI16550 SD-CD-mask probe"
puts " Work project: ${project_dir}/${project_name}.xpr"
puts " Output dir: ${output_dir}"
puts " Jobs: ${jobs}"
puts " Reuse synth: ${reuse_synth}"
puts " Prepare BD/ILA: ${run_prepare}"
puts " Post-synth hook: ${post_synth_tcl}"
puts " Self-contained sources: ${p3_self_contained_sources}"
puts " Tile config: ${::env(PITON_X_TILES)}x${::env(PITON_Y_TILES)} (${::env(PITON_NUM_TILES)} tiles)"
puts "=========================================="

if {![file exists $bootrom_rebuild_sh]} {
    puts "ERROR: missing Build 52 bootrom rebuild script: $bootrom_rebuild_sh"
    exit 1
}
if {$post_synth_tcl ne "" && ![file exists $post_synth_tcl]} {
    puts "ERROR: missing post-synthesis hook: ${post_synth_tcl}"
    exit 1
}
puts "Regenerating Build 52 bootrom before Vivado project creation..."
set bootrom_rebuild_exec_path [p3_to_wsl_path $bootrom_rebuild_sh]
puts "Bootrom rebuild script path for bash: ${bootrom_rebuild_exec_path}"
if {[catch {exec bash $bootrom_rebuild_exec_path 2>@1} bootrom_rebuild_log]} {
    puts $bootrom_rebuild_log
    puts "ERROR: Build 52 bootrom regeneration failed"
    exit 1
}
puts $bootrom_rebuild_log

p3_regenerate_pyhp_tmp $repo_dir

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
    puts "Skipping Build 52 prepare step."
}

if {$p3_self_contained_sources} {
    p3_validate_self_contained_xpr $project_dir $project_name $repo_dir
    p3_validate_tile_define_file "${project_dir}/source_snapshot/piton/design/include/define.tmp.h" \
        $::env(PITON_X_TILES) $::env(PITON_Y_TILES) $::env(PITON_NUM_TILES)
    p3_validate_ariane_memory_aperture $repo_dir \
        "${project_dir}/source_snapshot/piton/design/chip/tile/rtl/tile.tmp.v"
}

open_project "${project_dir}/${project_name}.xpr"
if {$p3_self_contained_sources} {
    set ariane_unread_impl_src [p3_snapshot_file_path $project_dir \
        "piton/design/xilinx/huaprop3/unread_vivado_impl.sv" \
        $ariane_unread_impl_src]
}

set defs [get_property verilog_define [current_fileset]]
set cleaned_defs {}
foreach define $defs {
    if {$define ne "P3_SIFIVE_UART" &&
        $define ne "P3_BD_SIFIVE_DEBUG_ILA" &&
        $define ne "P3_SIFIVE_UART_DEBUG_ILA" &&
        $define ne "P3_BD_UART_RAW_DEBUG_ILA" &&
        $define ne "P3_BD_UART_SD_DIAG_ILA" &&
        $define ne "P3_BD_BUILD41_DEBUG_ILA" &&
        $define ne "P3_BD_DDR_DEBUG_ILA" &&
        $define ne "P3_BD_BOOT_DEBUG_ILA" &&
        $define ne "P3_BD_BOOT_PROGRESS_ILA" &&
        $define ne "P3_BD_SD_SMOKE_ILA" &&
        $define ne "P3_BD_SD_INIT_ILA" &&
        $define ne "P3_BD_UART_DEBUG_ILA" &&
        $define ne "P3_BD_UART_LIVE_NARROW_DEBUG_ILA" &&
        $define ne "P3_BD_UART_WR_DEBUG_ILA" &&
        $define ne "P3_BD_UART_WR_NARROW_DEBUG_ILA" &&
        $define ne "P3_BD_UART_RW_DEBUG_ILA" &&
        $define ne "P3_SD_IGNORE_CARD_DETECT_RESET" &&
        $define ne "P3_BD_SD_CMD_DEBUG_ILA" &&
        $define ne "P3_SPI_SD_BOOT" &&
        $define ne "P3_SPI_SD_HISTORY_DEBUG" &&
        $define ne "P3_SPI_SD_PAD_DEBUG" &&
        $define ne "P3_SPI_SD_REF_CMD_DEBUG" &&
        $define ne "P3_SPI_SD_BLOCK_DEBUG" &&
        $define ne "P3_BUILD75_PC_L15_DEBUG" &&
        $define ne "PITONSYS_MEM_ZEROER"} {
        lappend cleaned_defs $define
    }
}
set defs $cleaned_defs
set required_defines [list \
    PITON_UART16550 \
    P3_AXI_DDR_ADDR_TRANSLATE \
    P3_RTL_DEBUG \
    P3_BD_BOOT_PROGRESS_ILA \
    P3_BD_SD_INIT_ILA \
    P3_BD_UART_WR_DEBUG_ILA \
    P3_BD_UART_RW_DEBUG_ILA \
    P3_SD_IGNORE_CARD_DETECT_RESET \
    PITON_ARIANE \
    PITON_RV64_PLATFORM \
    PITON_RV64_DEBUGUNIT \
    PITON_RV64_CLINT \
    PITON_RV64_PLIC \
    WT_DCACHE \
]
foreach extra_define $p3_extra_defines {
    if {$extra_define ne ""} {
        lappend required_defines $extra_define
    }
}
foreach required_define $required_defines {
    if {[lsearch -exact $defs $required_define] < 0} {
        lappend defs $required_define
    }
}
set_property verilog_define $defs [current_fileset]
puts "Verilog defines: [get_property verilog_define [current_fileset]]"

if {[lsearch -exact $defs "P3_SIFIVE_UART"] >= 0 ||
    [lsearch -exact $defs "P3_SIFIVE_UART_DEBUG_ILA"] >= 0} {
    puts "ERROR: Build 52 must not enable SiFive UART macros"
    exit 1
}
if {[lsearch -exact $defs "PITONSYS_MEM_ZEROER"] >= 0} {
    puts "ERROR: Build 52 keeps PITONSYS_MEM_ZEROER disabled to isolate SD card-detect mask debug traffic"
    exit 1
}

p3_use_ariane_unread_vivado_shim $ariane_unread_impl_src
update_compile_order -fileset sources_1
if {$p3_self_contained_sources} {
    p3_validate_self_contained_fileset $project_dir $repo_dir
}

if {$reuse_synth && $run_prepare} {
    puts "ERROR: -reuse_synth requires -skip_prepare because prepare regenerates synth_1 scripts and resets the run."
    exit 1
}

p3_set_vivado_thread_params $jobs "top synthesis and place/route"

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

if {$post_synth_tcl ne ""} {
    puts "Running post-synthesis hook: ${post_synth_tcl}"
    source $post_synth_tcl
}

p3_seed_build52_impl_caches $project_dir $project_name $repo_dir

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
puts " Build 52 AXI16550 SD card-detect mask debug flow complete"
puts "=========================================="
