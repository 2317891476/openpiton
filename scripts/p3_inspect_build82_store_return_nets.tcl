# p3_inspect_build82_store_return_nets.tcl -- Inventory retained nets along
# the WT store-response path before defining the next probe-only ECO.

set default_dcp \
    {D:/p3b81_wbuffer_eco/p3_top_build81_wbuffer_eco_pre_route.dcp}
set default_report {D:/p3b81_wbuffer_eco/build82_store_return_net_query.txt}

if {[llength $argv] > 2} {
    puts "ERROR: expected optional Build 81 pre-route DCP and report path"
    exit 1
}
set input_dcp $default_dcp
set report_file $default_report
if {[llength $argv] >= 1} {
    set input_dcp [file normalize [lindex $argv 0]]
}
if {[llength $argv] == 2} {
    set report_file [file normalize [lindex $argv 1]]
}
if {![file exists $input_dcp]} {
    error "Build 81 pre-route DCP not found: $input_dcp"
}

open_checkpoint $input_dcp
set fh [open $report_file w]
puts $fh "Build 82 retained WT store-response net inventory"
puts $fh "checkpoint=$input_dcp"

proc p3_emit_cell_q {fh label cell_name} {
    set cells [get_cells -quiet [list $cell_name]]
    if {[llength $cells] != 1} {
        puts $fh "$label MISSING_CELL count=[llength $cells] cell=$cell_name"
        return
    }
    set qpins [get_pins -quiet -of_objects $cells \
        -filter {DIRECTION == OUT && NAME =~ */Q}]
    set nets [get_nets -quiet -of_objects $qpins]
    puts $fh "$label cell=$cell_name qpins=$qpins nets=$nets"
}

proc p3_emit_pin_net {fh label pin_name} {
    set pins [get_pins -quiet [list $pin_name]]
    if {[llength $pins] != 1} {
        puts $fh "$label MISSING_PIN count=[llength $pins] pin=$pin_name"
        return
    }
    set nets [get_nets -quiet -of_objects $pins]
    puts $fh "$label pin=$pin_name nets=$nets"
}

proc p3_emit_exact_net {fh label net_name} {
    set nets [get_nets -quiet [list $net_name]]
    puts $fh "$label count=[llength $nets] requested=$net_name nets=$nets"
}

set cache \
    {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6/i_cache_subsystem}
set dcache "${cache}/i_wt_dcache"
set missunit "${dcache}/i_wt_dcache_missunit"
set wbuffer "${dcache}/i_wt_dcache_wbuffer"
set adapter "${cache}/i_adapter"
set req_fifo "${adapter}/i_dcache_data_fifo/i_fifo_v3"
set adapter_rtrn_fifo "${adapter}/i_rtrn_fifo/i_fifo_v3"
set wbuffer_rtrn_fifo "${wbuffer}/i_rtrn_id_fifo"

puts $fh ""
puts $fh "DCACHE_REQUEST_FIFO"
foreach bit {0 1} {
    p3_emit_cell_q $fh "req_status_q${bit}" \
        "${req_fifo}/status_cnt_q_reg\[${bit}\]"
}
p3_emit_cell_q $fh req_read_pointer "${req_fifo}/read_pointer_q_reg\[0\]"
p3_emit_cell_q $fh req_write_pointer "${req_fifo}/write_pointer_q_reg\[0\]"
p3_emit_pin_net $fh req_push "${req_fifo}/write_pointer_q_reg\[0\]/CE"
p3_emit_pin_net $fh req_pop_l15_ack "${req_fifo}/read_pointer_q_reg\[0\]/CE"
p3_emit_pin_net $fh adapter_l15_ack "${adapter}/i_rrarbiter/en_i"
foreach entry {0 1} {
    foreach bit {0 1 2} {
        p3_emit_cell_q $fh "req${entry}_rtype${bit}" \
            "${req_fifo}/mem_q_reg\[${entry}\]\[rtype\]\[${bit}\]"
    }
    p3_emit_cell_q $fh "req${entry}_tid" \
        "${req_fifo}/mem_q_reg\[${entry}\]\[tid\]\[0\]"
}
foreach bit {0 1} {
    p3_emit_exact_net $fh "req_front_rtype${bit}" \
        "${adapter}/dcache_data\[rtype\]\[${bit}\]"
}
p3_emit_exact_net $fh req_front_tid "${adapter}/dcache_data\[tid\]\[0\]"
for {set bit 0} {$bit < 40} {incr bit} {
    p3_emit_exact_net $fh "req_front_paddr${bit}" \
        "${adapter}/dcache_data\[paddr\]\[${bit}\]"
}

