# p3_build87_time_csr_eco.tcl -- Add a single-hart P3 architectural TIME CSR
# control to the board-validated Build 86 design.
#
# CSR 0xc01 returns cycle_q >> 7, matching the P3 30 MHz / 128 = 234375 Hz
# platform timebase.  The same address suppresses the synthesized illegal-CSR
# flag.  All other CSR results and exceptions remain unchanged.

set default_dcp \
    {D:/p3b86_store_queue_eco/p3_top_build86_store_queue_eco_pre_route.dcp}
set default_output_dir {D:/p3b87_time_csr_eco}

if {[llength $argv] > 2} {
    error "expected optional Build 86 pre-route DCP and output directory"
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
    error "Build 86 pre-route DCP not found: $input_dcp"
}

file mkdir $output_dir
set output_base "${output_dir}/p3_top_build87_time_csr_eco"
set mapping_file "${output_base}_eco_map.txt"
set pre_route_dcp "${output_base}_pre_route.dcp"
set route_report "${output_base}_route_status.rpt"
set timing_report "${output_base}_timing_summary.rpt"
set drc_report "${output_base}_drc.rpt"
set ltx_file "${output_base}.ltx"
set pdi_file "${output_base}.pdi"
set resume_from_build87 [string equal -nocase \
    [file normalize $input_dcp] [file normalize $pre_route_dcp]]

proc p3_require_one {kind objects name} {
    if {[llength $objects] != 1} {
        error "required exact $kind matched [llength $objects] objects: $name"
    }
    return [lindex $objects 0]
}

proc p3_require_net_candidates {name candidates} {
    set matches [list]
    foreach candidate $candidates {
        set matches [concat $matches [get_nets -quiet [list $candidate]]]
    }
    return [p3_require_one net [lsort -unique $matches] $name]
}

proc p3_q_net {cell_name} {
    set cell [p3_require_one cell [get_cells -quiet [list $cell_name]] $cell_name]
    set qpin [p3_require_one pin [get_pins -quiet -of_objects $cell \
        -filter {DIRECTION == OUT && REF_PIN_NAME == Q}] "${cell_name}/Q"]
    return [p3_require_one net [get_nets -quiet -of_objects $qpin] \
        "${cell_name}/Q net"]
}

proc p3_property_is_true {object property} {
    set value [get_property $property $object]
    return [expr {$value eq "1" || [string equal -nocase $value "true"]}]
}

proc p3_connect_existing {net pin} {
    set dont_touch [p3_property_is_true $net DONT_TOUCH]
    if {$dont_touch} {
        set_property DONT_TOUCH false $net
    }
    connect_net -hierarchical -net $net -objects $pin
    if {$dont_touch} {
        set_property DONT_TOUCH true $net
    }
}

proc p3_disconnect_sinks {sink_pins} {
    foreach pin $sink_pins {
        set current_net [p3_require_one net \
            [get_nets -quiet -of_objects $pin] "$pin current net"]
        set dont_touch [p3_property_is_true $current_net DONT_TOUCH]
        if {$dont_touch} {
            set_property DONT_TOUCH false $current_net
        }
        disconnect_net -net $current_net -pinlist $pin
        if {$dont_touch} {
            set_property DONT_TOUCH true $current_net
        }
    }
}

proc p3_insert_mux {cell_name old_net true_net select_net sink_pins} {
    if {[llength $sink_pins] == 0} {
        error "$cell_name has no downstream sink pins"
    }
    set cell [create_cell -reference LUT3 $cell_name]
    # O = I2 ? I1 : I0
    set_property INIT 8'hCA $cell
    p3_connect_existing $old_net [get_pins ${cell_name}/I0]
    p3_connect_existing $true_net [get_pins ${cell_name}/I1]
    p3_connect_existing $select_net [get_pins ${cell_name}/I2]

    set output_net [create_net "${cell_name}_n"]
    connect_net -net $output_net -objects [get_pins ${cell_name}/O]
    p3_disconnect_sinks $sink_pins
    connect_net -hierarchical -net $output_net -objects $sink_pins
    return $output_net
}

proc p3_insert_zero_when_selected {cell_name old_net select_net sink_pins} {
    if {[llength $sink_pins] == 0} {
        error "$cell_name has no downstream sink pins"
    }
    set cell [create_cell -reference LUT2 $cell_name]
    # O = I0 & ~I1
    set_property INIT 4'h2 $cell
    p3_connect_existing $old_net [get_pins ${cell_name}/I0]
    p3_connect_existing $select_net [get_pins ${cell_name}/I1]

    set output_net [create_net "${cell_name}_n"]
    connect_net -net $output_net -objects [get_pins ${cell_name}/O]
    p3_disconnect_sinks $sink_pins
    connect_net -hierarchical -net $output_net -objects $sink_pins
    return $output_net
}

