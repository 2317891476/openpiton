# p3_b93_resolve_check.tcl -- Quick net resolution check for Build 93.
# Opens the Build 92 DCP, tests every candidate probe net, and prints results.
# Does NOT do any ILA rewiring or routing.  Use this to confirm all probe nets
# before running the full Build 93 build script.
set input_dcp {D:/p3b92_udelay_caller/p3_top_build92_udelay_caller_routed.dcp}
if {[llength $argv] >= 1} { set input_dcp [file normalize [lindex $argv 0]] }
puts "Opening: $input_dcp"
open_checkpoint $input_dcp

set cva6 {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6}
set lu "${cva6}/ex_stage_i/lsu_i/i_load_unit"
set cache "${cva6}/i_cache_subsystem"
set dcache "${cache}/i_wt_dcache"
set ctrl "${dcache}/gen_rd_ports\u005b1\u005d.i_wt_dcache_ctrl"
set mu "${dcache}/i_wt_dcache_missunit"
set sb "${cva6}/issue_stage_i/i_scoreboard"
set cmb "${sb}/commit_instr_id_commit\u005b0\u005d"

proc check_net {label name} {
    set n [lsort -unique [get_nets -quiet [list $name]]]
    set cnt [llength $n]
    if {$cnt == 1} {
        puts "OK   $label : [lindex $n 0]"
    } else {
        puts "FAIL $label ($cnt nets) : $name"
    }
}

proc check_cells_qpin {label pattern} {
    set cells [get_cells -quiet -hier -filter "NAME =~ ${pattern}"]
    set cnt [llength $cells]
    if {$cnt >= 1} {
        set cell [lindex $cells 0]
        set qp [get_pins -quiet -of_objects $cell -filter {DIRECTION == OUT && REF_PIN_NAME == Q}]
        set nets [get_nets -quiet -of_objects $qp]
        puts "OKQ  $label ($cnt cells) first=$cell qnet=[lindex $nets 0]"
    } else {
        puts "FAIL $label (0 cells) : $pattern"
    }
}

proc check_cell_exact_qpin {label cell_name} {
    set cells [get_cells -quiet [list $cell_name]]
    set cnt [llength $cells]
    if {$cnt == 1} {
        set cell [lindex $cells 0]
        set qp [get_pins -quiet -of_objects $cell -filter {DIRECTION == OUT && REF_PIN_NAME == Q}]
        set nets [get_nets -quiet -of_objects $qp]
        puts "OKQ  $label : $cell qnet=[lindex $nets 0]"
    } else {
        puts "FAIL $label ($cnt cells) : $cell_name"
    }
}

puts "\n=== load-unit port-1 handshake ==="
check_net lu_data_req    "${lu}/dcache_req_ports_ex_cache\u005b1\u005d\u005bdata_req\u005d"
check_net lu_kill_req    "${lu}/dcache_req_ports_ex_cache\u005b1\u005d\u005bkill_req\u005d"
check_net lu_tag_valid   "${lu}/dcache_req_ports_ex_cache\u005b1\u005d\u005btag_valid\u005d"
check_net lu_data_gnt    "${lu}/dcache_req_ports_cache_ex\u005b1\u005d\u005bdata_gnt\u005d"
check_net lu_data_rvalid "${lu}/dcache_req_ports_cache_ex\u005b1\u005d\u005bdata_rvalid\u005d"
check_net lu_dtlb_hit    "${lu}/dtlb_hit"
check_net lu_ld_trans    "${lu}/ld_translation_req"
check_net lu_page_off    "${lu}/page_offset_matches"
check_net lu_rdata0      "${lu}/dcache_req_ports_cache_ex\u005b1\u005d\u005bdata_rdata\u005d\u005b0\u005d"

puts "\n=== controller handshake ==="
check_net c_miss_req    "${ctrl}/miss_req\u005b0\u005d"
check_net c_miss_replay "${ctrl}/miss_replay\u005b0\u005d"
check_net c_miss_rtrn   "${ctrl}/miss_rtrn_vld\u005b0\u005d"
check_net c_rd_req      "${ctrl}/rd_req_q_reg_0"
check_net c_rd_ack      "${ctrl}/rd_ack\u005b0\u005d"
check_net c_tag         "${ctrl}/dcache_req_ports_ex_cache\u005b1\u005d\u005btag_valid\u005d"
check_net c_kill        "${ctrl}/dcache_req_ports_ex_cache\u005b1\u005d\u005bkill_req\u005d"

puts "\n=== controller FSM bits ==="
for {set b 0} {$b < 3} {incr b} {
    check_net "c_fsm${b}_net0"  "${ctrl}/FSM_sequential_state_q_reg\u005b${b}\u005d_0"
    check_net "c_fsm${b}_plain" "${ctrl}/state_q_reg\u005b${b}\u005d"
    check_cells_qpin "c_fsm${b}_cell" "${ctrl}/FSM_sequential_state_q_reg\u005b${b}\u005d*"
}

puts "\n=== missunit handshake ==="
check_net mu_mr0   "${mu}/miss_req\u005b0\u005d"
check_net mu_mr1   "${mu}/miss_req\u005b1\u005d"
check_net mu_mr2   "${mu}/miss_req\u005b2\u005d"
check_net mu_rep   "${mu}/miss_replay\u005b0\u005d"
check_net mu_pidx1 "${mu}/miss_port_idx\u005b1\u005d"
check_net mu_mq0   "${mu}/miss_req_masked_q\u005b0\u005d"
check_net mu_mq1   "${mu}/miss_req_masked_q\u005b1\u005d"
check_net mu_mq2   "${mu}/miss_req_masked_q\u005b2\u005d"
check_cell_exact_qpin mu_mshrv "${mu}/mshr_vld_q_reg"

puts "\n=== missunit FSM bits ==="
for {set b 0} {$b < 3} {incr b} {
    check_net "mu_fsm${b}_net0"  "${mu}/FSM_sequential_state_q_reg\u005b${b}\u005d_0"
    check_net "mu_fsm${b}_plain" "${mu}/state_q_reg\u005b${b}\u005d"
    check_cells_qpin "mu_fsm${b}_cell" "${mu}/FSM_sequential_state_q_reg\u005b${b}\u005d*"
    check_cells_qpin "mu_fsm${b}_any"  "${mu}/*state_q*reg\u005b${b}\u005d*"
}

puts "\n=== commit PC bus ==="
check_net pc0 "${cmb}\u005bpc\u005d\u005b0\u005d"
check_net pc24 "${cmb}\u005bpc\u005d\u005b24\u005d"

puts "\n=== done ==="
close_design
