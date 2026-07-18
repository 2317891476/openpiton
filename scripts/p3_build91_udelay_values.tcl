# p3_build91_udelay_values.tcl -- Rewire three retained Build 90 ILAs to
# observe Linux udelay's a3/start, a4/threshold, and a5/current-or-delta value.
# This is diagnostic-only: no functional cell or RTL net driver is changed.

set default_dcp \
    {D:/p3b90_time_csr_rtl/huaprop3_build90_time_csr_rtl.runs/impl_1/p3_top_routed.dcp}
set default_output_dir {D:/p3b91_udelay_values}
set output_stem {p3_top_build91_udelay_values}
set gpr_regs {13 14 15}
set gpr_names {a3_start a4_threshold a5_time_delta}
set tag_prefix {p3_build91}
if {[info exists env(P3_UDELAY_OUTPUT_STEM)]} {
    set output_stem $env(P3_UDELAY_OUTPUT_STEM)
}
if {[info exists env(P3_UDELAY_GPR_REGS)]} {
    set gpr_regs $env(P3_UDELAY_GPR_REGS)
}
if {[info exists env(P3_UDELAY_GPR_NAMES)]} {
    set gpr_names $env(P3_UDELAY_GPR_NAMES)
}
if {[info exists env(P3_UDELAY_TAG_PREFIX)]} {
    set tag_prefix $env(P3_UDELAY_TAG_PREFIX)
}
if {[llength $gpr_regs] != 3 || [llength $gpr_names] != 3} {
    error "udelay diagnostic requires exactly three GPR numbers and names"
}

if {[llength $argv] > 2} {
    error "expected optional Build 90 routed DCP and output directory"
}
set input_dcp $default_dcp
set output_dir $default_output_dir
if {[llength $argv] >= 1} {
    set input_dcp [file normalize [lindex $argv 0]]
}
if {[llength $argv] == 2} {
    set output_dir [file normalize [lindex $argv 1]]
}
if {![file exists $input_dcp] || [file size $input_dcp] == 0} {
    error "Build 90 routed DCP is missing or empty: $input_dcp"
}

file mkdir $output_dir
set output_base "${output_dir}/${output_stem}"
set probe_map "${output_base}_probe_map.txt"
set pre_route_dcp "${output_base}_pre_route.dcp"
set routed_dcp "${output_base}_routed.dcp"
set route_report "${output_base}_route_status.rpt"
set timing_report "${output_base}_timing_summary.rpt"
set drc_report "${output_base}_drc.rpt"
set ltx_file "${output_base}.ltx"
set pdi_file "${output_base}.pdi"
set resume_from_build91 [string equal -nocase \
    [file normalize $input_dcp] [file normalize $pre_route_dcp]]

proc p3_b91_require_one {kind objects label} {
    if {[llength $objects] != 1} {
        error "Build 91 expected one $kind for $label, found [llength $objects]"
    }
    return [lindex $objects 0]
}

proc p3_b91_net {name} {
    return [p3_b91_require_one net [get_nets -quiet [list $name]] $name]
}

proc p3_b91_bus {base width label} {
    set result [list]
    for {set bit 0} {$bit < $width} {incr bit} {
        lappend result [p3_b91_net "${base}\[${bit}\]"]
    }
    return $result
}

proc p3_b91_q_net {cell_name} {
    set cell [p3_b91_require_one cell \
        [get_cells -quiet [list $cell_name]] $cell_name]
    set qpin [p3_b91_require_one pin \
        [get_pins -quiet -of_objects $cell \
            -filter {DIRECTION == OUT && REF_PIN_NAME == Q}] \
        "${cell_name}/Q"]
    return [p3_b91_require_one net \
        [get_nets -quiet -of_objects $qpin] "${cell_name}/Q net"]
}

proc p3_b91_true {object property} {
    set value [get_property $property $object]
    return [expr {$value eq "1" || [string equal -nocase $value "true"]}]
}

proc p3_b91_reconnect_probe {port_name nets tag} {
    set width [llength $nets]
    set port [p3_b91_require_one debug_port \
        [get_debug_ports -quiet [list $port_name]] $port_name]
    if {[get_property PORT_WIDTH $port] != $width} {
        error "$port_name width is [get_property PORT_WIDTH $port], expected $width"
    }
    for {set bit 0} {$bit < $width} {incr bit} {
        set pin_name "${port_name}\[${bit}\]"
        set pin [p3_b91_require_one pin \
            [get_pins -quiet [list $pin_name]] $pin_name]
        set old_net [p3_b91_require_one net \
            [get_nets -quiet -of_objects $pin] "${pin_name} old net"]
        set old_dont_touch [p3_b91_true $old_net DONT_TOUCH]
        if {$old_dont_touch} {
            set_property DONT_TOUCH false $old_net
        }
        disconnect_net -net $old_net -pinlist $pin
        if {$old_dont_touch} {
            set_property DONT_TOUCH true $old_net
        }

        set new_net [lindex $nets $bit]
        set new_dont_touch [p3_b91_true $new_net DONT_TOUCH]
        if {$new_dont_touch} {
            set_property DONT_TOUCH false $new_net
        }
        connect_net -hierarchical -basename "${tag}_${bit}" \
            -net $new_net -objects $pin
        if {$new_dont_touch} {
            set_property DONT_TOUCH true $new_net
        }
    }
}

