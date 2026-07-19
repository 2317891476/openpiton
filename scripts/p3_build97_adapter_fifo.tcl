# Build 97 -- diagnostic-only incremental adapter FIFO / L1.5 ingress probe.
#
# Reuses the post-fix Build 90 functional routed DCP. Build 96 only rewired
# ILA probes, so it contributes no functional state that Build 97 needs. This
# script changes only existing ILA probe connections and ECO routing; it does
# not synthesize, place, change functional RTL, or touch the SD payload.

set default_dcp {D:/p3b90_time_csr_rtl/huaprop3_build90_time_csr_rtl.runs/impl_1/p3_top_routed.dcp}
set default_output_dir {D:/p3b97_adapter_fifo}
set output_stem {p3_top_build97_adapter_fifo}
set tag_prefix {p3_build97}
if {[llength $argv] > 2} { error "expected optional DCP and output dir" }
set input_dcp $default_dcp
set output_dir $default_output_dir
if {[llength $argv] >= 1} { set input_dcp [file normalize [lindex $argv 0]] }
if {[llength $argv] == 2} { set output_dir [file normalize [lindex $argv 1]] }
if {![file exists $input_dcp] || [file size $input_dcp] == 0} {
    error "post-fix Build 90 routed DCP is missing or empty: $input_dcp"
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
proc pinnet {name} {
    set pin [req1 pin [get_pins -quiet -hier [list $name]] $name]
    return [req1 net [lsort -unique [get_nets -quiet -of_objects $pin]] "${name} net"]
}
proc pbus {base width} {
    set nets [list]
    for {set bit 0} {$bit < $width} {incr bit} {
        lappend nets [pnet "${base}\[${bit}\]"]
    }
    return $nets
}
proc pinbus {base width} {
    set nets [list]
    for {set bit 0} {$bit < $width} {incr bit} {
        lappend nets [pinnet "${base}\[${bit}\]"]
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
        u_bd/openpiton_top_i/axis_ila_1 \
        u_bd/openpiton_top_i/axis_ila_2 \
        u_bd/openpiton_top_i/axis_ila_3 \
        u_ila_build90] {
        req1 debug_core [get_debug_cores -quiet [list $core_name]] $core_name
    }

    set tile {u_openpiton/system_inst/chip/tile0}
    set cva6 "${tile}/g_ariane_core.core/ariane/i_cva6"
    set dcache "${cva6}/i_cache_subsystem/i_wt_dcache"
    set missunit "${dcache}/i_wt_dcache_missunit"
    set adapter "${cva6}/i_cache_subsystem/i_adapter"
    set l15 "${tile}/l15/l15"
    set pipeline "${l15}/pipeline"
    set commit "${cva6}/issue_stage_i/i_scoreboard/commit_instr_id_commit\[0\]"
    set pc16 [pbus "${commit}\[pc\]" 16]

    # ILA1: retain the already proven AMO/missunit state and add the actual
    # post-synthesis adapter FIFO state cells. Source-level module-port names
    # are intentionally not used: the routed DCP has optimized them away.
    set src_req [pnet "${cva6}/amo_req\[req\]"]
    set src_ack [pnet "${cva6}/amo_resp\[ack\]"]
    set no_store_pending [pnet "${cva6}/no_st_pending_ex"]
    set dc_req [pnet "${dcache}/amo_req\[req\]"]
    set dc_req_q [pnet "${dcache}/amo_req_q"]
    set dc_resp_ack [pnet "${dcache}/amo_resp\[ack\]"]
    set mu_req [pnet "${missunit}/amo_req\[req\]"]
    set mu_req_q [pnet "${missunit}/amo_req_q"]
    set mu_resp_ack [pnet "${missunit}/amo_resp\[ack\]"]
    set miss_state [list \
        [pqnet "${missunit}/FSM_sequential_state_q_reg\[0\]"] \
        [pqnet "${missunit}/FSM_sequential_state_q_reg\[1\]"] \
        [pqnet "${missunit}/FSM_sequential_state_q_reg\[2\]"]]
    set dcfifo "${adapter}/i_dcache_data_fifo/i_fifo_v3"
    set dcf_count [list \
        [pqnet "${dcfifo}/status_cnt_q_reg\[0\]"] \
        [pqnet "${dcfifo}/status_cnt_q_reg\[1\]"]]
    set dcf_pointers [list \
        [pqnet "${dcfifo}/read_pointer_q_reg\[0\]"] \
        [pqnet "${dcfifo}/write_pointer_q_reg\[0\]"]]
    set dcf_rtypes [list \
        [pqnet "${dcfifo}/mem_q_reg\[0\]\[rtype\]\[0\]"] \
        [pqnet "${dcfifo}/mem_q_reg\[0\]\[rtype\]\[1\]"] \
        [pqnet "${dcfifo}/mem_q_reg\[1\]\[rtype\]\[0\]"] \
        [pqnet "${dcfifo}/mem_q_reg\[1\]\[rtype\]\[1\]"]]
    set ila1_base [concat $pc16 [list \
        $src_req $src_ack $no_store_pending \
        $dc_req $dc_req_q $dc_resp_ack \
        $mu_req $mu_req_q $mu_resp_ack] $miss_state $dcf_count $dcf_pointers $dcf_rtypes]
    set ila1 [concat $ila1_base [lrepeat [expr {64 - [llength $ila1_base]}] $src_req]]
    if {[llength $ila1] != 64} { error "ILA1 width [llength $ila1]" }
    reconnect "u_bd/openpiton_top_i/axis_ila_1/probe0" $ila1 "${tag_prefix}_adapter"

    # ILA2: simultaneous FIFO occupancy and retained L1.5 pipeline stages.
    # A full FIFO with val_s2/val_s3 and NoC1 all low identifies the next
    # boundary without relying on source-level transducer port aliases.
    set val_s2 [pnet "${pipeline}/val_s2"]
    set val_s3 [pnet "${pipeline}/val_s3"]
    set pipe_noc1_val [pnet "${pipeline}/l15_noc1buffer_req_val"]
    set noc1_staled [pnet "${pipeline}/noc1encoder_req_staled_s3"]
    set noc1_req_val [pnet "${l15}/l15_noc1buffer_req_val"]
    set creditman_req [pnet "${l15}/creditman_noc1_req"]
    set noc1_enc_ack [pnet "${l15}/noc1encoder_noc1buffer_req_ack"]
    set noc1_rtr_val [pnet "${l15}/noc1buffer/buffer_router_valid_noc1"]
    set noc1_cmd_val [list]
    for {set bit 0} {$bit < 8} {incr bit} {
        lappend noc1_cmd_val [pnet "${l15}/noc1buffer/command_buffer_val_reg\[${bit}\]__0"]
    }
    set noc2_data_val [pnet "${l15}/noc2_data_val"]
    set noc2_pipe_val [pnet "${pipeline}/noc2_data_val"]
    set noc2_simple_val [pnet "${l15}/simplenocbuffer/noc2_data_val"]
    set ila2_base [concat $pc16 $dcf_count $dcf_pointers $dcf_rtypes [list \
        $val_s2 $val_s3 $pipe_noc1_val $noc1_staled $noc1_req_val \
        $creditman_req $noc1_enc_ack $noc1_rtr_val] $noc1_cmd_val [list \
        $noc2_data_val $noc2_pipe_val $noc2_simple_val]]
    set ila2 [concat $ila2_base [lrepeat [expr {64 - [llength $ila2_base]}] $val_s2]]
    if {[llength $ila2] != 64} { error "ILA2 width [llength $ila2]" }
    reconnect "u_bd/openpiton_top_i/axis_ila_2/probe0" $ila2 "${tag_prefix}_ingress"

    # ILA3 provides an independently clocked copy of the AMO and FIFO state
    # alongside the first two L1.5 pipeline stages.
    set ila3_base [concat $pc16 [list \
        $src_req $src_ack $no_store_pending \
        $mu_req $mu_req_q $mu_resp_ack] $miss_state $dcf_count $dcf_pointers \
        $dcf_rtypes [list $val_s2 $val_s3 $pipe_noc1_val $noc1_staled \
        $noc1_req_val $creditman_req $noc1_enc_ack $noc1_rtr_val]]
    set ila3 [concat $ila3_base [lrepeat [expr {64 - [llength $ila3_base]}] $noc1_req_val]]
    if {[llength $ila3] != 64} { error "ILA3 width [llength $ila3]" }
    reconnect "u_bd/openpiton_top_i/axis_ila_3/probe0" $ila3 "${tag_prefix}_noc"

    set fh [open $probe_map w]
    puts $fh {Build 97 probe map (bit 0 first, 64 bits per ILA)}
    puts $fh "source=$input_dcp"
    puts $fh {ILA1 [15:0]=commit_PC_low [16:24]=source/D-cache/missunit AMO req/ack state [25:27]=missunit_state [28:29]=D-cache FIFO status_count [30:31]=FIFO read/write pointers [32:35]=FIFO slots 0/1 rtype bits}
    puts $fh {ILA2 [15:0]=commit_PC_low [16:23]=FIFO count/pointers/rtype [24:31]=L1.5 val_s2/val_s3/NoC1/stall/credit/ack/router [32:39]=NoC1 command FIFO valid [40:42]=NoC2 ingress/pipeline/simple valid}
    puts $fh {ILA3 [15:0]=commit_PC_low [16:24]=source/missunit AMO req/ack state [25:27]=missunit_state [28:31]=FIFO occupancy/pointers [32:35]=FIFO rtype [36:43]=L1.5 val_s2/val_s3/NoC1 and downstream handshakes}
    puts $fh {missunit state: IDLE=0 DRAIN=1 AMO=2 FLUSH=3 STORE_WAIT=4 LOAD_WAIT=5 AMO_WAIT=6}
    close $fh
    write_checkpoint -force $pre_route_dcp
} else {
    puts "Resuming Build 97 from pre-route checkpoint"
}

puts "ECO-routing Build 97 diagnostic probe loads"
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
puts "SUCCESS: Build 97 incremental adapter FIFO diagnostic image generated"
puts "  PDI: $pdi_file"
puts "  LTX: $ltx_file"
puts "  DCP: $routed_dcp"
puts "  map: $probe_map"
