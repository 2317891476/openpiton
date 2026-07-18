# p3_build94_noc_boundary.tcl -- Diagnostic ILA rewiring from Build 93
# routed DCP to probe the L1.5<->NoC boundary and L2 MSHR state.
# No functional RTL change.
set default_dcp {D:/p3b93_load_path/p3_top_build93_load_path_routed.dcp}
set default_output_dir {D:/p3b94_noc_boundary}
set output_stem {p3_top_build94_noc_boundary}
set tag_prefix {p3_build94}
if {[llength $argv] > 2} { error "expected optional DCP and output dir" }
set input_dcp $default_dcp
set output_dir $default_output_dir
if {[llength $argv] >= 1} { set input_dcp [file normalize [lindex $argv 0]] }
if {[llength $argv] == 2} { set output_dir [file normalize [lindex $argv 1]] }
if {![file exists $input_dcp] || [file size $input_dcp] == 0} { error "DCP missing: $input_dcp" }
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

proc req1 {kind objects label} { if {[llength $objects] != 1} { error "expected one $kind for $label, found [llength $objects]" }; return [lindex $objects 0] }
proc pnet {name} { return [req1 net [lsort -unique [get_nets -quiet [list $name]]] $name] }
proc pqnet {cell_name} { set cell [req1 cell [get_cells -quiet [list $cell_name]] $cell_name]; set qp [req1 pin [get_pins -quiet -of_objects $cell -filter {DIRECTION == OUT && REF_PIN_NAME == Q}] "${cell_name}/Q"]; return [req1 net [get_nets -quiet -of_objects $qp] "${cell_name}/Q net"] }
proc pfsm {root bit} {
    foreach pat [list "${root}/FSM_sequential_state_q_reg\u005b${bit}\u005d_0" "${root}/state_q_reg\u005b${bit}\u005d"] {
        set n [lsort -unique [get_nets -quiet [list $pat]]]
        if {[llength $n] == 1} { return [lindex $n 0] }
    }
    return [pqnet "${root}/FSM_sequential_state_q_reg\u005b${bit}\u005d"]
}
proc ptrue {obj prop} { set v [get_property $prop $obj]; return [expr {$v eq "1" || [string equal -nocase $v "true"]}] }
proc reconnect {port_name nets tag} {
    set width [llength $nets]
    set port [req1 debug_port [get_debug_ports -quiet [list $port_name]] $port_name]
    if {[get_property PORT_WIDTH $port] != $width} { error "$port_name width mismatch: [get_property PORT_WIDTH $port] vs $width" }
    for {set b 0} {$b < $width} {incr b} {
        set pn "${port_name}\u005b${b}\u005d"
        set pin [req1 pin [get_pins -quiet [list $pn]] $pn]
        set old [req1 net [get_nets -quiet -of_objects $pin] "${pn} old"]
        set odt [ptrue $old DONT_TOUCH]
        if {$odt} { set_property DONT_TOUCH false $old }
        disconnect_net -net $old -pinlist $pin
        if {$odt} { set_property DONT_TOUCH true $old }
        set new [lindex $nets $b]
        set ndt [ptrue $new DONT_TOUCH]
        if {$ndt} { set_property DONT_TOUCH false $new }
        connect_net -hierarchical -basename "${tag}_${b}" -net $new -objects $pin
        if {$ndt} { set_property DONT_TOUCH true $new }
    }
}

set_param general.maxThreads 16
set_msg_config -id {Vivado 12-3773} -suppress
set_msg_config -id {Constraints 18-549} -suppress
puts "Opening Build 93 routed checkpoint: $input_dcp"
open_checkpoint $input_dcp

