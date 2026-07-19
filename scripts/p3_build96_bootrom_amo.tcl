# Build 96 -- diagnostic-only incremental AMO handshake ILA rewiring.
#
# This opens the post-fix Build 90 routed DCP, reconnects only existing ILA
# probe pins, ECO-routes those probe nets, then writes a matching DCP/LTX/PDI.
# It neither synthesizes nor places functional RTL and does not change SD data.

set default_dcp {D:/p3b90_time_csr_rtl/huaprop3_build90_time_csr_rtl.runs/impl_1/p3_top_routed.dcp}
set default_output_dir {D:/p3b96_bootrom_amo}
set output_stem {p3_top_build96_bootrom_amo}
set tag_prefix {p3_build96}
if {[llength $argv] > 2} { error "expected optional DCP and output dir" }
set input_dcp $default_dcp
set output_dir $default_output_dir
if {[llength $argv] >= 1} { set input_dcp [file normalize [lindex $argv 0]] }
if {[llength $argv] == 2} { set output_dir [file normalize [lindex $argv 1]] }
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
set resume [string equal -nocase [file normalize $input_dcp] [file normalize $pre_route_dcp]]

proc req1 {kind objects label} {
    if {[llength $objects] != 1} {
        error "expected one $kind for $label, found [llength $objects]"
    }
    return [lindex $objects 0]
}
proc pnet {name} {
    return [req1 net [lsort -unique [get_nets -quiet [list $name]]] $name]
}
proc pbus {base width} {
    set nets [list]
    for {set bit 0} {$bit < $width} {incr bit} {
        lappend nets [pnet "${base}\[${bit}\]"]
    }
    return $nets
}
proc pqnet {cell_name} {
    set cell [req1 cell [get_cells -quiet [list $cell_name]] $cell_name]
    set qpin [req1 pin [get_pins -quiet -of_objects $cell \
        -filter {DIRECTION == OUT && REF_PIN_NAME == Q}] "${cell_name}/Q"]
    return [req1 net [get_nets -quiet -of_objects $qpin] "${cell_name}/Q net"]
}
proc ptrue {obj prop} {
    set value [get_property $prop $obj]
    return [expr {$value eq "1" || [string equal -nocase $value "true"]}]
}
proc reconnect {port_name nets tag} {
    set width [llength $nets]
    set port [req1 debug_port [get_debug_ports -quiet [list $port_name]] $port_name]
    if {[get_property PORT_WIDTH $port] != $width} {
        error "$port_name width mismatch: [get_property PORT_WIDTH $port] vs $width"
    }
    for {set bit 0} {$bit < $width} {incr bit} {
        set pin_name "${port_name}\[${bit}\]"
        set pin [req1 pin [get_pins -quiet [list $pin_name]] $pin_name]
        set old [req1 net [get_nets -quiet -of_objects $pin] "${pin_name} old"]
        set old_dt [ptrue $old DONT_TOUCH]
        if {$old_dt} { set_property DONT_TOUCH false $old }
        disconnect_net -net $old -pinlist $pin
        if {$old_dt} { set_property DONT_TOUCH true $old }
        set new [lindex $nets $bit]
        set new_dt [ptrue $new DONT_TOUCH]
        if {$new_dt} { set_property DONT_TOUCH false $new }
        connect_net -hierarchical -basename "${tag}_${bit}" -net $new -objects $pin
        if {$new_dt} { set_property DONT_TOUCH true $new }
    }
}

set_param general.maxThreads 16
set_msg_config -id {Vivado 12-3773} -suppress
set_msg_config -id {Constraints 18-549} -suppress
puts "Opening post-fix Build 90 routed checkpoint: $input_dcp"
open_checkpoint $input_dcp