set_param general.maxThreads 16
set_msg_config -id {Vivado 12-3773} -suppress
set_msg_config -id {Constraints 18-549} -suppress
puts "Opening clean Build 90 routed checkpoint: $input_dcp"
open_checkpoint $input_dcp

if {!$resume_from_build91} {
    foreach name [list \
        {axi_dbg_hub} \
        {u_bd/openpiton_top_i/axis_ila_0} \
        {u_bd/openpiton_top_i/axis_ila_1} \
        {u_bd/openpiton_top_i/axis_ila_2} \
        {u_bd/openpiton_top_i/axis_ila_3} \
        {u_ila_build90}] {
        p3_b91_require_one debug_core [get_debug_cores -quiet [list $name]] $name
    }

    set cva6 \
        {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6}
    set scoreboard "${cva6}/issue_stage_i/i_scoreboard"
    set commit_base "${scoreboard}/commit_instr_id_commit\[0\]"
    set regfile \
        "${cva6}/issue_stage_i/i_issue_read_operands/i_ariane_regfile"
    set commit_pc [p3_b91_bus "${commit_base}\[pc\]" 64 {commit PC}]
    set pc_low [lrange $commit_pc 0 23]

    set gpr_payloads [list]
    foreach reg $gpr_regs {
        set value [list]
        for {set bit 0} {$bit < 40} {incr bit} {
            lappend value \
                [p3_b91_q_net "${regfile}/mem_reg\[${reg}\]\[${bit}\]"]
        }
        set payload [concat $pc_low $value]
        if {[llength $payload] != 64 || \
                [llength [lsort -unique $payload]] != 64} {
            error "Build 91 x${reg} payload is incomplete or aliased"
        }
        lappend gpr_payloads $payload
    }

    for {set ila_index 1} {$ila_index <= 3} {incr ila_index} {
        p3_b91_reconnect_probe \
            "u_bd/openpiton_top_i/axis_ila_${ila_index}/probe0" \
            [lindex $gpr_payloads [expr {$ila_index - 1}]] \
            "${tag_prefix}_ila${ila_index}"
    }

    set fh [open $probe_map w]
    puts $fh "Build 91 probe map (logical bit 0 first)"
    puts $fh "source checkpoint=$input_dcp"
    puts $fh "u_ila_build90: unchanged clean Build 90 commit/CSR/cycle diagnostic"
    for {set index 0} {$index < 3} {incr index} {
        set ila_index [expr {$index + 1}]
        set reg [lindex $gpr_regs $index]
        set name [lindex $gpr_names $index]
        puts $fh "axis_ila_${ila_index} probe0\[23:0\]=commit PC\[23:0\], \[63:24\]=${name}/x${reg}\[39:0\]"
    }
    puts $fh "trigger PC low24=0x7d8aa4; full PC control=0xffffffff807d8aa4"
    puts $fh "functional RTL/cells/drivers changed=none"
    close $fh

    write_checkpoint -force $pre_route_dcp
} else {
    if {![file exists $probe_map] || [file size $probe_map] == 0} {
        error "Build 91 resume requires the existing probe map: $probe_map"
    }
    puts "Resuming from exact Build 91 pre-route checkpoint"
}

puts "Routing only the three Build 91 diagnostic probe loads"
route_design -eco
report_route_status -file $route_report
report_timing_summary -delay_type min_max -max_paths 20 -file $timing_report
report_drc -file $drc_report
write_debug_probes -force $ltx_file
if {![file exists $ltx_file] || [file size $ltx_file] == 0} {
    error "Build 91 LTX is missing or empty: $ltx_file"
}
cd $output_dir
write_device_image -force -file $pdi_file
if {![file exists $pdi_file] || [file size $pdi_file] == 0} {
    error "Build 91 PDI is missing or empty: $pdi_file"
}
write_checkpoint -force $routed_dcp

puts "SUCCESS: Build 91 diagnostic-only udelay image generated"
puts "  PDI:       $pdi_file"
puts "  LTX:       $ltx_file"
puts "  routed DCP:$routed_dcp"
puts "  probe map: $probe_map"
