# p3_build82_store_return_eco.tcl -- Trace accepted WT stores through the
# adapter request/return FIFOs and the write-buffer return-ID FIFO.
#
# This is a probe-only ECO from Build 81.  It does not change functional RTL.

set default_dcp \
    {D:/p3b81_wbuffer_eco/p3_top_build81_wbuffer_eco_pre_route.dcp}
set default_output_dir {D:/p3b82_store_return_eco}

if {[llength $argv] > 2} {
    puts "ERROR: expected optional Build 81 pre-route DCP and output directory"
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
    error "Build 81 pre-route DCP not found: $input_dcp"
}

file mkdir $output_dir
set output_base "${output_dir}/p3_top_build82_store_return_eco"
set mapping_file "${output_base}_probe_map.txt"
set pre_route_dcp "${output_base}_pre_route.dcp"
set route_report "${output_base}_route_status.rpt"
set timing_report "${output_base}_timing_summary.rpt"
set drc_report "${output_base}_drc.rpt"
set ltx_file "${output_base}.ltx"
set pdi_file "${output_base}.pdi"
set resume_from_build82 [string equal -nocase \
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
puts "Opening Build 81 pre-route checkpoint: $input_dcp"
open_checkpoint $input_dcp

foreach name [list \
    {axi_dbg_hub} \
    {u_bd/openpiton_top_i/axis_ila_0} \
    {u_bd/openpiton_top_i/axis_ila_1} \
    {u_bd/openpiton_top_i/axis_ila_2} \
    {u_bd/openpiton_top_i/axis_ila_3}] {
    p3_require_one debug_core [get_debug_cores -quiet [list $name]] $name
}

if {!$resume_from_build82} {
    set cva6 \
        {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6}
    set cache "${cva6}/i_cache_subsystem"
    set dcache "${cache}/i_wt_dcache"
    set missunit "${dcache}/i_wt_dcache_missunit"
    set wbuffer "${dcache}/i_wt_dcache_wbuffer"
    set adapter "${cache}/i_adapter"
    set req_fifo "${adapter}/i_dcache_data_fifo/i_fifo_v3"
    set adapter_rtrn_fifo "${adapter}/i_rtrn_fifo/i_fifo_v3"
    set wbuffer_rtrn_fifo "${wbuffer}/i_rtrn_id_fifo"

    set tx_valid [list]
    set tx_ptr [list]
    for {set slot 0} {$slot < 2} {incr slot} {
        lappend tx_valid [p3_q_net "${wbuffer}/tx_stat_q_reg\[${slot}\]\[vld\]"]
        for {set bit 0} {$bit < 3} {incr bit} {
            lappend tx_ptr \
                [p3_q_net "${wbuffer}/tx_stat_q_reg\[${slot}\]\[ptr\]\[${bit}\]"]
        }
    }
    set trigger [lindex $tx_valid 1]

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
        for {set bit 0} {$bit < 16} {incr bit} {
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

    set adapter_status \
        [p3_q_net "${adapter_rtrn_fifo}/status_cnt_q_reg\[0\]"]
    set adapter_read_ptr \
        [p3_q_net "${adapter_rtrn_fifo}/read_pointer_q_reg\[0\]"]
    set adapter_write_ptr \
        [p3_q_net "${adapter_rtrn_fifo}/write_pointer_q_reg\[0\]"]
    set adapter_input_rtype [list]
    foreach bit {0 1 2 3} {
        lappend adapter_input_rtype \
            [p3_pin_net "${adapter_rtrn_fifo}/mem_q_reg\[0\]\[l15_returntype\]\[${bit}\]/D"]
    }
    set adapter_input_tid \
        [p3_pin_net "${adapter_rtrn_fifo}/mem_q_reg\[0\]\[l15_threadid\]\[0\]/D"]
    set adapter_front_rtype [list]
    foreach bit {0 1 2 3} {
        lappend adapter_front_rtype \
            [p3_require_net "${cache}/rtrn_fifo_data\[l15_returntype\]\[${bit}\]"]
    }
    set adapter_mem_rtype [list]
    set adapter_mem_tid [list]
    foreach entry {0 1} {
        foreach bit {0 1 2 3} {
            lappend adapter_mem_rtype \
                [p3_q_net "${adapter_rtrn_fifo}/mem_q_reg\[${entry}\]\[l15_returntype\]\[${bit}\]"]
        }
        lappend adapter_mem_tid \
            [p3_q_net "${adapter_rtrn_fifo}/mem_q_reg\[${entry}\]\[l15_threadid\]\[0\]"]
    }

    set wbuffer_rtrn_status [list]
    foreach bit {0 1} {
        lappend wbuffer_rtrn_status \
            [p3_q_net "${wbuffer_rtrn_fifo}/status_cnt_q_reg\[${bit}\]"]
    }
    set wbuffer_rtrn_read_ptr \
        [p3_q_net "${wbuffer_rtrn_fifo}/read_pointer_q_reg\[0\]"]
    set wbuffer_rtrn_write_ptr \
        [p3_q_net "${wbuffer_rtrn_fifo}/write_pointer_q_reg\[0\]"]
    set wbuffer_rtrn_mem_tid [list]
    foreach entry {0 1} {
        lappend wbuffer_rtrn_mem_tid \
            [p3_q_net "${wbuffer_rtrn_fifo}/mem_q_reg\[${entry}\]\[0\]"]
    }
    set wbuffer_rtrn_input_tid \
        [p3_pin_net "${wbuffer_rtrn_fifo}/mem_q_reg\[0\]\[0\]/D"]
    set evict [p3_require_net "${wbuffer}/evict3_out"]

    set checked [list]
    set dirty [list]
    foreach entry {0 1 2 3 4 5 6 7} {
        lappend checked \
            [p3_q_net "${wbuffer}/wbuffer_q_reg\[${entry}\]\[checked\]"]
        lappend dirty [p3_require_net "${wbuffer}/dirty\[${entry}\]"]
    }
    set txblock_23 [list]
    foreach entry {2 3} {
        for {set bit 0} {$bit < 8} {incr bit} {
            lappend txblock_23 \
                [p3_q_net "${wbuffer}/wbuffer_q_reg\[${entry}\]\[txblock\]\[${bit}\]"]
        }
    }

    set request_fillers [list $trigger {*}$tx_valid \
        {*}$req_status $req_read_ptr $req_write_ptr]
    set request_payload [concat \
        [list $trigger] $tx_valid $req_status \
        [list $req_read_ptr $req_write_ptr] \
        [lrange $req_rtype 0 1] [lrange $req_tid 0 0] \
        [lrange $req_rtype 2 3] [lrange $req_tid 1 1] \
        $stores_inflight $tx_ptr \
        [list $dirty_rd_en $miss_req $wbuffer_empty $no_st_pending] \
        $req_paddr_low $request_fillers]

    set adapter_fillers [concat \
        [list $trigger] $tx_valid [list $adapter_status \
        $adapter_read_ptr $adapter_write_ptr] $stores_inflight \
        $req_status [list $req_read_ptr $req_write_ptr] \
        $wbuffer_rtrn_status \
        [list $wbuffer_rtrn_read_ptr $wbuffer_rtrn_write_ptr $evict]]
    set adapter_payload [concat \
        [list $trigger] $tx_valid \
        [list $adapter_status $adapter_read_ptr $adapter_write_ptr] \
        $adapter_input_rtype [list $adapter_input_tid] \
        $adapter_front_rtype \
        [lrange $adapter_mem_rtype 0 3] [lrange $adapter_mem_tid 0 0] \
        [lrange $adapter_mem_rtype 4 7] [lrange $adapter_mem_tid 1 1] \
        $stores_inflight $req_status [list $req_read_ptr $req_write_ptr] \
        $wbuffer_rtrn_status \
        [list $wbuffer_rtrn_read_ptr $wbuffer_rtrn_write_ptr] \
        $wbuffer_rtrn_mem_tid [list $wbuffer_rtrn_input_tid $evict] \
        $checked $adapter_fillers]

    set return_payload [concat \
        [list $trigger] $tx_valid $stores_inflight $wbuffer_rtrn_status \
        [list $wbuffer_rtrn_read_ptr $wbuffer_rtrn_write_ptr] \
        $wbuffer_rtrn_mem_tid \
        [list $wbuffer_rtrn_input_tid $evict $wbuffer_empty \
        $dirty_rd_en $miss_req] \
        $tx_ptr $checked $dirty $txblock_23 \
        [list $adapter_status $adapter_read_ptr $adapter_write_ptr] \
        $req_status [list $req_read_ptr $req_write_ptr] \
        [list $trigger {*}$tx_valid]]

    if {[llength $request_payload] != 64 || \
        [llength $adapter_payload] != 64 || \
        [llength $return_payload] != 64} {
        error "Build 82 payload widths request=[llength $request_payload] adapter=[llength $adapter_payload] return=[llength $return_payload]"
    }

    p3_reconnect_probe \
        {u_bd/openpiton_top_i/axis_ila_0/probe0} 1 \
        [list $trigger] p3_build82_trigger
    p3_reconnect_probe \
        {u_bd/openpiton_top_i/axis_ila_1/probe0} 64 \
        $request_payload p3_build82_request
    p3_reconnect_probe \
        {u_bd/openpiton_top_i/axis_ila_2/probe0} 64 \
        $adapter_payload p3_build82_adapter
    p3_reconnect_probe \
        {u_bd/openpiton_top_i/axis_ila_3/probe0} 64 \
        $return_payload p3_build82_return

    set fh [open $mapping_file w]
    puts $fh "Build 82 probe map (least-significant bit first)"
    puts $fh "common trigger: tx_stat_q\[1\].vld rising"
    puts $fh "axis_ila_0/probe0: common trigger; probe1..4: Build 81 commit PC"
    puts $fh "axis_ila_1 request: trigger, tx slots, request FIFO state/data, inflight count, tx pointers, allocation gates, request paddr\[15:0\]"
    puts $fh "axis_ila_2 adapter: trigger, adapter input/front/FIFO return type and TID, request/return FIFO state, checked state"
    puts $fh "axis_ila_3 return: trigger, inflight count, write-buffer return FIFO/TID/evict, tx pointers, dirty and entry2/3 txblock state"
    close $fh

    write_checkpoint -force $pre_route_dcp
} else {
    if {![file exists $mapping_file] || [file size $mapping_file] == 0} {
        error "Build 82 resume requires the existing probe map: $mapping_file"
    }
    puts "Resuming from exact Build 82 pre-route checkpoint"
}

puts "Routing only Build 82 ILA probe loads"
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

puts "SUCCESS: Build 82 WT store-return ECO generated"
puts "  pre-route DCP: $pre_route_dcp"
puts "  PDI:           $pdi_file"
puts "  LTX:           $ltx_file"
puts "  probe map:     $mapping_file"