set_param general.maxThreads 16
set_msg_config -id {Vivado 12-3773} -suppress
set_msg_config -id {Constraints 18-549} -suppress
puts "Opening Build 86 pre-route ECO checkpoint: $input_dcp"
open_checkpoint $input_dcp

foreach name [list \
    {axi_dbg_hub} \
    {u_bd/openpiton_top_i/axis_ila_0} \
    {u_bd/openpiton_top_i/axis_ila_1} \
    {u_bd/openpiton_top_i/axis_ila_2} \
    {u_bd/openpiton_top_i/axis_ila_3}] {
    p3_require_one debug_core [get_debug_cores -quiet [list $name]] $name
}

if {!$resume_from_build87} {
    set cva6 \
        {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6}
    set csr "${cva6}/csr_regfile_i"

    set csr_addr [list]
    for {set bit 0} {$bit < 12} {incr bit} {
        lappend csr_addr [p3_require_net_candidates "CSR address bit $bit" [list \
            "${cva6}/csr_addr_ex_csr\[${bit}\]" \
            "${cva6}/ex_stage_i/csr_buffer_i/csr_addr_ex_csr\[${bit}\]"]]
    }

    set sel_low_cell "${cva6}/p3_b87_time_sel_low"
    set sel_high_cell "${cva6}/p3_b87_time_sel_high"
    set addr_sel_cell "${cva6}/p3_b87_time_addr_sel"
    set commit_sel_cell "${cva6}/p3_b87_time_commit_sel"
    set sel_cell "${cva6}/p3_b87_time_sel"
    set low_cell [create_cell -reference LUT6 $sel_low_cell]
    set high_cell [create_cell -reference LUT6 $sel_high_cell]
    set addr_cell [create_cell -reference LUT2 $addr_sel_cell]
    set commit_cell [create_cell -reference LUT5 $commit_sel_cell]
    set and_cell [create_cell -reference LUT2 $sel_cell]
    # Address low bits [5:0] == 6'b000001.
    set_property INIT 64'h0000000000000002 $low_cell
    # Address high bits [11:6] == 6'b110000.
    set_property INIT 64'h0001000000000000 $high_cell
    set_property INIT 4'h8 $addr_cell
    # I0=commit valid; I4:I1=FU[3:0].  Match valid=1 and FU=4'b0110.
    set_property INIT 32'h00002000 $commit_cell
    set_property INIT 4'h8 $and_cell
    for {set bit 0} {$bit < 6} {incr bit} {
        p3_connect_existing [lindex $csr_addr $bit] \
            [get_pins "${sel_low_cell}/I${bit}"]
        p3_connect_existing [lindex $csr_addr [expr {$bit + 6}]] \
            [get_pins "${sel_high_cell}/I${bit}"]
    }
    set sel_low_net [create_net "${sel_low_cell}_n"]
    set sel_high_net [create_net "${sel_high_cell}_n"]
    set addr_sel_net [create_net "${addr_sel_cell}_n"]
    set commit_sel_net [create_net "${commit_sel_cell}_n"]
    set time_sel_net [create_net "${sel_cell}_n"]
    connect_net -net $sel_low_net -objects [get_pins ${sel_low_cell}/O]
    connect_net -net $sel_high_net -objects [get_pins ${sel_high_cell}/O]
    connect_net -net $addr_sel_net -objects [get_pins ${addr_sel_cell}/O]
    connect_net -net $commit_sel_net -objects [get_pins ${commit_sel_cell}/O]
    connect_net -net $time_sel_net -objects [get_pins ${sel_cell}/O]
    connect_net -net $sel_low_net -objects [get_pins ${addr_sel_cell}/I0]
    connect_net -net $sel_high_net -objects [get_pins ${addr_sel_cell}/I1]

    set scoreboard "${cva6}/issue_stage_i/i_scoreboard"
    set commit_base "${scoreboard}/commit_instr_id_commit\[0\]"
    set commit_valid [p3_require_net_candidates "commit valid" [list \
        "${commit_base}\[valid\]"]]
    p3_connect_existing $commit_valid [get_pins ${commit_sel_cell}/I0]
    for {set bit 0} {$bit < 4} {incr bit} {
        set fu_net [p3_require_net_candidates "commit FU bit $bit" [list \
            "${commit_base}\[fu\]\[${bit}\]"]]
        p3_connect_existing $fu_net \
            [get_pins "${commit_sel_cell}/I[expr {$bit + 1}]"]
    }
    connect_net -net $addr_sel_net -objects [get_pins ${sel_cell}/I0]
    connect_net -net $commit_sel_net -objects [get_pins ${sel_cell}/I1]

    set wdata_nets [list]
    for {set bit 0} {$bit < 64} {incr bit} {
        lappend wdata_nets [p3_require_net_candidates \
            "commit write-data bit $bit" [list \
                "${cva6}/wdata_commit_id\[0\]\[${bit}\]" \
                "${cva6}/wdata_commit_id\[0\]_27\[${bit}\]"]]
    }

    for {set bit 0} {$bit < 64} {incr bit} {
        set old_net [lindex $wdata_nets $bit]
        set segments [get_nets -quiet -segments $old_net]
        set sinks [get_pins -quiet -of_objects $segments \
            -filter {DIRECTION == IN}]
        if {$bit < 57} {
            set cycle_net [p3_q_net \
                "${csr}/cycle_q_reg\[[expr {$bit + 7}]\]"]
            p3_insert_mux "${cva6}/p3_b87_time_wdata_${bit}" \
                $old_net $cycle_net $time_sel_net $sinks
        } else {
            p3_insert_zero_when_selected \
                "${cva6}/p3_b87_time_wdata_${bit}" \
                $old_net $time_sel_net $sinks
        }
    }

    set exception_net [p3_require_net_candidates "CSR illegal/valid flag" [list \
        "${cva6}/csr_exception_csr_commit\[cause\]\[1\]"]]
    set exception_segments [get_nets -quiet -segments $exception_net]
    set exception_sinks [get_pins -quiet -of_objects $exception_segments \
        -filter {DIRECTION == IN}]
    p3_insert_zero_when_selected "${cva6}/p3_b87_time_exception" \
        $exception_net $time_sel_net $exception_sinks

    set eco_cells [get_cells -quiet "${cva6}/p3_b87_time_*"]
    if {[llength $eco_cells] != 70} {
        error "Build 87 created [llength $eco_cells] ECO cells, expected 70"
    }

    puts "Placing 70 Build 87 functional ECO cells"
    # VP1902 checkpoints use Vivado Advanced Flow.  Its dedicated incremental
    # placement mode is -eco with non-timing-driven placement; the legacy
    # -post_place_opt option and an unqualified -eco invocation are rejected.
    place_design -eco -no_timing_driven
    foreach cell $eco_cells {
        if {[get_property LOC $cell] eq ""} {
            error "Build 87 ECO cell remains unplaced: $cell"
        }
    }

    set fh [open $mapping_file w]
    puts $fh "Build 87 single-hart CSR_TIME functional ECO"
    puts $fh "selector: CSR address 0xc01, commit valid, and commit FU=CSR"
    puts $fh "data: commit write-data[56:0] = cycle_q[63:7] when selected"
    puts $fh "data: commit write-data[63:57] = 0 when selected"
    puts $fh "exception: synthesized illegal/valid flag forced low when selected"
    puts $fh "all non-0xc01 commit data and CSR exception behavior unchanged"
    puts $fh "frequency contract: 30 MHz / 128 = 234375 Hz"
    puts $fh "debug payload: unchanged Build 86 four-ILA map"
    close $fh

    write_checkpoint -force $pre_route_dcp
} else {
    if {![file exists $mapping_file] || [file size $mapping_file] == 0} {
        error "Build 87 resume requires the existing ECO map: $mapping_file"
    }
    puts "Resuming from exact Build 87 pre-route checkpoint"
}

puts "Routing Build 87 TIME CSR functional ECO"
route_design -eco
report_route_status -file $route_report
write_debug_probes -force $ltx_file
if {![file exists $ltx_file] || [file size $ltx_file] == 0} {
    error "write_debug_probes did not create a non-empty LTX: $ltx_file"
}
cd $output_dir
write_device_image -force -file $pdi_file
if {![file exists $pdi_file] || [file size $pdi_file] == 0} {
    error "write_device_image did not create a non-empty PDI: $pdi_file"
}
report_timing_summary -delay_type min_max -max_paths 20 -file $timing_report
report_drc -file $drc_report

puts "SUCCESS: Build 87 single-hart CSR_TIME ECO generated"
puts "  pre-route DCP: $pre_route_dcp"
puts "  PDI:           $pdi_file"
puts "  LTX:           $ltx_file"
puts "  ECO map:       $mapping_file"