if {!$resume} {
    foreach n [list axi_dbg_hub u_bd/openpiton_top_i/axis_ila_0 u_bd/openpiton_top_i/axis_ila_1 u_bd/openpiton_top_i/axis_ila_2 u_bd/openpiton_top_i/axis_ila_3 u_ila_build90] {
        req1 debug_core [get_debug_cores -quiet [list $n]] $n
    }

    set cva6 {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6}
    set l15 "u_openpiton/system_inst/chip/tile0/l15/l15"
    set l2  "u_openpiton/system_inst/chip/tile0/l2"
    set dcache "${cva6}/i_cache_subsystem/i_wt_dcache"
    set ctrl "${dcache}/gen_rd_ports\u005b1\u005d.i_wt_dcache_ctrl"
    set mu "${dcache}/i_wt_dcache_missunit"
    set sb "${cva6}/issue_stage_i/i_scoreboard"
    set cmb "${sb}/commit_instr_id_commit\u005b0\u005d"

    set pc24 [list]
    for {set b 0} {$b < 24} {incr b} { lappend pc24 [pnet "${cmb}\u005bpc\u005d\u005b${b}\u005d"] }

    # NOC1 (request: L1.5 -> L2) state
    set noc1_req_val   [pnet "${l15}/l15_noc1buffer_req_val"]
    set creditman_req  [pnet "${l15}/creditman_noc1_req"]
    set noc1_enc_ack   [pnet "${l15}/noc1encoder_noc1buffer_req_ack"]
    set noc1_rtr_val   [pnet "${l15}/noc1buffer/buffer_router_valid_noc1"]
    set noc1_cmd_val   [list]
    for {set b 0} {$b < 8} {incr b} { lappend noc1_cmd_val [pnet "${l15}/noc1buffer/command_buffer_val_reg\u005b${b}\u005d__0"] }

    # NOC2 (response: L2 -> L1.5) state
    set noc2_data_val     [pnet "${l15}/noc2_data_val"]
    set noc2_pipe_val     [pnet "${l15}/pipeline/noc2_data_val"]
    set noc2_simple_val   [pnet "${l15}/simplenocbuffer/noc2_data_val"]
    set tile tile0
    set noc2_proc_val     $noc2_data_val
    set noc2_off_val      $noc2_data_val

    # L2 MSHR valid bits
    set l2_mshr_vals [list]
    foreach cell_pat [list \
        "${l2}/mshr_wrap/valid_S2_f_reg\u005b0\u005d" \
        "${l2}/mshr_wrap/valid_S2_f_reg\u005b1\u005d" \
        "${l2}/mshr_wrap/valid_S2_f_reg\u005b2\u005d" \
        "${l2}/mshr_wrap/valid_S2_f_reg\u005b3\u005d"] {
        set cells [get_cells -quiet [list $cell_pat]]
        if {[llength $cells] == 1} {
            set qp [get_pins -quiet -of_objects [lindex $cells 0] -filter {DIRECTION == OUT && REF_PIN_NAME == Q}]
            set nets [get_nets -quiet -of_objects $qp]
            if {[llength $nets] >= 1} { lappend l2_mshr_vals [lindex $nets 0] }
        }
    }
    # Fallback: use any 4 distinct mshr val nets
    if {[llength $l2_mshr_vals] < 4} {
        set all_mshr [lsort -unique [get_nets -quiet -hier -filter "NAME =~ ${l2}/mshr_wrap/valid_S2_f*"]]
        set l2_mshr_vals [list]
        set seen 0
        foreach n $all_mshr {
            if {$seen >= 4} break
            lappend l2_mshr_vals $n
            incr seen
        }
    }

    # Controller and missunit FSM mirrors
    set c_fsm0 [pfsm $ctrl 0]; set c_fsm1 [pfsm $ctrl 1]; set c_fsm2 [pfsm $ctrl 2]
    set mu_fsm0 [pfsm $mu 0]; set mu_fsm1 [pfsm $mu 1]; set mu_fsm2 [pfsm $mu 2]

    # ILA1 [64]: PC[23:0] + NOC1 state
    set filler1 [lrepeat 28 $noc1_req_val]
    set ila1 [concat $pc24 [list $noc1_req_val $creditman_req $noc1_enc_ack $noc1_rtr_val] $noc1_cmd_val $filler1]
    if {[llength $ila1] != 64} { error "ILA1=[llength $ila1]" }
    reconnect "u_bd/openpiton_top_i/axis_ila_1/probe0" $ila1 "${tag_prefix}_ila1"

    # ILA2 [64]: PC[23:0] + NOC2 state + L2 MSHR
    set ila2_base [concat $pc24 [list $noc2_data_val $noc2_pipe_val $noc2_simple_val $noc2_proc_val $noc2_off_val] $l2_mshr_vals]
    set filler2_needed [expr {64 - [llength $ila2_base]}]
    set filler2 [lrepeat $filler2_needed $noc2_data_val]
    set ila2 [concat $ila2_base $filler2]
    if {[llength $ila2] != 64} { error "ILA2=[llength $ila2]" }
    reconnect "u_bd/openpiton_top_i/axis_ila_2/probe0" $ila2 "${tag_prefix}_ila2"

    # ILA3 [64]: PC[23:0] + FSM mirrors + L2 MSHR mirrors
    set mu_mshrv [pqnet "${mu}/mshr_vld_q_reg"]
    set ila3_base [concat $pc24 [list $c_fsm0 $c_fsm1 $c_fsm2] [list $mu_fsm0 $mu_fsm1 $mu_fsm2] [list $mu_mshrv] $l2_mshr_vals]
    set filler3_needed [expr {64 - [llength $ila3_base]}]
    set filler3 [lrepeat $filler3_needed $mu_mshrv]
    set ila3 [concat $ila3_base $filler3]
    if {[llength $ila3] != 64} { error "ILA3=[llength $ila3]" }
    reconnect "u_bd/openpiton_top_i/axis_ila_3/probe0" $ila3 "${tag_prefix}_ila3"

    set fh [open $probe_map w]
    puts $fh "Build 94 probe map (bit 0 first, 64 bits per ILA)"
    puts $fh "source=$input_dcp"
    puts $fh "ILA1 [23:0]=PC [24]=noc1_req_val [25]=creditman_req [26]=noc1_enc_ack [27]=noc1_rtr_val [28:35]=noc1_cmd_val[0:7] [36:63]=filler"
    puts $fh "ILA2 [23:0]=PC [24]=noc2_data_val [25]=noc2_pipe_val [26]=noc2_simple_val [27]=noc2_proc_val [28]=noc2_off_val [29:32]=l2_mshr_val[0:3] [33:63]=filler"
    puts $fh "ILA3 [23:0]=PC [24:26]=ctrl_FSM [27:29]=mu_FSM [30]=mshr_vld [31:34]=l2_mshr_val[0:3] [35:63]=filler"
    puts $fh "ctrl FSM: IDLE=0 READ=1 MISS_REQ=2 MISS_WAIT=3 KILL_MISS=4 KILL_MISS_ACK=5 REPLAY_REQ=6 REPLAY_READ=7"
    puts $fh "mu FSM: IDLE=0 DRAIN=1 AMO=2 FLUSH=3 STORE_WAIT=4 LOAD_WAIT=5 AMO_WAIT=6"
    puts $fh "NOC1 cmd_val[0:7]: nonzero = NOC1 command buffer occupied"
    puts $fh "NOC2 data_val: nonzero = L2 response arriving"
    puts $fh "L2 MSHR val: nonzero = L2 has outstanding miss"
    close $fh
    write_checkpoint -force $pre_route_dcp
} else {
    puts "Resuming from Build 94 pre-route checkpoint"
}

puts "Routing Build 94 diagnostic probe loads"
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
puts "SUCCESS: Build 94 NoC-boundary diagnostic image generated"
puts "  PDI: $pdi_file"
puts "  LTX: $ltx_file"
puts "  DCP: $routed_dcp"
puts "  map: $probe_map"
