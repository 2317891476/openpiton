# Build 99 -- incremental load-path diagnostic ECO.
#
# Reuses the Build 97 routed DCP. Changes only existing ILA probe loads and
# ECO-routes them. No synthesis, placement, functional RTL, or SD content is
# changed.
#
# Key correction from Build 98: Build 98 probed amo_resp[ack], which is the
# AMO completion response -- NOT the adapter data ack.  This build replaces
# those misleading probes with:
#   - miss_req[1]/[2] (surviving nets showing load/store miss pending)
#   - rd_ack[1] (surviving net showing cache read grant)
#   - state_d[2] LUT chain inputs (to trace the absorbed mem_data_ack_i)
#   - deeper LUT-tree intermediates

set default_dcp {C:/p3eco/build97/p3_top_build97_adapter_fifo_routed.dcp}
set default_output_dir {C:/p3eco/build99}
set output_stem {p3_top_build99_loadpath}
set tag_prefix {p3_build99}
if {[llength $argv] > 2} { error "expected optional DCP and output dir" }
set input_dcp $default_dcp
set output_dir $default_output_dir
if {[llength $argv] >= 1} { set input_dcp [file normalize [lindex $argv 0]] }
if {[llength $argv] == 2} { set output_dir [file normalize [lindex $argv 1]] }
if {![file exists $input_dcp] || [file size $input_dcp] == 0} {
    error "DCP is missing or empty: $input_dcp"
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
proc cellpin_net {cell_name ref_pin} {
    set cell [req1 cell [get_cells -quiet [list $cell_name]] $cell_name]
    set pin [req1 pin [get_pins -quiet -of_objects $cell \
        -filter "REF_PIN_NAME == ${ref_pin}"] "${cell_name}/${ref_pin}"]
    return [req1 net [get_nets -quiet -of_objects $pin] "${cell_name}/${ref_pin} net"]
}
proc qnet {cell_name} { return [cellpin_net $cell_name Q] }
proc ptrue {obj prop} {
    set value [get_property $prop $obj]
    return [expr {$value eq "1" || [string equal -nocase $value "true"]}]
}
proc ptrynet {name fallback} {
    set nets [get_nets -quiet [list $name]]
    if {[llength $nets] == 1} { return [lindex $nets 0] }
    return $fallback
}
proc cp_try_net {cell_name ref_pin fallback} {
    set cell [get_cells -quiet [list $cell_name]]
    if {[llength $cell] != 1} { return $fallback }
    set pin [get_pins -quiet -of_objects $cell -filter "REF_PIN_NAME == ${ref_pin}"]
    if {[llength $pin] != 1} { return $fallback }
    set nets [get_nets -quiet -of_objects $pin]
    if {[llength $nets] == 1} { return [lindex $nets 0] }
    return $fallback
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
puts "Opening checkpoint: $input_dcp"
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
    set cache "${cva6}/i_cache_subsystem"
    set dcache "${cache}/i_wt_dcache"
    set missunit "${dcache}/i_wt_dcache_missunit"
    set adapter "${cache}/i_adapter"
    set dcfifo "${adapter}/i_dcache_data_fifo/i_fifo_v3"
    set l15 "${tile}/l15/l15"
    set pipeline "${l15}/pipeline"
    set commit "${cva6}/issue_stage_i/i_scoreboard/commit_instr_id_commit\[0\]"
    set pc16 [pbus "${commit}\[pc\]" 16]

    # ---- Missunit state Q/D/CE (same as Build 98, confirmed working) ----
    set state_q [list]; set state_d [list]; set state_ce [list]
    for {set bit 0} {$bit < 3} {incr bit} {
        set cell "${missunit}/FSM_sequential_state_q_reg\[${bit}\]"
        lappend state_q [qnet $cell]
        lappend state_d [cellpin_net $cell D]
        lappend state_ce [cellpin_net $cell CE]
    }

    # ---- FIFO count Q/D/CE (same as Build 98, confirmed working) ----
    set fifo_q [list]; set fifo_d [list]; set fifo_ce [list]
    for {set bit 0} {$bit < 2} {incr bit} {
        set cell "${dcfifo}/status_cnt_q_reg\[${bit}\]"
        lappend fifo_q [qnet $cell]
        lappend fifo_d [cellpin_net $cell D]
        lappend fifo_ce [cellpin_net $cell CE]
    }
    set pointer_q [list \
        [qnet "${dcfifo}/read_pointer_q_reg\[0\]"] \
        [qnet "${dcfifo}/write_pointer_q_reg\[0\]"]]
    set pointer_d [list \
        [cellpin_net "${dcfifo}/read_pointer_q_reg\[0\]" D] \
        [cellpin_net "${dcfifo}/write_pointer_q_reg\[0\]" D]]

    # ---- Surviving D-cache miss-path nets ----
    set miss_req1 [pnet "${dcache}/miss_req\[1\]"]
    set miss_req2 [pnet "${dcache}/miss_req\[2\]"]
    set rd_ack1  [pnet "${dcache}/rd_ack\[1\]"]

    # ---- state_d[2] LUT chain inputs (to trace absorbed mem_data_ack_i) ----
    set sd2_lut "${missunit}/FSM_sequential_state_q\[2\]_i_1__0"
    set sd2_i [list]
    for {set i 0} {$i < 6} {incr i} {
        set pin [req1 pin [get_pins -quiet "${sd2_lut}/I${i}"] "${sd2_lut}/I${i}"]
        lappend sd2_i [req1 net [get_nets -quiet -of_objects $pin] "${sd2_lut}/I${i} net"]
    }

    # ---- Deeper LUT-tree intermediates (resolved from cell pins, not net names) ----
    set i244_out [cp_try_net "${missunit}/i___244_i_2" O [lindex $sd2_i 0]]
    set i6_out  [cp_try_net "${missunit}/FSM_sequential_state_q\[2\]_i_6__0" O [lindex $sd2_i 0]]
    set reg0_12 [lindex $sd2_i 0]
    set reg0_13 [ptrynet "${missunit}/FSM_sequential_state_q_reg\[0\]_13" [lindex $sd2_i 0]]
    set reg0_14 [ptrynet "${missunit}/FSM_sequential_state_q_reg\[0\]_14" [lindex $sd2_i 0]]

    # ---- L1.5 pipeline boundary (same as Build 98 ILA2, confirmed) ----
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

    # ===================== ILA1: missunit FSM + miss path =====================
    set ila1_base [concat $pc16 [list \
        $miss_req1 $miss_req2 $rd_ack1] \
        $state_q $state_d $state_ce \
        $fifo_q $fifo_d $fifo_ce $pointer_q $pointer_d \
        $sd2_i [list $i244_out $i6_out $reg0_12 $reg0_13 $reg0_14] \
        [list $val_s2 $val_s3 $noc1_req_val $creditman_req $noc1_enc_ack]]
    set ila1 [concat $ila1_base [lrepeat [expr {64 - [llength $ila1_base]}] $val_s2]]
    if {[llength $ila1] != 64} { error "ILA1 width [llength $ila1]" }
    reconnect "u_bd/openpiton_top_i/axis_ila_1/probe0" $ila1 "${tag_prefix}_fsm"

    # =============== ILA2: L1.5 boundary + NoC (same as Build 98) ===============
    set dcf_rtypes [list \
        [qnet "${dcfifo}/mem_q_reg\[0\]\[rtype\]\[0\]"] \
        [qnet "${dcfifo}/mem_q_reg\[0\]\[rtype\]\[1\]"] \
        [qnet "${dcfifo}/mem_q_reg\[1\]\[rtype\]\[0\]"] \
        [qnet "${dcfifo}/mem_q_reg\[1\]\[rtype\]\[1\]"]]
    set ila2_base [concat $pc16 $fifo_q $fifo_d $fifo_ce $pointer_q $pointer_d \
        $state_q $state_d $state_ce [list \
        $val_s2 $val_s3 $pipe_noc1_val $noc1_staled $noc1_req_val \
        $creditman_req $noc1_enc_ack $noc1_rtr_val] $noc1_cmd_val [list \
        $noc2_data_val $noc2_pipe_val $noc2_simple_val]]
    set ila2 [concat $ila2_base [lrepeat [expr {64 - [llength $ila2_base]}] $val_s2]]
    if {[llength $ila2] != 64} { error "ILA2 width [llength $ila2]" }
    reconnect "u_bd/openpiton_top_i/axis_ila_2/probe0" $ila2 "${tag_prefix}_l15"

    # ======== ILA3: miss path confirmation + FIFO rtype + L1.5 ========
    set ila3_base [concat $pc16 [list \
        $miss_req1 $miss_req2 $rd_ack1] \
        $state_q $state_d $state_ce \
        $fifo_q $fifo_d $fifo_ce $pointer_q $pointer_d $dcf_rtypes \
        [list $val_s2 $val_s3 $pipe_noc1_val $noc1_staled \
        $noc1_req_val $creditman_req $noc1_enc_ack $noc1_rtr_val]]
    set ila3 [concat $ila3_base [lrepeat [expr {64 - [llength $ila3_base]}] $noc1_req_val]]
    if {[llength $ila3] != 64} { error "ILA3 width [llength $ila3]" }
    reconnect "u_bd/openpiton_top_i/axis_ila_3/probe0" $ila3 "${tag_prefix}_miss"

    set fh [open $probe_map w]
    puts $fh {Build 99 probe map (bit 0 first, 64 bits per ILA)}
    puts $fh "source=$input_dcp"
    puts $fh {ILA1 [15:0]=commit_PC [16]=miss_req1(load) [17]=miss_req2(store) [18]=rd_ack1 [19:21]=state_q [22:24]=state_d [25]=state_ce [26:27]=fifo_count_q [28:29]=fifo_count_d [30]=fifo_count_ce [31:32]=ptr_q [33:34]=ptr_d [35:40]=sd2_LUT_I0-I5 [41]=i244_out [42]=i6_out [43:45]=reg0_12/13/14 [46:50]=L1.5_subset}
    puts $fh {ILA2 [15:0]=commit_PC [16:21]=fifo_q/d/ce [22:25]=ptr_q/d [26:34]=state_q/d/ce [35:42]=L1.5_val/noc1 [43:50]=noc1_cmd_fifo [51:53]=noc2}
    puts $fh {ILA3 [15:0]=commit_PC [16:18]=miss_req1/2/rd_ack1 [19:21]=state_q [22:24]=state_d [25]=state_ce [26:27]=fifo_q [28:29]=fifo_d [30]=fifo_ce [31:34]=ptr_q/d [35:38]=fifo_rtype [39:46]=L1.5_handshakes}
    puts $fh {missunit state: IDLE=0 DRAIN=1 AMO=2 FLUSH=3 STORE_WAIT=4 LOAD_WAIT=5 AMO_WAIT=6}
    puts $fh {Key: miss_req1=1 means load miss pending, miss_req2=1 means store miss pending}
    puts $fh {Key: sd2_LUT inputs trace absorbed mem_data_ack_i through the state_d[2] logic tree}
    close $fh
    write_checkpoint -force $pre_route_dcp
} else {
    puts "Resuming from pre-route checkpoint"
}

puts "ECO-routing Build 99 diagnostic probe loads"
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
puts "SUCCESS: Build 99 incremental load-path diagnostic generated"
puts "  PDI: $pdi_file"
puts "  LTX: $ltx_file"
puts "  DCP: $routed_dcp"
puts "  map: $probe_map"