puts $fh ""
puts $fh "ADAPTER_RETURN_FIFO"
foreach bit {0 1} {
    p3_emit_cell_q $fh "adapter_rtrn_status_q${bit}" \
        "${adapter_rtrn_fifo}/status_cnt_q_reg\[${bit}\]"
}
p3_emit_cell_q $fh adapter_rtrn_read_pointer \
    "${adapter_rtrn_fifo}/read_pointer_q_reg\[0\]"
p3_emit_cell_q $fh adapter_rtrn_write_pointer \
    "${adapter_rtrn_fifo}/write_pointer_q_reg\[0\]"
p3_emit_pin_net $fh adapter_rtrn_push \
    "${adapter_rtrn_fifo}/write_pointer_q_reg\[0\]/CE"
p3_emit_pin_net $fh adapter_rtrn_pop \
    "${adapter_rtrn_fifo}/read_pointer_q_reg\[0\]/CE"
foreach bit {0 1 2 3} {
    p3_emit_pin_net $fh "adapter_input_returntype${bit}" \
        "${adapter_rtrn_fifo}/mem_q_reg\[0\]\[l15_returntype\]\[${bit}\]/D"
    p3_emit_exact_net $fh "adapter_front_returntype${bit}" \
        "${cache}/rtrn_fifo_data\[l15_returntype\]\[${bit}\]"
}
p3_emit_pin_net $fh adapter_input_tid \
    "${adapter_rtrn_fifo}/mem_q_reg\[0\]\[l15_threadid\]\[0\]/D"
p3_emit_exact_net $fh adapter_front_tid \
    "${cache}/rtrn_fifo_data\[l15_threadid\]"

puts $fh ""
puts $fh "MISSUNIT"
foreach bit {0 1} {
    p3_emit_cell_q $fh "stores_inflight_q${bit}" \
        "${missunit}/stores_inflight_q_reg\[${bit}\]"
}
for {set port 0} {$port < 3} {incr port} {
    p3_emit_exact_net $fh "miss_rtrn_vld${port}" \
        "${dcache}/miss_rtrn_vld\[${port}\]"
}
for {set bit 0} {$bit < 5} {incr bit} {
    p3_emit_exact_net $fh "miss_rtrn_id${bit}" \
        "${dcache}/miss_rtrn_id\[${bit}\]"
}

puts $fh ""
puts $fh "WBUFFER_RETURN_FIFO"
foreach bit {0 1} {
    p3_emit_cell_q $fh "wbuffer_rtrn_status_q${bit}" \
        "${wbuffer_rtrn_fifo}/status_cnt_q_reg\[${bit}\]"
}
p3_emit_cell_q $fh wbuffer_rtrn_read_pointer \
    "${wbuffer_rtrn_fifo}/read_pointer_q_reg\[0\]"
p3_emit_cell_q $fh wbuffer_rtrn_write_pointer \
    "${wbuffer_rtrn_fifo}/write_pointer_q_reg\[0\]"
p3_emit_pin_net $fh wbuffer_rtrn_push \
    "${wbuffer_rtrn_fifo}/write_pointer_q_reg\[0\]/CE"
p3_emit_pin_net $fh wbuffer_rtrn_pop \
    "${wbuffer_rtrn_fifo}/read_pointer_q_reg\[0\]/CE"
foreach entry {0 1} {
    p3_emit_cell_q $fh "wbuffer_rtrn_mem${entry}_tid" \
        "${wbuffer_rtrn_fifo}/mem_q_reg\[${entry}\]\[0\]"
}
p3_emit_pin_net $fh wbuffer_rtrn_input_tid \
    "${wbuffer_rtrn_fifo}/mem_q_reg\[0\]\[0\]/D"
p3_emit_exact_net $fh wbuffer_evict "${wbuffer}/evict3_out"

puts $fh ""
puts $fh "WBUFFER_TX_SLOTS"
foreach slot {0 1} {
    p3_emit_cell_q $fh "tx${slot}_valid" \
        "${wbuffer}/tx_stat_q_reg\[${slot}\]\[vld\]"
    for {set bit 0} {$bit < 3} {incr bit} {
        p3_emit_cell_q $fh "tx${slot}_ptr${bit}" \
            "${wbuffer}/tx_stat_q_reg\[${slot}\]\[ptr\]\[${bit}\]"
    }
}

close $fh
puts "SUCCESS: Build 82 store-return inventory written to $report_file"
close_design
