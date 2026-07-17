# p3_build83_orphan_return_eco.tcl -- Capture the cycle history that creates a
# write-buffer return ID with no corresponding valid transaction slot.
#
# This is a probe-only ECO from Build 82.  It changes only existing ILA probe
# loads and leaves the functional Build 66 hardware and SD payload unchanged.

set default_dcp \
    {D:/p3b82_store_return_eco/p3_top_build82_store_return_eco_pre_route.dcp}
set default_output_dir {D:/p3b83_orphan_return_eco}

if {[llength $argv] > 2} {
    error "expected optional Build 82 pre-route DCP and output directory"
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
    error "Build 82 pre-route DCP not found: $input_dcp"
}

file mkdir $output_dir
set output_base "${output_dir}/p3_top_build83_orphan_return_eco"
set mapping_file "${output_base}_probe_map.txt"
set pre_route_dcp "${output_base}_pre_route.dcp"
set route_report "${output_base}_route_status.rpt"
set timing_report "${output_base}_timing_summary.rpt"
set drc_report "${output_base}_drc.rpt"
set ltx_file "${output_base}.ltx"
set pdi_file "${output_base}.pdi"
set resume_from_build83 [string equal -nocase \
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

proc p3_q_net {cell_name} {
    set cell [p3_require_one cell [get_cells -quiet [list $cell_name]] $cell_name]
    set qpin [p3_require_one pin [get_pins -quiet -of_objects $cell \
        -filter {DIRECTION == OUT && NAME =~ */Q}] "${cell_name}/Q"]
    return [p3_require_one net [get_nets -quiet -of_objects $qpin] \
        "${cell_name}/Q net"]
}

proc p3_pin_net {pin_name} {
    set pin [p3_require_one pin [get_pins -quiet [list $pin_name]] $pin_name]
    return [p3_require_one net [get_nets -quiet -of_objects $pin] \
        "${pin_name} net"]
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
        set pin_name "${port_name}\[${bit}\]"
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
puts "Opening Build 82 pre-route ECO checkpoint: $input_dcp"
open_checkpoint $input_dcp

foreach name [list \
    {axi_dbg_hub} \
    {u_bd/openpiton_top_i/axis_ila_0} \
    {u_bd/openpiton_top_i/axis_ila_1} \
    {u_bd/openpiton_top_i/axis_ila_2} \
    {u_bd/openpiton_top_i/axis_ila_3}] {
    p3_require_one debug_core [get_debug_cores -quiet [list $name]] $name
}

if {!$resume_from_build83} {
    set cva6 \
        {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6}
    set cache "${cva6}/i_cache_subsystem"
    set dcache "${cache}/i_wt_dcache"
    set missunit "${dcache}/i_wt_dcache_missunit"
    set wbuffer "${dcache}/i_wt_dcache_wbuffer"
    set adapter "${cache}/i_adapter"
    set req_fifo "${adapter}/i_dcache_data_fifo/i_fifo_v3"
    set adapter_fifo "${adapter}/i_rtrn_fifo/i_fifo_v3"
    set return_fifo "${wbuffer}/i_rtrn_id_fifo"

    set return_status [list]
    foreach bit {0 1} {
        lappend return_status \
            [p3_q_net "${return_fifo}/status_cnt_q_reg\[${bit}\]"]
    }
    set return_read_ptr \
        [p3_q_net "${return_fifo}/read_pointer_q_reg\[0\]"]
    set return_write_ptr \
        [p3_q_net "${return_fifo}/write_pointer_q_reg\[0\]"]
    set return_mem_tid [list]
    foreach entry {0 1} {
        lappend return_mem_tid \
            [p3_q_net "${return_fifo}/mem_q_reg\[${entry}\]\[0\]"]
    }
    set return_input_tid \
        [p3_pin_net "${return_fifo}/mem_q_reg\[0\]\[0\]/D"]

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

    # Every ILA starts with these seven fields.  Hardware Manager can match
    # one concrete orphan case without relying on an RTL-generated trigger:
    # count, read pointer, both stored IDs, and both transaction valid bits.
    set orphan_common [concat $return_status [list $return_read_ptr] \
        $return_mem_tid $tx_valid]

    set req_status [list]
    foreach bit {0 1} {
        lappend req_status [p3_q_net "${req_fifo}/status_cnt_q_reg\[${bit}\]"]
    }
    set req_read_ptr [p3_q_net "${req_fifo}/read_pointer_q_reg\[0\]"]
    set req_write_ptr [p3_q_net "${req_fifo}/write_pointer_q_reg\[0\]"]
    set req_rtype [list]
    set req_tid [list]
    set req_paddr_low [list]
    foreach entry {0 1} {
        foreach bit {0 1} {
            lappend req_rtype \
                [p3_q_net "${req_fifo}/mem_q_reg\[${entry}\]\[rtype\]\[${bit}\]"]
        }
        lappend req_tid \
            [p3_q_net "${req_fifo}/mem_q_reg\[${entry}\]\[tid\]\[0\]"]
        for {set bit 0} {$bit < 10} {incr bit} {
            lappend req_paddr_low \
                [p3_q_net "${req_fifo}/mem_q_reg\[${entry}\]\[paddr\]\[${bit}\]"]
        }
    }

    set stores_inflight [list]
    foreach bit {0 1} {
        lappend stores_inflight \
            [p3_q_net "${missunit}/stores_inflight_q_reg\[${bit}\]"]
    }
    set dirty_rd_en [p3_require_net "${cache}/i_wt_dcache_wbuffer/dirty_rd_en"]
    set miss_req [p3_require_net "${dcache}/miss_req\[2\]"]
    set wbuffer_empty [p3_require_net "${cva6}/dcache_commit_wbuffer_empty"]
    set no_st_pending [p3_require_net "${cva6}/no_st_pending_ex"]
    set evict [p3_require_net "${wbuffer}/evict3_out"]

    set adapter_status \
        [p3_q_net "${adapter_fifo}/status_cnt_q_reg\[0\]"]
    set adapter_read_ptr \
        [p3_q_net "${adapter_fifo}/read_pointer_q_reg\[0\]"]
    set adapter_write_ptr \
        [p3_q_net "${adapter_fifo}/write_pointer_q_reg\[0\]"]
    set adapter_input_rtype [list]
    set adapter_front_rtype [list]
    foreach bit {0 1 2 3} {
        lappend adapter_input_rtype \
            [p3_pin_net "${adapter_fifo}/mem_q_reg\[0\]\[l15_returntype\]\[${bit}\]/D"]
        lappend adapter_front_rtype \
            [p3_require_net "${cache}/rtrn_fifo_data\[l15_returntype\]\[${bit}\]"]
    }
    set adapter_input_tid \
        [p3_pin_net "${adapter_fifo}/mem_q_reg\[0\]\[l15_threadid\]\[0\]/D"]
    set adapter_mem_rtype [list]
    set adapter_mem_tid [list]
    foreach entry {0 1} {
        foreach bit {0 1 2 3} {
            lappend adapter_mem_rtype \
                [p3_q_net "${adapter_fifo}/mem_q_reg\[${entry}\]\[l15_returntype\]\[${bit}\]"]
        }
        lappend adapter_mem_tid \
            [p3_q_net "${adapter_fifo}/mem_q_reg\[${entry}\]\[l15_threadid\]\[0\]"]
    }

    set checked [list]
    set dirty [list]
    set txblock_byte0 [list]
    foreach entry {0 1 2 3 4 5 6 7} {
        lappend checked \
            [p3_q_net "${wbuffer}/wbuffer_q_reg\[${entry}\]\[checked\]"]
        lappend dirty [p3_require_net "${wbuffer}/dirty\[${entry}\]"]
        lappend txblock_byte0 \
            [p3_q_net "${wbuffer}/wbuffer_q_reg\[${entry}\]\[txblock\]\[0\]"]
    }

    set return_fifo_state [concat $return_status \
        [list $return_read_ptr $return_write_ptr] \
        $return_mem_tid [list $return_input_tid]]

    set request_entries [concat \
        [lrange $req_rtype 0 1] [lrange $req_tid 0 0] \
        [lrange $req_paddr_low 0 9] \
        [lrange $req_rtype 2 3] [lrange $req_tid 1 1] \
        [lrange $req_paddr_low 10 19]]
    set request_front [concat \
        [lrange $req_rtype 0 1] [lrange $req_tid 0 0] \
        [lrange $req_rtype 2 3] [lrange $req_tid 1 1]]
    set request_state [concat $req_status \
        [list $req_read_ptr $req_write_ptr]]

    set adapter_state [list \
        $adapter_status $adapter_read_ptr $adapter_write_ptr]
    set adapter_input [concat $adapter_input_rtype [list $adapter_input_tid]]
    set adapter_memory [concat \
        [lrange $adapter_mem_rtype 0 3] [lrange $adapter_mem_tid 0 0] \
        [lrange $adapter_mem_rtype 4 7] [lrange $adapter_mem_tid 1 1]]

    set ila0_payload [concat $orphan_common $request_state \
        $request_entries $stores_inflight [list $dirty_rd_en] \
        $tx_ptr $tx_be [list $miss_req $wbuffer_empty $no_st_pending]]

    set ila1_payload [concat $orphan_common $adapter_state \
        $adapter_input $adapter_front_rtype $adapter_memory \
        $stores_inflight $return_fifo_state [list $evict] \
        $tx_ptr $checked $request_state $request_front [list $miss_req]]

    set ila2_payload [concat $orphan_common $adapter_state \
        $adapter_input $adapter_front_rtype $adapter_memory \
        $stores_inflight $return_fifo_state [list $evict] \
        $tx_ptr $tx_be [list $dirty_rd_en $miss_req $wbuffer_empty]]

    set ila3_payload [concat $orphan_common $return_fifo_state \
        [list $evict] $tx_ptr $tx_be $checked $dirty $txblock_byte0 \
        [list $dirty_rd_en $miss_req $wbuffer_empty]]

    if {[llength $ila0_payload] != 65 || \
        [llength $ila1_payload] != 64 || \
        [llength $ila2_payload] != 64 || \
        [llength $ila3_payload] != 64} {
        error "Build 83 payload widths ila0=[llength $ila0_payload] ila1=[llength $ila1_payload] ila2=[llength $ila2_payload] ila3=[llength $ila3_payload]"
    }

    p3_reconnect_probe \
        {u_bd/openpiton_top_i/axis_ila_0/probe0} 1 \
        [lrange $ila0_payload 0 0] p3_build83_ila0_trigger
    for {set port 1} {$port <= 4} {incr port} {
        set first [expr {1 + ($port - 1) * 16}]
        set last [expr {$first + 15}]
        p3_reconnect_probe \
            "u_bd/openpiton_top_i/axis_ila_0/probe${port}" 16 \
            [lrange $ila0_payload $first $last] "p3_build83_ila0_p${port}"
    }
    p3_reconnect_probe \
        {u_bd/openpiton_top_i/axis_ila_1/probe0} 64 \
        $ila1_payload p3_build83_ila1
    p3_reconnect_probe \
        {u_bd/openpiton_top_i/axis_ila_2/probe0} 64 \
        $ila2_payload p3_build83_ila2
    p3_reconnect_probe \
        {u_bd/openpiton_top_i/axis_ila_3/probe0} 64 \
        $ila3_payload p3_build83_ila3

    set fh [open $mapping_file w]
    puts $fh "Build 83 probe map (least-significant bit first)"
    puts $fh "common bits 0..6: return FIFO count\[1:0\], read pointer, mem0 TID, mem1 TID, tx_valid\[1:0\]"
    puts $fh "axis_ila_0: common, request FIFO entries/address low10, stores-inflight, allocation and tx slot state"
    puts $fh "axis_ila_1: common, adapter return ingress/FIFO, return-ID FIFO, checked state, request identity"
    puts $fh "axis_ila_2: common, adapter/missunit return path, return-ID FIFO, tx pointers/byte enables"
    puts $fh "axis_ila_3: common, return-ID FIFO/evict, tx slots, checked/dirty/txblock summaries"
    puts $fh "board trigger position 896; first case is count=1, readptr=0, mem0_tid=0, tx_valid0=0"
    close $fh

    write_checkpoint -force $pre_route_dcp
} else {
    if {![file exists $mapping_file] || [file size $mapping_file] == 0} {
        error "Build 83 resume requires the existing probe map: $mapping_file"
    }
    puts "Resuming from exact Build 83 pre-route checkpoint"
}

puts "Routing only Build 83 ILA probe loads"
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

puts "SUCCESS: Build 83 orphan return-ID ECO generated"
puts "  pre-route DCP: $pre_route_dcp"
puts "  PDI:           $pdi_file"
puts "  LTX:           $ltx_file"
puts "  probe map:     $mapping_file"
