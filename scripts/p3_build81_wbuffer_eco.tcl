# p3_build81_wbuffer_eco.tcl -- Expand a persistent Linux FENCE stall into
# byte-level WT D-cache write-buffer and transaction-slot state.
#
# The functional Build 66 design is unchanged.  This post-route ECO starts
# from the Build 80 pre-route checkpoint and reconnects only existing ILA
# probe loads; axis_ila_0 retains the complete commit PC.

set default_dcp \
    {D:/p3b80_trap_csr_eco/p3_top_build80_trap_csr_eco_pre_route.dcp}
set default_output_dir {D:/p3b81_wbuffer_eco}

if {[llength $argv] > 2} {
    puts "ERROR: expected optional Build 80 pre-route DCP and output directory"
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
    puts "ERROR: Build 80 pre-route DCP not found: $input_dcp"
    exit 1
}

file mkdir $output_dir
set output_base "${output_dir}/p3_top_build81_wbuffer_eco"
set mapping_file "${output_base}_probe_map.txt"
set pre_route_dcp "${output_base}_pre_route.dcp"
set route_report "${output_base}_route_status.rpt"
set timing_report "${output_base}_timing_summary.rpt"
set drc_report "${output_base}_drc.rpt"
set ltx_file "${output_base}.ltx"
set pdi_file "${output_base}.pdi"
set resume_from_build81 [string equal -nocase \
    [file normalize $input_dcp] [file normalize $pre_route_dcp]]

proc p3_require_one {kind objects name} {
    if {[llength $objects] != 1} {
        error "required exact $kind matched [llength $objects] objects: $name"
    }
    return [lindex $objects 0]
}

proc p3_require_net {name} {
    return [p3_require_one net [get_nets -quiet [list $name]] $name]
}

proc p3_require_cell {name} {
    return [p3_require_one cell [get_cells -quiet [list $name]] $name]
}

proc p3_q_net {cell_name} {
    set cell [p3_require_cell $cell_name]
    set qpin [p3_require_one pin [get_pins -quiet -of_objects $cell \
        -filter {DIRECTION == OUT && NAME =~ */Q}] "${cell_name}/Q"]
    return [p3_require_one net [get_nets -quiet -of_objects $qpin] \
        "${cell_name}/Q net"]
}

proc p3_property_is_true {object property} {
    set value [get_property $property $object]
    return [expr {$value eq "1" || [string equal -nocase $value "true"]}]
}

