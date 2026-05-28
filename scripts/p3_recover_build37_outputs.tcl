# p3_recover_build37_outputs.tcl -- Recover Build 37 LTX/PDI from routed DCP.
#
# Usage:
#   vivado -mode batch -source scripts/p3_recover_build37_outputs.tcl
#
# Build 37 routed successfully but failed during write_device_image PLM BSP
# generation in the run-manager directory. This script opens the routed DCP,
# writes LTX/PDI from a short temporary working directory, validates the debug
# metadata, and publishes the outputs without rerunning synthesis or route.

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]
set run_dir [file normalize "${repo_dir}/huaprop3_openpiton/huaprop3_openpiton.runs/impl_37_uartlivenarrowila"]
set output_dir [file normalize "${repo_dir}/huaprop3_openpiton/debug_build"]
set routed_dcp "${run_dir}/p3_top_routed.dcp"
set tmp_dir "Z:/tmp/p3_b37_recover"
set tmp_ltx "${tmp_dir}/p3_top_build37_runmgr_uart_live_narrow_ila.ltx"
set tmp_pdi "${tmp_dir}/p3_top_build37_runmgr_uart_live_narrow_ila.pdi"
set ltx_out "${output_dir}/p3_top_build37_runmgr_uart_live_narrow_ila.ltx"
set pdi_out "${output_dir}/p3_top_build37_runmgr_uart_live_narrow_ila.pdi"

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
    foreach token [list \
        "0x000003FFC0000000" \
        "PMC_AXI_NOC0" \
        "axis_ila_0" \
        "axis_ila_1" \
        "p3_dbg_uart_seen16_i" \
        "p3_dbg_uart_bus64_i" \
    ] {
        if {[string first $token $data] < 0} {
            puts "ERROR: LTX is missing expected Build 37 token: ${token}"
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
puts " Build 37 routed-output recovery"
puts " Run dir: ${run_dir}"
puts " Routed DCP: ${routed_dcp}"
puts " Work dir: ${tmp_dir}"
puts " LTX out: ${ltx_out}"
puts " PDI out: ${pdi_out}"
puts "=========================================="

p3_require_file $routed_dcp "Build 37 routed DCP"
file mkdir $tmp_dir
file mkdir $output_dir
cd $tmp_dir

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

write_debug_probes -force $tmp_ltx
p3_validate_ltx $tmp_ltx

write_device_image -force $tmp_pdi
p3_validate_pdi $tmp_pdi

file copy -force $tmp_ltx $ltx_out
file copy -force $tmp_pdi $pdi_out
p3_validate_ltx $ltx_out
p3_validate_pdi $pdi_out

close_design
puts "Published recovered Build 37 LTX: ${ltx_out}"
puts "Published recovered Build 37 PDI: ${pdi_out}"
puts "=========================================="
puts " Build 37 output recovery complete"
puts "=========================================="