if {!$resume} {
    foreach core_name [list \
        axi_dbg_hub \
        u_bd/openpiton_top_i/axis_ila_0 \
        u_bd/openpiton_top_i/axis_ila_1 \
        u_bd/openpiton_top_i/axis_ila_2 \
        u_bd/openpiton_top_i/axis_ila_3 \
        u_ila_build90] {
        req1 debug_core [get_debug_cores -quiet [list $core_name]] $core_name
    }

    set cva6 {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6}
    set dcache "${cva6}/i_cache_subsystem/i_wt_dcache"
    set missunit "${dcache}/i_wt_dcache_missunit"
    set l15 {u_openpiton/system_inst/chip/tile0/l15/l15}
    set l2 {u_openpiton/system_inst/chip/tile0/l2}
    set scoreboard "${cva6}/issue_stage_i/i_scoreboard"
    set commit "${scoreboard}/commit_instr_id_commit\[0\]"

    set pc24 [pbus "${commit}\[pc\]" 24]
    set pc16 [lrange $pc24 0 15]

    # ILA1: AMO source from the core/amo_buffer boundary.
    set src_req [pnet "${cva6}/amo_req\[req\]"]
    set src_ack [pnet "${cva6}/amo_resp\[ack\]"]
    set no_store_pending [pnet "${cva6}/no_st_pending_ex"]
    set src_addr [pbus "${cva6}/amo_req\[operand_a\]" 32]
    set src_size [pnet "${cva6}/amo_req\[size\]\[0\]"]
    set ila1 [concat $pc24 [list $src_req $src_ack $no_store_pending] $src_addr [list $src_size] [lrepeat 4 $src_req]]
    if {[llength $ila1] != 64} { error "ILA1 width [llength $ila1]" }
    reconnect "u_bd/openpiton_top_i/axis_ila_1/probe0" $ila1 "${tag_prefix}_source"

    # ILA2: the AMO state-machine boundary.  The stable AMO state proves that
    # mem_data_ack_i has not occurred; AMO_WAIT proves it did occur and shifts
    # the first missing event to the atomic return path.
    set dc_req [pnet "${dcache}/amo_req\[req\]"]
    set dc_req_q [pnet "${dcache}/amo_req_q"]
    set dc_resp_ack [pnet "${dcache}/amo_resp\[ack\]"]
    set mu_req [pnet "${missunit}/amo_req\[req\]"]
    set mu_req_q [pnet "${missunit}/amo_req_q"]
    set mu_resp_ack [pnet "${missunit}/amo_resp\[ack\]"]
    set mu_state [list \
        [pqnet "${missunit}/FSM_sequential_state_q_reg\[0\]"] \
        [pqnet "${missunit}/FSM_sequential_state_q_reg\[1\]"] \
        [pqnet "${missunit}/FSM_sequential_state_q_reg\[2\]"]]
    set ila2_base [concat $pc16 \
        [list $src_req $src_ack $no_store_pending] \
        [list $dc_req $dc_req_q $dc_resp_ack] \
        [list $mu_req $mu_req_q $mu_resp_ack] $mu_state]
    set ila2 [concat $ila2_base [lrepeat [expr {64 - [llength $ila2_base]}] $mu_req]]
    if {[llength $ila2] != 64} { error "ILA2 width [llength $ila2]" }
    reconnect "u_bd/openpiton_top_i/axis_ila_2/probe0" $ila2 "${tag_prefix}_missunit"

    # ILA3: confirmed retained L1.5/NoC request and return boundaries.  These
    # distinguish an AMO stalled before NoC1 from one awaiting a NOC2 return.
    set noc1_req_val [pnet "${l15}/l15_noc1buffer_req_val"]
    set creditman_req [pnet "${l15}/creditman_noc1_req"]
    set noc1_enc_ack [pnet "${l15}/noc1encoder_noc1buffer_req_ack"]
    set noc1_rtr_val [pnet "${l15}/noc1buffer/buffer_router_valid_noc1"]
    set noc1_cmd_val [list]
    for {set bit 0} {$bit < 8} {incr bit} {
        lappend noc1_cmd_val [pnet "${l15}/noc1buffer/command_buffer_val_reg\[${bit}\]__0"]
    }
    set noc2_data_val [pnet "${l15}/noc2_data_val"]
    set noc2_pipe_val [pnet "${l15}/pipeline/noc2_data_val"]
    set noc2_simple_val [pnet "${l15}/simplenocbuffer/noc2_data_val"]
    set l2_mshr_vals [list]
    foreach cell_pattern [list \
        "${l2}/mshr_wrap/valid_S2_f_reg\[0\]" \
        "${l2}/mshr_wrap/valid_S2_f_reg\[1\]" \
        "${l2}/mshr_wrap/valid_S2_f_reg\[2\]" \
        "${l2}/mshr_wrap/valid_S2_f_reg\[3\]"] {
        lappend l2_mshr_vals [pqnet $cell_pattern]
    }
    set ila3_base [concat $pc16 \
        [list $noc1_req_val $creditman_req $noc1_enc_ack $noc1_rtr_val] \
        $noc1_cmd_val \
        [list $noc2_data_val $noc2_pipe_val $noc2_simple_val] $l2_mshr_vals]
    set ila3 [concat $ila3_base [lrepeat [expr {64 - [llength $ila3_base]}] $noc1_req_val]]
    if {[llength $ila3] != 64} { error "ILA3 width [llength $ila3]" }
    reconnect "u_bd/openpiton_top_i/axis_ila_3/probe0" $ila3 "${tag_prefix}_adapter"

    set fh [open $probe_map w]
    puts $fh {Build 96 probe map (bit 0 first, 64 bits per ILA)}
    puts $fh "source=$input_dcp"
    puts $fh {ILA1 [23:0]=commit_PC_low [24]=source_amo_req [25]=source_amo_resp_ack [26]=no_st_pending [27:58]=AMO_paddr_low32 [59]=AMO_size0 [60:63]=source_req_fill}
    puts $fh {ILA2 [15:0]=commit_PC_low [16:18]=source_req/ack/no_st_pending [19:21]=dcache_req/req_q/ack [22:24]=missunit_req/req_q/ack [25:27]=missunit_state [28:63]=missunit_req_fill}
    puts $fh {ILA3 [15:0]=commit_PC_low [16]=noc1_req_val [17]=creditman_req [18]=noc1_encoder_ack [19]=noc1_router_val [20:27]=noc1_cmd_val[0:7] [28:30]=noc2_ingress/pipeline/simple_val [31:34]=l2_mshr_valid[0:3] [35:63]=noc1_req_val_fill}
    puts $fh {missunit state: IDLE=0 DRAIN=1 AMO=2 FLUSH=3 STORE_WAIT=4 LOAD_WAIT=5 AMO_WAIT=6}
    puts $fh {stable pre-OpenSBI boundary: bootrom PC=0x000000fff1010040, amoswap.w target=0x84000040}
    close $fh
    write_checkpoint -force $pre_route_dcp
} else {
    puts "Resuming Build 96 from pre-route checkpoint"
}

puts "ECO-routing Build 96 diagnostic probe loads"
route_design -eco
report_route_status -file $route_report
report_timing_summary -delay_type min_max -max_paths 20 -file $timing_report
report_drc -file $drc_report
write_debug_probes -force $ltx_file
if {![file exists $ltx_file] || [file size $ltx_file] == 0} { error "LTX missing: $ltx_file" }
cd $output_dir
write_device_image -force -file $pdi_file
if {![file exists $pdi_file] || [file size $pdi_file] == 0} { error "PDI missing: $pdi_file" }
write_checkpoint -force $routed_dcp
puts "SUCCESS: Build 96 incremental AMO diagnostic image generated"
puts "  PDI: $pdi_file"
puts "  LTX: $ltx_file"
puts "  DCP: $routed_dcp"
puts "  map: $probe_map"
