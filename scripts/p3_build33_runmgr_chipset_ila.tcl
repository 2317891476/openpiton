# p3_build33_runmgr_chipset_ila.tcl -- Build 33 using project run-manager ILAs.
# Usage:
#   vivado -mode batch -source scripts/p3_build33_runmgr_chipset_ila.tcl
#   vivado -mode batch -source scripts/p3_build33_runmgr_chipset_ila.tcl -tclargs -skip_prepare
#   vivado -mode batch -source scripts/p3_build33_runmgr_chipset_ila.tcl -tclargs -jobs 2

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]
set project_dir [file normalize "${script_dir}/../huaprop3_openpiton"]
set project_name "huaprop3_openpiton"
set output_dir "${project_dir}/debug_build"
set prepare_tcl [file normalize "${script_dir}/p3_prepare_build33_chipset_ila.tcl"]
set synth_run "synth_1"
set impl_run "impl_33_chipila"
set pdi_basename "p3_top_build33_runmgr_chipset_ila"
set tmp_dir "Z:/tmp"
set run_prepare 1
set jobs 1

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    switch -- $arg {
        -skip_prepare {
            set run_prepare 0
        }
        -jobs {
            incr i
            if {$i >= [llength $argv]} {
                puts "ERROR: -jobs requires a value"
                exit 1
            }
            set jobs [lindex $argv $i]
            if {![string is integer -strict $jobs] || $jobs < 1} {
                puts "ERROR: -jobs must be a positive integer"
                exit 1
            }
        }
        default {
            puts "ERROR: unknown argument: $arg"
            puts "Usage: vivado -mode batch -source scripts/p3_build33_runmgr_chipset_ila.tcl ?-tclargs -skip_prepare? ?-jobs N?"
            exit 1
        }
    }
}

