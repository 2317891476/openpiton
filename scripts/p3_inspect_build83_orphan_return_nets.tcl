# p3_inspect_build83_orphan_return_nets.tcl -- Verify retained nets needed to
# trigger on a return-ID whose transaction slot is no longer valid.

set default_dcp \
    {D:/p3b82_store_return_eco/p3_top_build82_store_return_eco_pre_route.dcp}
set default_report \
    {D:/p3b82_store_return_eco/build83_orphan_return_net_query.txt}

if {[llength $argv] > 2} {
    error "expected optional Build 82 pre-route DCP and report path"
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
    error "Build 82 pre-route DCP not found: $input_dcp"
}

proc p3_emit_exact_net {fh label net_name} {
    set nets [get_nets -quiet [list $net_name]]
    puts $fh "$label count=[llength $nets] requested=$net_name nets=$nets"
}

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

open_checkpoint $input_dcp
set fh [open $report_file w]
puts $fh "Build 83 orphan return-ID trigger inventory"
puts $fh "checkpoint=$input_dcp"

set cva6 \
    {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6}
set cache "${cva6}/i_cache_subsystem"
set dcache "${cache}/i_wt_dcache"
set missunit "${dcache}/i_wt_dcache_missunit"
set wbuffer "${dcache}/i_wt_dcache_wbuffer"
set adapter "${cache}/i_adapter"
set adapter_fifo "${adapter}/i_rtrn_fifo/i_fifo_v3"
set return_fifo "${wbuffer}/i_rtrn_id_fifo"

p3_emit_exact_net $fh rtrn_id "${wbuffer}/rtrn_id"
p3_emit_exact_net $fh rtrn_empty "${wbuffer}/rtrn_empty"
p3_emit_exact_net $fh rtrn_ptr0 "${wbuffer}/rtrn_ptr\[0\]"
p3_emit_exact_net $fh rtrn_ptr1 "${wbuffer}/rtrn_ptr\[1\]"
p3_emit_exact_net $fh rtrn_ptr2 "${wbuffer}/rtrn_ptr\[2\]"
p3_emit_exact_net $fh evict "${wbuffer}/evict3_out"
p3_emit_exact_net $fh miss_rtrn_vld "${dcache}/miss_rtrn_vld\[2\]"
p3_emit_exact_net $fh miss_rtrn_id "${dcache}/miss_rtrn_id\[0\]"
p3_emit_exact_net $fh mem_rtrn_vld "${missunit}/mem_rtrn_vld_i"
p3_emit_exact_net $fh mem_rtrn_tid "${missunit}/mem_rtrn_i\[tid\]\[0\]"
p3_emit_exact_net $fh mem_rtrn_rtype0 "${missunit}/mem_rtrn_i\[rtype\]\[0\]"
p3_emit_exact_net $fh mem_rtrn_rtype1 "${missunit}/mem_rtrn_i\[rtype\]\[1\]"
p3_emit_exact_net $fh mem_rtrn_rtype2 "${missunit}/mem_rtrn_i\[rtype\]\[2\]"

foreach bit {0 1} {
    p3_emit_cell_q $fh "return_status${bit}" \
        "${return_fifo}/status_cnt_q_reg\[${bit}\]"
}
p3_emit_cell_q $fh return_read_pointer \
    "${return_fifo}/read_pointer_q_reg\[0\]"
p3_emit_cell_q $fh return_write_pointer \
    "${return_fifo}/write_pointer_q_reg\[0\]"
foreach entry {0 1} {
    p3_emit_cell_q $fh "return_mem${entry}_tid" \
        "${return_fifo}/mem_q_reg\[${entry}\]\[0\]"
}
foreach slot {0 1} {
    p3_emit_cell_q $fh "tx${slot}_valid" \
        "${wbuffer}/tx_stat_q_reg\[${slot}\]\[vld\]"
}
foreach bit {0 1} {
    p3_emit_cell_q $fh "stores_inflight${bit}" \
        "${missunit}/stores_inflight_q_reg\[${bit}\]"
    p3_emit_cell_q $fh "adapter_status${bit}" \
        "${adapter_fifo}/status_cnt_q_reg\[${bit}\]"
}

close $fh
close_design
puts "SUCCESS: Build 83 orphan return-ID inventory written to $report_file"