proc p3_reconnect_probe {port_name width nets tag} {
    if {[llength $nets] != $width} {
        error "$port_name received [llength $nets] nets, expected $width"
    }
    set port [p3_require_one debug_port \
        [get_debug_ports -quiet [list $port_name]] $port_name]
    if {[get_property PORT_WIDTH $port] != $width} {
        error "$port_name width is [get_property PORT_WIDTH $port], expected $width"
    }
    for {set bit 0} {$bit < $width} {incr bit} {
        set pin_name "${port_name}\[$bit\]"
        set pin [p3_require_one pin [get_pins -quiet [list $pin_name]] $pin_name]
        set old_net [p3_require_one net \
            [get_nets -quiet -of_objects $pin] "$pin_name existing net"]
        set old_dont_touch [p3_property_is_true $old_net DONT_TOUCH]
        if {$old_dont_touch} {
            set_property DONT_TOUCH false $old_net
        }
        disconnect_net -net $old_net -pinlist $pin
        if {$old_dont_touch} {
            set_property DONT_TOUCH true $old_net
        }
        set new_net [lindex $nets $bit]
        set new_dont_touch [p3_property_is_true $new_net DONT_TOUCH]
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
puts "Opening Build 80 pre-route ECO checkpoint: $input_dcp"
open_checkpoint $input_dcp

foreach name [list \
    {axi_dbg_hub} \
    {u_bd/openpiton_top_i/axis_ila_0} \
    {u_bd/openpiton_top_i/axis_ila_1} \
    {u_bd/openpiton_top_i/axis_ila_2} \
    {u_bd/openpiton_top_i/axis_ila_3}] {
    p3_require_one debug_core [get_debug_cores -quiet [list $name]] $name
}

if {!$resume_from_build81} {
    set cva6 \
        {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6}
    set scoreboard "${cva6}/issue_stage_i/i_scoreboard"
    set commit_base "${scoreboard}/commit_instr_id_commit\[0\]"
    set wbuffer \
        "${cva6}/i_cache_subsystem/i_wt_dcache/i_wt_dcache_wbuffer"

    set dirty_bits [list]
    set txblock_bits [list]
    set checked_bits [list]
    for {set entry 0} {$entry < 8} {incr entry} {
        lappend checked_bits \
            [p3_q_net "${wbuffer}/wbuffer_q_reg\[${entry}\]\[checked\]"]
        for {set byte 0} {$byte < 8} {incr byte} {
            lappend dirty_bits \
                [p3_q_net "${wbuffer}/wbuffer_q_reg\[${entry}\]\[dirty\]\[${byte}\]"]
            lappend txblock_bits \
                [p3_q_net "${wbuffer}/wbuffer_q_reg\[${entry}\]\[txblock\]\[${byte}\]"]
        }
    }

    set tx_valid [list]
    set tx_ptr [list]
    set tx_be [list]
    for {set slot 0} {$slot < 2} {incr slot} {
        lappend tx_valid \
            [p3_q_net "${wbuffer}/tx_stat_q_reg\[${slot}\]\[vld\]"]
        for {set bit 0} {$bit < 3} {incr bit} {
            lappend tx_ptr \
                [p3_q_net "${wbuffer}/tx_stat_q_reg\[${slot}\]\[ptr\]\[${bit}\]"]
        }
        for {set bit 0} {$bit < 8} {incr bit} {
            lappend tx_be \
                [p3_q_net "${wbuffer}/tx_stat_q_reg\[${slot}\]\[be\]\[${bit}\]"]
        }
    }

    set commit_valid [p3_require_net "${commit_base}\[valid\]"]
    set commit_ack [p3_require_net "${scoreboard}/commit_ack\[0\]"]
    set commit_fu [list]
    for {set bit 0} {$bit < 4} {incr bit} {
        lappend commit_fu [p3_require_net "${commit_base}\[fu\]\[${bit}\]"]
    }
    set commit_op [list]
    for {set bit 0} {$bit < 8} {incr bit} {
        lappend commit_op [p3_require_net "${commit_base}\[op\]\[${bit}\]"]
    }
    set no_st_pending [p3_require_net "${cva6}/no_st_pending_ex"]
    set wbuffer_empty [p3_require_net "${cva6}/dcache_commit_wbuffer_empty"]
    set miss_req [p3_require_net \
        "${cva6}/i_cache_subsystem/i_wt_dcache/miss_req\[2\]"]
    # This combinational grant is promoted one hierarchy level by synthesis.
    set dirty_rd_en [p3_require_net \
        "${cva6}/i_cache_subsystem/i_wt_dcache_wbuffer/dirty_rd_en"]
    set check_en_q [p3_q_net "${wbuffer}/check_en_q_reg"]
    set check_en_q1 [p3_q_net "${wbuffer}/check_en_q1_reg"]
    set evict [p3_require_net "${wbuffer}/evict3_out"]
    # The legacy p3_dbg_core_bus is derived from a BUFG-driven synchronizer.
    # Adding any new load in that cone forces an unsupported Versal clock
    # topology update.  Duplicate seven local checked Q bits as explicit safe
    # fillers instead; all causal write-buffer state remains present.
    set safe_fillers [lrange $checked_bits 0 6]
    set load_miss_req [p3_require_net \
        "${cva6}/i_cache_subsystem/i_wt_dcache/miss_req\[0\]"]
    set dirty_ptr [list]
    for {set bit 0} {$bit < 3} {incr bit} {
        lappend dirty_ptr [p3_require_net \
            "${cva6}/i_cache_subsystem/i_wt_dcache_wbuffer/dirty_ptr\[${bit}\]"]
    }

    set control [concat \
        [list $commit_valid $commit_ack] $commit_fu $commit_op \
        [list $no_st_pending $wbuffer_empty] $checked_bits $tx_valid \
        $tx_ptr $tx_be \
        [list $miss_req $dirty_rd_en $check_en_q $check_en_q1 $evict] \
        $safe_fillers [list $load_miss_req] $dirty_ptr]
    if {[llength $dirty_bits] != 64 || [llength $txblock_bits] != 64 || \
        [llength $control] != 64} {
        error "Build 81 payload widths dirty=[llength $dirty_bits] txblock=[llength $txblock_bits] control=[llength $control]"
    }

    p3_reconnect_probe \
        {u_bd/openpiton_top_i/axis_ila_1/probe0} 64 \
        $dirty_bits p3_build81_dirty
    p3_reconnect_probe \
        {u_bd/openpiton_top_i/axis_ila_2/probe0} 64 \
        $txblock_bits p3_build81_txblock
    p3_reconnect_probe \
        {u_bd/openpiton_top_i/axis_ila_3/probe0} 64 \
        $control p3_build81_control

    set fh [open $mapping_file w]
    puts $fh "Build 81 probe map (least-significant bit first)"
    puts $fh "axis_ila_0/probe1..4: unchanged Build 80 commit PC\[63:0\]"
    puts $fh "axis_ila_1/probe0\[entry*8 +: 8\]: wbuffer_q\[entry\].dirty\[7:0\]"
    puts $fh "axis_ila_2/probe0\[entry*8 +: 8\]: wbuffer_q\[entry\].txblock\[7:0\]"
    puts $fh "axis_ila_3/probe0\[0\]: commit valid"
    puts $fh "axis_ila_3/probe0\[1\]: commit ack"
    puts $fh "axis_ila_3/probe0\[5:2\]: commit FU"
    puts $fh "axis_ila_3/probe0\[13:6\]: commit op"
    puts $fh "axis_ila_3/probe0\[14\]: no_st_pending_ex"
    puts $fh "axis_ila_3/probe0\[15\]: dcache write-buffer empty"
    puts $fh "axis_ila_3/probe0\[23:16\]: entry checked bits"
    puts $fh "axis_ila_3/probe0\[25:24\]: transaction valid bits"
    puts $fh "axis_ila_3/probe0\[31:26\]: transaction pointers 0,1"
    puts $fh "axis_ila_3/probe0\[47:32\]: transaction byte enables 0,1"
    puts $fh "axis_ila_3/probe0\[48\]: write-buffer miss request"
    puts $fh "axis_ila_3/probe0\[49\]: dirty transaction allocation"
    puts $fh "axis_ila_3/probe0\[51:50\]: tag-check pipeline q/q1"
    puts $fh "axis_ila_3/probe0\[52\]: write-buffer evict"
    puts $fh "axis_ila_3/probe0\[59:53\]: safe duplicate entry checked\[6:0\]"
    puts $fh "axis_ila_3/probe0\[60\]: load-port miss_req\[0\]"
    puts $fh "axis_ila_3/probe0\[63:61\]: dirty arbiter pointer"
    close $fh

    write_checkpoint -force $pre_route_dcp
} else {
    if {![file exists $mapping_file] || [file size $mapping_file] == 0} {
        error "Build 81 resume requires the existing probe map: $mapping_file"
    }
    puts "Resuming from exact Build 81 pre-route checkpoint"
}

puts "Routing only Build 81 ILA probe loads"
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

puts "SUCCESS: Build 81 WT D-cache write-buffer ECO generated"
puts "  pre-route DCP: $pre_route_dcp"
puts "  PDI:           $pdi_file"
puts "  LTX:           $ltx_file"
puts "  probe map:     $mapping_file"