proc p3_require_file {path label} {
    if {![file exists $path]} {
        puts "ERROR: missing ${label}: ${path}"
        exit 1
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

    set p3_top_tmp "${tmp_dir}/p3_top.v"
    set fh [open $p3_top_tmp r]
    set data [read $fh]
    close $fh
    foreach token [list "P3_BD_CHIPSET_DEBUG_ILA" "p3_dbg_chipset_seen16_i" "p3_dbg_chipset_bus64_i"] {
        if {[string first $token $data] < 0} {
            puts "ERROR: synced ${p3_top_tmp} is missing expected Build 33 token: ${token}"
            exit 1
        }
    }
}

proc p3_check_synth_log_for_stale_tmp_rtl {synth_run} {
    set synth_dir [get_property DIRECTORY [get_runs $synth_run]]
    if {$synth_dir eq ""} {
        puts "WARNING: cannot resolve synthesis run directory for ${synth_run}"
        return
    }

    foreach log_name [list runme.log vivado.log] {
        set log_file "${synth_dir}/${log_name}"
        if {![file exists $log_file]} {
            continue
        }
        set fh [open $log_file r]
        set log_data [read $fh]
        close $fh
        if {[regexp {instance 'u_bd' of module 'openpiton_top_wrapper' has [0-9]+ connections declared, but only [0-9]+ given} $log_data]} {
            puts "ERROR: synthesis log still shows an under-connected openpiton_top_wrapper/u_bd."
            puts "       This usually means Vivado read stale Z:/tmp RTL and left Build 33 BD debug inputs floating."
            puts "       Log: ${log_file}"
            exit 1
        }
    }
}

proc p3_runmgr_check_status {run_name phase} {
    set run_obj [get_runs $run_name]
    set status [get_property STATUS $run_obj]
    puts "${phase} status for ${run_name}: ${status}"
    if {[string match -nocase "*fail*" $status] ||
        [string match -nocase "*error*" $status] ||
        ![string match "*Complete*" $status]} {
        puts "ERROR: ${phase} did not complete successfully"
        exit 1
    }
}

proc p3_remove_stale_post_synth_debug_constraints {} {
    set stale_names [list p3_top_debug.xdc p3_top_rtl_debug.xdc]
    set removed {}

    foreach fileset [get_filesets -quiet] {
        foreach file_obj [get_files -quiet -of_objects $fileset] {
            set tail [file tail [get_property NAME $file_obj]]
            if {[lsearch -exact $stale_names $tail] >= 0} {
                puts "Removing stale post-synthesis debug constraint from ${fileset}: ${file_obj}"
                lappend removed $file_obj
            }
        }
    }

    if {[llength $removed] != 0} {
        remove_files $removed
    }

    set remaining {}
    foreach fileset [get_filesets -quiet] {
        foreach file_obj [get_files -quiet -of_objects $fileset] {
            set tail [file tail [get_property NAME $file_obj]]
            if {[lsearch -exact $stale_names $tail] >= 0} {
                lappend remaining "${fileset}:${file_obj}"
            }
        }
    }
    if {[llength $remaining] != 0} {
        puts "ERROR: stale post-synthesis debug constraints are still in the project:"
        foreach item $remaining {
            puts "  $item"
        }
        exit 1
    }
}

proc p3_find_latest_file {dir pattern} {
    set files [glob -nocomplain -directory $dir $pattern]
    if {[llength $files] == 0} {
        return ""
    }
    set best [lindex $files 0]
    set best_mtime [file mtime $best]
    foreach file $files {
        set mtime [file mtime $file]
        if {$mtime > $best_mtime} {
            set best $file
            set best_mtime $mtime
        }
    }
    return $best
}

proc p3_copy_checked_run_output {run_dir output_dir pdi_basename} {
    set pdi_src [p3_find_latest_file $run_dir "*.pdi"]
    set ltx_src [p3_find_latest_file $run_dir "*.ltx"]
    set pdi_dst "${output_dir}/${pdi_basename}.pdi"
    set ltx_dst "${output_dir}/${pdi_basename}.ltx"

    if {$pdi_src eq ""} {
        puts "ERROR: run-manager completed but no PDI was found in ${run_dir}"
        exit 1
    }
    if {$ltx_src eq ""} {
        puts "ERROR: run-manager completed but no LTX was found in ${run_dir}"
        puts "       Refusing to publish a PDI without matching probes."
        exit 1
    }
    if {[file size $ltx_src] <= 0} {
        puts "ERROR: run-manager produced an empty LTX: ${ltx_src}"
        exit 1
    }

    set fh [open $ltx_src r]
    set ltx_data [read $fh]
    close $fh
    if {[string first "0x000003FFC0000000" $ltx_data] < 0 ||
        [string first "PMC_AXI_NOC0" $ltx_data] < 0 ||
        [string first "axis_ila_0" $ltx_data] < 0 ||
        [string first "axis_ila_1" $ltx_data] < 0} {
        puts "ERROR: LTX is missing the expected Build 33 debug hub path or split ILA cells."
        puts "       Expected address 0x000003FFC0000000 through PMC_AXI_NOC0 and axis_ila_0/axis_ila_1."
        exit 1
    }

    file mkdir $output_dir
    file delete -force $pdi_dst $ltx_dst
    file copy -force $pdi_src $pdi_dst
    file copy -force $ltx_src $ltx_dst
    puts "Published Build 33 PDI: ${pdi_dst}"
    puts "Published Build 33 LTX: ${ltx_dst}"
}

puts "=========================================="
puts " Build 33: run-manager chipset BD-owned ILAs"
puts " Project: ${project_dir}/${project_name}.xpr"
puts " Jobs: ${jobs}"
puts "=========================================="

p3_copy_tmp_rtl $repo_dir $tmp_dir

if {$run_prepare} {
    source $prepare_tcl
} else {
    puts "Skipping Build 33 BD preparation step."
}

p3_copy_tmp_rtl $repo_dir $tmp_dir

open_project "${project_dir}/${project_name}.xpr"
p3_remove_stale_post_synth_debug_constraints
update_compile_order -fileset sources_1

if {[llength [get_runs -quiet $impl_run]] == 0} {
    puts "Creating implementation run: ${impl_run}"
    create_run $impl_run \
        -parent_run $synth_run \
        -flow {Vivado Advanced Implementation 2024} \
        -strategy {Vivado Advanced Implementation Defaults} \
        -part [get_property PART [current_project]]
} else {
    puts "Reusing implementation run object: ${impl_run}"
}

puts "Resetting and launching synthesis run: ${synth_run}"
reset_run $synth_run
launch_runs $synth_run -jobs $jobs
wait_on_run $synth_run
p3_runmgr_check_status $synth_run "Synthesis"
p3_check_synth_log_for_stale_tmp_rtl $synth_run

puts "Resetting and launching implementation run: ${impl_run}"
reset_run $impl_run
launch_runs $impl_run -to_step write_device_image -jobs $jobs
wait_on_run $impl_run
p3_runmgr_check_status $impl_run "Implementation"

set run_dir [get_property DIRECTORY [get_runs $impl_run]]
if {$run_dir eq ""} {
    set run_dir "${project_dir}/${project_name}.runs/${impl_run}"
}
puts "Implementation run directory: ${run_dir}"
p3_copy_checked_run_output $run_dir $output_dir $pdi_basename

close_project

puts "=========================================="
puts " Build 33 run-manager chipset flow complete"
puts "=========================================="
