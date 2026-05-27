# p3_recover_build32_outputs.tcl -- Recover Build 32 LTX/PDI from routed outputs.
#
# Usage:
#   vivado -mode batch -source scripts/p3_recover_build32_outputs.tcl
#
# Build 32 routed successfully but failed during write_device_image PLM BSP
# generation in a Windows/WSL path-dependent embeddedsw copy/include step. This
# recovery script opens the routed DCP from a shorter working directory, validates
# that the BD-owned debug metadata is still present, then writes the matching LTX
# and PDI without rerunning synthesis or implementation.

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]
set run_dir [file normalize "${repo_dir}/huaprop3_openpiton/huaprop3_openpiton.runs/impl_32_runmgr_chipset_ila"]
set output_dir [file normalize "${repo_dir}/huaprop3_openpiton/debug_build"]
set routed_dcp "${run_dir}/p3_top_routed.dcp"
set ltx_out "${output_dir}/p3_top_build32_runmgr_chipset_ila.ltx"
set pdi_out "${output_dir}/p3_top_build32_runmgr_chipset_ila.pdi"

cd $repo_dir

proc p3_require_file {path label} {
    if {![file exists $path]} {
        puts "ERROR: missing ${label}: ${path}"
        exit 1
    }
}

proc p3_validate_ltx {ltx_file} {
    p3_require_file $ltx_file "LTX"
    if {[file size $ltx_file] <= 0} {
        puts "ERROR: empty LTX: ${ltx_file}"
        exit 1
    }
    set fh [open $ltx_file r]
    set data [read $fh]
    close $fh
    foreach token [list "0x000003FFC0000000" "PMC_AXI_NOC0" "axis_ila_0" "axis_ila_1"] {
        if {[string first $token $data] < 0} {
            puts "ERROR: LTX is missing expected token: ${token}"
            exit 1
        }
    }
}

proc p3_validate_pdi {pdi_file} {
    p3_require_file $pdi_file "PDI"
    if {[file size $pdi_file] <= 0} {
        puts "ERROR: empty PDI: ${pdi_file}"
        exit 1
    }
}

puts "=========================================="
puts " Build 32 routed-output recovery"
puts " Run dir: ${run_dir}"
puts " Routed DCP: ${routed_dcp}"
puts " LTX out: ${ltx_out}"
puts " PDI out: ${pdi_out}"
puts "=========================================="

p3_require_file $routed_dcp "Build 32 routed DCP"
file mkdir $output_dir

open_checkpoint $routed_dcp

set debug_cores [get_debug_cores -quiet]
puts "Debug cores: ${debug_cores}"
foreach core $debug_cores {
    set name $core
    catch {set name [get_property NAME $core]}
    puts "  CORE ${name}"
}

if {[llength $debug_cores] == 0} {
    puts "ERROR: routed DCP has no debug cores visible to write_debug_probes"
    exit 1
}

write_debug_probes -force $ltx_out
p3_validate_ltx $ltx_out

write_device_image -force $pdi_out
p3_validate_pdi $pdi_out

close_design
puts "Published recovered Build 32 LTX: ${ltx_out}"
puts "Published recovered Build 32 PDI: ${pdi_out}"
puts "=========================================="
puts " Build 32 output recovery complete"
puts "=========================================="
