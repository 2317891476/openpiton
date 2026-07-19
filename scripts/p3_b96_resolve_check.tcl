# Read-only synthesized-net audit for the Build 96 bootrom AMO diagnostic.
# This must pass before the diagnostic-only ECO reconnects an existing ILA.
#
# Usage:
#   vivado -mode batch -source scripts/p3_b96_resolve_check.tcl -tclargs \
#     <routed.dcp> <report.txt>

if {[llength $argv] != 2} {
    error "Usage: p3_b96_resolve_check.tcl <routed.dcp> <report.txt>"
}
set input_dcp [file normalize [lindex $argv 0]]
set report_file [file normalize [lindex $argv 1]]
if {![file exists $input_dcp] || [file size $input_dcp] == 0} {
    error "Routed checkpoint is missing or empty: $input_dcp"
}
file mkdir [file dirname $report_file]

proc emit_exact {fh label name} {
    set nets [lsort -unique [get_nets -quiet [list $name]]]
    puts $fh "\nEXACT $label count=[llength $nets]"
    foreach net $nets { puts $fh "  [get_property NAME $net]" }
}

proc emit_glob {fh label pattern} {
    set nets [lsort -unique [get_nets -quiet -hier -filter "NAME =~ ${pattern}"]]
    puts $fh "\nGLOB $label count=[llength $nets] pattern=${pattern}"
    foreach net $nets { puts $fh "  [get_property NAME $net]" }
}

proc emit_pin_net {fh label pin_name} {
    set pins [lsort -unique [get_pins -quiet -hier [list $pin_name]]]
    set nets [list]
    foreach pin $pins {
        set nets [concat $nets [get_nets -quiet -of_objects $pin]]
    }
    set nets [lsort -unique $nets]
    puts $fh "\nPIN_NET $label pins=[llength $pins] nets=[llength $nets]"
    foreach pin $pins { puts $fh "  PIN [get_property NAME $pin]" }
    foreach net $nets { puts $fh "  NET [get_property NAME $net]" }
}

proc emit_pin_glob {fh label pattern} {
    set pins [lsort -unique [get_pins -quiet -hier -filter "NAME =~ ${pattern}"]]
    puts $fh "\nPIN_GLOB $label count=[llength $pins] pattern=${pattern}"
    foreach pin $pins {
        set nets [lsort -unique [get_nets -quiet -of_objects $pin]]
        puts $fh "  PIN [get_property NAME $pin] nets=[llength $nets]"
        foreach net $nets { puts $fh "    NET [get_property NAME $net]" }
    }
}

puts "Opening routed checkpoint read-only: $input_dcp"
open_checkpoint $input_dcp
set fh [open $report_file w]
puts $fh "Build 96 bootrom AMO probe resolution audit"
puts $fh "checkpoint=$input_dcp"

set cva6 {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6}
set dcache "${cva6}/i_cache_subsystem/i_wt_dcache"
set missunit "${dcache}/i_wt_dcache_missunit"
set adapter "${cva6}/i_cache_subsystem/i_adapter"

# AMO source and response at the CVA6/cache boundary.
foreach spec [list \
    [list source_amo_req "${cva6}/amo_req\[req\]"] \
    [list source_amo_resp_ack "${cva6}/amo_resp\[ack\]"] \
    [list source_no_store_pending "${cva6}/no_st_pending_ex"] \
    [list dcache_amo_req "${dcache}/amo_req\[req\]"] \
    [list dcache_amo_req_q "${dcache}/amo_req_q"] \
    [list dcache_amo_resp_ack "${dcache}/amo_resp\[ack\]"] \
    [list missunit_amo_req "${missunit}/amo_req\[req\]"] \
    [list missunit_amo_req_q "${missunit}/amo_req_q"] \
    [list missunit_amo_resp_ack "${missunit}/amo_resp\[ack\]"] \
] {
    emit_exact $fh [lindex $spec 0] [lindex $spec 1]
}

