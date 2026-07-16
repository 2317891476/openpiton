# p3_build76_eco_pc_diag.tcl -- Rewire the existing, board-validated Build 66
# BD-owned ILAs to CVA6 commit-head signals, then route only the ECO changes.
#
# This flow deliberately does not create a new ILA or debug hub.  The VP1902
# debug path remains the same one that was already routed and board-validated
# in Build 66.  Only existing ILA probe loads are moved.
#
# Usage from Windows Vivado 2024.2.2:
#   vivado -mode batch -source scripts/p3_build76_eco_pc_diag.tcl
#   vivado -mode batch -source scripts/p3_build76_eco_pc_diag.tcl -tclargs \
#     <build66-routed.dcp> <native-windows-output-dir>

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]
set default_dcp [file normalize \
    "${repo_dir}/p3b66_validated_snapshot/huaprop3_build66_normal_spi_sd_boot.runs/impl_1/p3_top_routed.dcp"]
set default_output_dir {D:/p3b76_eco_pc_diag}

if {[llength $argv] > 2} {
    puts "ERROR: expected optional routed DCP and output directory"
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
    puts "ERROR: validated Build 66 routed DCP not found: $input_dcp"
    exit 1
}

file mkdir $output_dir
set output_base "${output_dir}/p3_top_build76_build66_eco_pc_diag"
set mapping_file "${output_base}_probe_map.txt"
set pre_route_dcp "${output_base}_pre_route.dcp"
set route_report "${output_base}_route_status.rpt"
set timing_report "${output_base}_timing_summary.rpt"
set drc_report "${output_base}_drc.rpt"
set ltx_file "${output_base}.ltx"
set pdi_file "${output_base}.pdi"

proc p3_require_debug_port {name width} {
    set ports [get_debug_ports -quiet [list $name]]
    if {[llength $ports] != 1} {
        error "required debug port matched [llength $ports] objects: $name"
    }
    set actual [get_property PORT_WIDTH $ports]
    if {$actual != $width} {
        error "debug port $name has width $actual, expected $width"
    }
    return $ports
}

proc p3_require_net {name} {
    set nets [get_nets -quiet [list $name]]
    if {[llength $nets] != 1} {
        error "required exact net matched [llength $nets] objects: $name"
    }
    return [lindex $nets 0]
}

proc p3_require_bus {base width} {
    set result [list]
    for {set bit 0} {$bit < $width} {incr bit} {
        lappend result [p3_require_net "${base}\[$bit\]"]
    }
    return $result
}

proc p3_property_is_true {object property} {
    set value [get_property $property $object]
    return [expr {$value eq "1" || [string equal -nocase $value "true"]}]
}

proc p3_reconnect_probe {port_name width nets} {
    if {[llength $nets] != $width} {
        error "$port_name received [llength $nets] nets, expected $width"
    }
    p3_require_debug_port $port_name $width
    set port_tag [string map {/ _} $port_name]
    for {set bit 0} {$bit < $width} {incr bit} {
        set pin_name "${port_name}\[$bit\]"
        set pins [get_pins -quiet [list $pin_name]]
        if {[llength $pins] != 1} {
            error "required exact ILA input pin matched [llength $pins] objects: $pin_name"
        }
        if {[get_property DIRECTION $pins] ne "IN"} {
            error "ILA probe pin is not an input: $pin_name"
        }
        set old_nets [get_nets -quiet -of_objects $pins]
        if {[llength $old_nets] != 1} {
            error "ILA probe pin has [llength $old_nets] existing nets: $pin_name"
        }
        set new_net [lindex $nets $bit]
        set old_dont_touch [p3_property_is_true $old_nets DONT_TOUCH]
        if {$old_dont_touch} {
            set_property DONT_TOUCH false $old_nets
        }
        disconnect_net -net $old_nets -pinlist $pins
        if {$old_dont_touch} {
            set_property DONT_TOUCH true $old_nets
        }
        set new_dont_touch [p3_property_is_true $new_net DONT_TOUCH]
        if {$new_dont_touch} {
            set_property DONT_TOUCH false $new_net
        }
        connect_net -hierarchical \
            -basename "p3_build76_${port_tag}_${bit}" \
            -net $new_net -objects $pins
        if {$new_dont_touch} {
            set_property DONT_TOUCH true $new_net
        }
    }
    puts "Reconnected $port_name to $width exact nets"
}

set_param general.maxThreads 16
set_msg_config -id {Vivado 12-3773} -suppress
set_msg_config -id {Constraints 18-549} -suppress
puts "Opening validated Build 66 routed checkpoint: $input_dcp"
open_checkpoint $input_dcp
set resume_from_pre_route [string match \
    {*_pre_route.dcp} [string tolower $input_dcp]]

set required_cores [list \
    {axi_dbg_hub} \
    {u_bd/openpiton_top_i/axis_ila_0} \
    {u_bd/openpiton_top_i/axis_ila_1} \
    {u_bd/openpiton_top_i/axis_ila_2} \
    {u_bd/openpiton_top_i/axis_ila_3}]
