# p3_build77_fix_commit_valid_eco.tcl -- Correct Build 76 status bit 0 from
# the exception-valid field to the commit-entry valid field, then reroute the
# existing Build 66 ECO probes.  Functional logic and the other 127 modified
# probe channels are unchanged.

set default_dcp \
    {D:/p3b76_eco_pc_diag/p3_top_build76_build66_eco_pc_diag_pre_route.dcp}
set default_output_dir {D:/p3b77_commit_valid_fix}

if {[llength $argv] > 2} {
    puts "ERROR: expected optional Build 76 pre-route DCP and output directory"
    exit 1
}
set input_dcp $default_dcp
set output_dir $default_output_dir
if {[llength $argv] >= 1} {
    set input_dcp [file normalize [lindex $argv 0]]
}
if {[llength $argv] == 2} {
    set output_dir [file normalize [lindex $argv 1]]
}
if {![file exists $input_dcp]} {
    puts "ERROR: Build 76 pre-route DCP not found: $input_dcp"
    exit 1
}

file mkdir $output_dir
set output_base "${output_dir}/p3_top_build77_commit_valid_fix"
set pre_route_dcp "${output_base}_pre_route.dcp"
set route_report "${output_base}_route_status.rpt"
set timing_report "${output_base}_timing_summary.rpt"
set drc_report "${output_base}_drc.rpt"
set ltx_file "${output_base}.ltx"
set pdi_file "${output_base}.pdi"

proc p3_require_one {kind objects name} {
    if {[llength $objects] != 1} {
        error "required exact $kind matched [llength $objects] objects: $name"
    }
    return [lindex $objects 0]
}

proc p3_property_is_true {object property} {
    set value [get_property $property $object]
    return [expr {$value eq "1" || [string equal -nocase $value "true"]}]
}

set_param general.maxThreads 16
set_msg_config -id {Vivado 12-3773} -suppress
set_msg_config -id {Constraints 18-549} -suppress
puts "Opening Build 76 pre-route ECO checkpoint: $input_dcp"
open_checkpoint $input_dcp

foreach name [list \
    {axi_dbg_hub} \
    {u_bd/openpiton_top_i/axis_ila_0} \
    {u_bd/openpiton_top_i/axis_ila_1} \
    {u_bd/openpiton_top_i/axis_ila_2} \
    {u_bd/openpiton_top_i/axis_ila_3}] {
    p3_require_one debug_core [get_debug_cores -quiet [list $name]] $name
}

set valid_name \
    {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6/issue_stage_i/i_scoreboard/commit_instr_id_commit[0][valid]}
set valid_net [p3_require_one net [get_nets -quiet [list $valid_name]] $valid_name]
set probe_name {u_bd/openpiton_top_i/axis_ila_2/probe0[0]}
set probe_pin [p3_require_one pin [get_pins -quiet [list $probe_name]] $probe_name]
set old_net [p3_require_one net [get_nets -quiet -of_objects $probe_pin] $probe_name]
if {![string match {*axis_ila_2_probe0_0} $old_net]} {
    error "Build 76 status bit 0 is not on the expected ECO branch: $old_net"
}

set old_dont_touch [p3_property_is_true $old_net DONT_TOUCH]
if {$old_dont_touch} {
    set_property DONT_TOUCH false $old_net
}
disconnect_net -net $old_net -pinlist $probe_pin
if {$old_dont_touch} {
    set_property DONT_TOUCH true $old_net
}
set valid_dont_touch [p3_property_is_true $valid_net DONT_TOUCH]
if {$valid_dont_touch} {
    set_property DONT_TOUCH false $valid_net
}
connect_net -hierarchical -basename p3_build77_commit_valid \
    -net $valid_net -objects $probe_pin
if {$valid_dont_touch} {
    set_property DONT_TOUCH true $valid_net
}
puts "Corrected axis_ila_2/probe0\[0\] to commit_instr_id_commit\[0\].valid"

write_checkpoint -force $pre_route_dcp
route_design -eco
report_route_status -file $route_report

write_debug_probes -force $ltx_file
if {![file exists $ltx_file] || [file size $ltx_file] == 0} {
    error "write_debug_probes did not create a non-empty LTX: $ltx_file"
}
set fh [open $ltx_file r]
set ltx_text [read $fh]
close $fh
foreach marker [list \
    {0x000003FFC0000000} \
    {p3_build76_u_bd_openpiton_top_i_axis_ila_1_probe0_0} \
    {p3_build76_u_bd_openpiton_top_i_axis_ila_1_probe0_63} \
    {p3_build77_commit_valid} \
    {p3_build76_u_bd_openpiton_top_i_axis_ila_2_probe0_27}] {
    if {[string first $marker $ltx_text] < 0} {
        error "generated Build 77 LTX is missing required marker: $marker"
    }
}

write_device_image -force -file $pdi_file
if {![file exists $pdi_file] || [file size $pdi_file] == 0} {
    error "write_device_image did not create a non-empty PDI: $pdi_file"
}
report_timing_summary -delay_type min_max -max_paths 20 -file $timing_report
report_drc -file $drc_report

puts "SUCCESS: Build 77 commit-valid-corrected ECO diagnostic generated"
puts "  pre-route DCP: $pre_route_dcp"
puts "  PDI:           $pdi_file"
puts "  LTX:           $ltx_file"