# Retained source fields and every interface candidate needed to select a
# single probe endpoint.  Do not infer a signal from a similarly named cell.
foreach spec [list \
    [list source_operand_a "${cva6}/amo_req\[operand_a\]*"] \
    [list source_amo_op "${cva6}/amo_req\[amo_op\]*"] \
    [list source_size "${cva6}/amo_req\[size\]*"] \
    [list missunit_memory "${missunit}/*mem_*"] \
    [list missunit_state "${missunit}/FSM_sequential_state_q_reg*"] \
    [list adapter_dcache "${adapter}/*dcache*"] \
    [list adapter_arb "${adapter}/arb_*"] \
    [list adapter_l15_request "${adapter}/*l15_req*"] \
    [list adapter_l15_return "${adapter}/*l15_rtrn*"] \
    [list adapter_return_fifo "${adapter}/*rtrn_fifo*"] \
] {
    emit_glob $fh [lindex $spec 0] [lindex $spec 1]
}

# Interface pins provide a fail-closed view even when Vivado has renamed the
# connecting net during optimization.  These are the only endpoints Build 96
# may use for the request/return handshakes below.
foreach spec [list \
    [list miss_req "${missunit}/mem_data_req_o"] \
    [list miss_ack "${missunit}/mem_data_ack_i"] \
    [list miss_return_valid "${missunit}/mem_rtrn_vld_i"] \
    [list miss_return_type0 "${missunit}/mem_rtrn_i\[rtype\]\[0\]"] \
    [list miss_return_type1 "${missunit}/mem_rtrn_i\[rtype\]\[1\]"] \
    [list miss_return_type2 "${missunit}/mem_rtrn_i\[rtype\]\[2\]"] \
    [list adapter_dcache_req "${adapter}/dcache_data_req_i"] \
    [list adapter_dcache_ack "${adapter}/dcache_data_ack_o"] \
    [list adapter_dcache_return "${adapter}/dcache_rtrn_vld_o"] \
    [list adapter_l15_val "${adapter}/l15_req_o\[l15_val\]"] \
    [list adapter_l15_req_ack "${adapter}/l15_req_o\[l15_req_ack\]"] \
    [list adapter_l15_return_val "${adapter}/l15_rtrn_i\[l15_val\]"] \
    [list adapter_l15_return_atomic "${adapter}/l15_rtrn_i\[l15_atomic\]"] \
    [list adapter_dcache_fifo_full "${adapter}/i_dcache_data_fifo/full_o"] \
    [list adapter_dcache_fifo_empty "${adapter}/i_dcache_data_fifo/empty_o"] \
    [list adapter_dcache_fifo_push "${adapter}/i_dcache_data_fifo/push_i"] \
    [list adapter_dcache_fifo_pop "${adapter}/i_dcache_data_fifo/pop_i"] \
    [list adapter_return_fifo_full "${adapter}/i_rtrn_fifo/full_o"] \
    [list adapter_return_fifo_empty "${adapter}/i_rtrn_fifo/empty_o"] \
    [list adapter_return_fifo_push "${adapter}/i_rtrn_fifo/push_i"] \
    [list adapter_return_fifo_pop "${adapter}/i_rtrn_fifo/pop_i"] \
] {
    emit_pin_net $fh [lindex $spec 0] [lindex $spec 1]
}

# These wildcard queries avoid bracket matching in Vivado's object-pattern
# parser and establish whether a flattened hierarchy retains the desired
# boundary pins at all.
foreach spec [list \
    [list missunit_memory_pins "*i_wt_dcache_missunit*mem_*"] \
    [list adapter_dcache_pins "*i_adapter*dcache_*"] \
    [list adapter_l15_pins "*i_adapter*l15_*"] \
    [list adapter_fifo_pins "*i_adapter*i_*fifo*"] \
] {
    emit_pin_glob $fh [lindex $spec 0] [lindex $spec 1]
}

close $fh
close_design
puts "SUCCESS: Build 96 AMO probe audit written to $report_file"