foreach name $required_cores {
    if {[llength [get_debug_cores -quiet [list $name]]] != 1} {
        error "validated debug core is missing or ambiguous: $name"
    }
}
if {[get_property C_DATA_DEPTH \
        [get_debug_cores {u_bd/openpiton_top_i/axis_ila_1}]] != 1024} {
    error "Build 66 axis_ila_1 depth is no longer the validated 1024 samples"
}

if {!$resume_from_pre_route} {
set scoreboard \
    {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6/issue_stage_i/i_scoreboard}
set commit_base "${scoreboard}/commit_instr_id_commit\[0\]"
set pc_nets [p3_require_bus "${commit_base}\[pc\]" 64]
set fu_nets [p3_require_bus "${commit_base}\[fu\]" 4]
set op_nets [p3_require_bus "${commit_base}\[op\]" 8]
set valid_net [p3_require_net "${commit_base}\[valid\]"]
set ack_net [p3_require_net "${scoreboard}/commit_ack\[0\]"]
set lsu_nets [p3_require_bus \
    {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6/lsu_addr} 11]
set stall_nets [list \
    [p3_require_net \
        {u_openpiton/system_inst/chip/tile0/l15/l15/pipeline/stall_s1}] \
    [p3_require_net \
        {u_openpiton/system_inst/chip/tile0/l15/l15/pipeline/stall_s2}] \
    [p3_require_net \
        {u_openpiton/system_inst/chip/tile0/l15/l15/pipeline/l15_csm_stall_s3}]]
set uart_tail [lrange [p3_require_bus \
    {u_bd/openpiton_top_i/p3_dbg_uart_bus64_i_1} 64] 0 35]
# axis_ila_1/probe0[63:0] is the exact commit-head PC.
p3_reconnect_probe \
    {u_bd/openpiton_top_i/axis_ila_1/probe0} 64 $pc_nets

# axis_ila_2/probe0 packs the commit state and keeps 36 bits of the existing
# UART diagnostic bus so every implemented probe channel remains connected.
# Channel order is least-significant bit first.
set status_nets [concat \
    [list $valid_net $ack_net] \
    $fu_nets \
    $op_nets \
    $lsu_nets \
    $stall_nets \
    $uart_tail]
p3_reconnect_probe \
    {u_bd/openpiton_top_i/axis_ila_2/probe0} 64 $status_nets

set fh [open $mapping_file w]
puts $fh "Build 76 probe map (channel 0 is the least-significant CSV bit)"
puts $fh "axis_ila_0: unchanged Build 66 heartbeat/layer-seen probes"
puts $fh "axis_ila_1/probe0\[63:0\]: commit_instr_id_commit\[0\].pc\[63:0\]"
puts $fh "axis_ila_2/probe0\[0\]: commit valid"
puts $fh "axis_ila_2/probe0\[1\]: commit ack"
puts $fh "axis_ila_2/probe0\[5:2\]: commit FU\[3:0\]"
puts $fh "axis_ila_2/probe0\[13:6\]: commit op\[7:0\]"
puts $fh "axis_ila_2/probe0\[24:14\]: LSU address\[10:0\]"
puts $fh "axis_ila_2/probe0\[25\]: L1.5 stall_s1"
puts $fh "axis_ila_2/probe0\[26\]: L1.5 stall_s2"
puts $fh "axis_ila_2/probe0\[27\]: L1.5 l15_csm_stall_s3"
puts $fh "axis_ila_2/probe0\[63:28\]: original UART diagnostic bus\[35:0\]"
puts $fh "axis_ila_3/probe0\[63:0\]: unchanged original Build 66 DDR diagnostic bus"
close $fh

write_checkpoint -force $pre_route_dcp
} else {
    puts "Resuming from an existing Build 76 pre-route ECO checkpoint"
}
puts "Routing ECO probe loads while preserving the validated routed design"
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
    {u_bd/openpiton_top_i/axis_ila_1} \
    {p3_build76_u_bd_openpiton_top_i_axis_ila_1_probe0_0} \
    {p3_build76_u_bd_openpiton_top_i_axis_ila_1_probe0_63} \
    {p3_build76_u_bd_openpiton_top_i_axis_ila_2_probe0_27}] {
    if {[string first $marker $ltx_text] < 0} {
        error "generated LTX is missing required marker: $marker"
    }
}

write_device_image -force -file $pdi_file
if {![file exists $pdi_file] || [file size $pdi_file] == 0} {
    error "write_device_image did not create a non-empty PDI: $pdi_file"
}

report_timing_summary -delay_type min_max -max_paths 20 -file $timing_report
report_drc -file $drc_report

puts "SUCCESS: Build 76 Build-66 ECO PC diagnostic generated"
puts "  pre-route DCP: $pre_route_dcp"
puts "  PDI:        $pdi_file"
puts "  LTX:        $ltx_file"
puts "  probe map:  $mapping_file"
