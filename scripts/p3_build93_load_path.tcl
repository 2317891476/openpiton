# p3_build93_load_path.tcl -- Diagnostic-only ILA rewiring from Build 92
# routed DCP to trace load-unit port-1 request through WT D-cache controller,
# miss unit, and MSHR.  No functional RTL is changed.
set default_dcp {D:/p3b92_udelay_caller/p3_top_build92_udelay_caller_routed.dcp}
set default_output_dir {D:/p3b93_load_path}
set output_stem {p3_top_build93_load_path}
set tag_prefix {p3_build93}
if {[llength $argv] > 2} { error "expected optional DCP and output dir" }
set input_dcp $default_dcp
set output_dir $default_output_dir
if {[llength $argv] >= 1} { set input_dcp [file normalize [lindex $argv 0]] }
if {[llength $argv] == 2} { set output_dir [file normalize [lindex $argv 1]] }
if {![file exists $input_dcp] || [file size $input_dcp] == 0} {
    error "Build 92 routed DCP is missing or empty: $input_dcp"
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
    if {[llength $objects] != 1} { error "expected one $kind for $label, found [llength $objects]" }
    return [lindex $objects 0]
}
proc pnet {name} { return [req1 net [lsort -unique [get_nets -quiet [list $name]]] $name] }
proc pbus {base width} {
    set r [list]
    for {set b 0} {$b < $width} {incr b} { lappend r [pnet "${base}\u005b${b}\u005d"] }
    return $r
}
proc pfsm {root bit} {
    foreach pat [list \
        "${root}/FSM_sequential_state_q_reg\u005b${bit}\u005d_0" \
        "${root}/state_q_reg\u005b${bit}\u005d"] {
        set n [lsort -unique [get_nets -quiet [list $pat]]]
        if {[llength $n] == 1} { return [lindex $n 0] }
    }
    return [pqnet "${root}/FSM_sequential_state_q_reg\u005b${bit}\u005d"]
}
proc pqnet {cell_name} {
    set cell [req1 cell [get_cells -quiet [list $cell_name]] $cell_name]
    set qp [req1 pin [get_pins -quiet -of_objects $cell -filter {DIRECTION == OUT && REF_PIN_NAME == Q}] "${cell_name}/Q"]
    return [req1 net [get_nets -quiet -of_objects $qp] "${cell_name}/Q net"]
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
puts "Opening Build 92 routed checkpoint: $input_dcp"
open_checkpoint $input_dcp
if {!$resume} {
    foreach n [list axi_dbg_hub u_bd/openpiton_top_i/axis_ila_0 u_bd/openpiton_top_i/axis_ila_1 u_bd/openpiton_top_i/axis_ila_2 u_bd/openpiton_top_i/axis_ila_3 u_ila_build90] {
        req1 debug_core [get_debug_cores -quiet [list $n]] $n
    }
    set cva6 {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6}
    set lu "${cva6}/ex_stage_i/lsu_i/i_load_unit"
    set cache "${cva6}/i_cache_subsystem"
    set dcache "${cache}/i_wt_dcache"
    set ctrl "${dcache}/gen_rd_ports\u005b1\u005d.i_wt_dcache_ctrl"
    set mu "${dcache}/i_wt_dcache_missunit"
    set sb "${cva6}/issue_stage_i/i_scoreboard"
    set cmb "${sb}/commit_instr_id_commit\u005b0\u005d"
    set pc24 [lrange [pbus "${cmb}\u005bpc\u005d" 64] 0 23]
    set lu_req    [pnet "${lu}/dcache_req_ports_ex_cache\u005b1\u005d\u005bdata_req\u005d"]
    set lu_kill   [pnet "${lu}/dcache_req_ports_ex_cache\u005b1\u005d\u005bkill_req\u005d"]
    set lu_tag    [pnet "${lu}/dcache_req_ports_ex_cache\u005b1\u005d\u005btag_valid\u005d"]
    set lu_gnt    [pnet "${lu}/dcache_req_ports_cache_ex\u005b1\u005d\u005bdata_gnt\u005d"]
    set lu_rvalid [pnet "${lu}/dcache_req_ports_cache_ex\u005b1\u005d\u005bdata_rvalid\u005d"]
    set lu_dtlb   [pnet "${lu}/dtlb_hit"]
    set lu_trans  [pnet "${lu}/ld_translation_req"]
    set lu_pom    [pnet "${lu}/page_offset_matches"]
    set c_mreq    [pnet "${ctrl}/miss_req\u005b0\u005d"]
    set c_mrep    [pnet "${ctrl}/miss_replay\u005b0\u005d"]
    set c_mrtrn   [pnet "${ctrl}/miss_rtrn_vld\u005b0\u005d"]
    set c_rdreq   [pnet "${ctrl}/rd_req_q_reg_0"]
    set c_rdack   [pnet "${ctrl}/rd_ack\u005b0\u005d"]
    set c_fsm0    [pfsm $ctrl 0]
    set c_fsm1    [pfsm $ctrl 1]
    set c_fsm2    [pfsm $ctrl 2]
    set c_tag     [pnet "${ctrl}/dcache_req_ports_ex_cache\u005b1\u005d\u005btag_valid\u005d"]
    set c_kill    [pnet "${ctrl}/dcache_req_ports_ex_cache\u005b1\u005d\u005bkill_req\u005d"]
    set mu_mr0    [pnet "${mu}/miss_req\u005b0\u005d"]
    set mu_mr1    [pnet "${mu}/miss_req\u005b1\u005d"]
    set mu_mr2    [pnet "${mu}/miss_req\u005b2\u005d"]
    set mu_rep    [pnet "${mu}/miss_replay\u005b0\u005d"]
    set mu_mshrv  [pqnet "${mu}/mshr_vld_q_reg"]
    set mu_pidx1  [pnet "${mu}/miss_port_idx\u005b1\u005d"]
    set mu_mq0    [pnet "${mu}/miss_req_masked_q\u005b0\u005d"]
    set mu_mq1    [pnet "${mu}/miss_req_masked_q\u005b1\u005d"]
    set mu_mq2    [pnet "${mu}/miss_req_masked_q\u005b2\u005d"]
    set mu_fsm0   [pfsm $mu 0]
    set mu_fsm1   [pfsm $mu 1]
    set mu_fsm2   [pfsm $mu 2]
    set rd21 [lrepeat 22 $lu_req]
    set ila1 [concat $pc24 \
        [list $lu_req $lu_kill $lu_tag $lu_gnt $lu_rvalid $lu_dtlb $lu_trans $lu_pom] \
        [list $c_mreq $c_mrep $c_mrtrn $c_rdreq $c_rdack] \
        [list $c_fsm0 $c_fsm1 $c_fsm2] [list $c_tag $c_kill] $rd21]
    if {[llength $ila1] != 64} { error "ILA1=[llength $ila1]" }
    reconnect "u_bd/openpiton_top_i/axis_ila_1/probe0" $ila1 "${tag_prefix}_ila1"
    set rd28 [lrepeat 28 $mu_mr1]
    set ila2 [concat $pc24 \
        [list $mu_mr0 $mu_mr1 $mu_mr2 $mu_rep $mu_mshrv $mu_pidx1 $mu_mq0 $mu_mq1 $mu_mq2] \
        [list $mu_fsm0 $mu_fsm1 $mu_fsm2] $rd28]
    if {[llength $ila2] != 64} { error "ILA2=[llength $ila2]" }
    reconnect "u_bd/openpiton_top_i/axis_ila_2/probe0" $ila2 "${tag_prefix}_ila2"
    set rd28b [lrepeat 26 $lu_rvalid]
    set ila3 [concat $pc24 \
        [list $c_fsm0 $c_fsm1 $c_fsm2] [list $mu_fsm0 $mu_fsm1 $mu_fsm2] \
        [list $lu_req $lu_gnt $lu_rvalid $mu_mshrv $c_mreq $c_mrtrn $c_kill $c_tag] $rd28b]
    if {[llength $ila3] != 64} { error "ILA3=[llength $ila3]" }
    reconnect "u_bd/openpiton_top_i/axis_ila_3/probe0" $ila3 "${tag_prefix}_ila3"
    set fh [open $probe_map w]
    puts $fh "Build 93 probe map (bit 0 first, 64 bits per ILA)"
    puts $fh "source=$input_dcp"
    puts $fh "ILA1 [23:0]=PC [24]=data_req [25]=kill_req [26]=tag_valid [27]=data_gnt [28]=data_rvalid [29]=dtlb_hit [30]=ld_trans [31]=page_off"
    puts $fh "ILA1 [32]=ctrl_miss_req [33]=ctrl_miss_replay [34]=ctrl_miss_rtrn [35]=ctrl_rd_req [36]=ctrl_rd_ack [37:39]=ctrl_FSM [40]=ctrl_tag [41]=ctrl_kill [42:63]=rdata[21:0]"
    puts $fh "ILA2 [23:0]=PC [24:26]=mu_miss_req[0:2] [27]=mu_replay [28]=mu_mshr_vld [29]=mu_port_idx1 [30:32]=mu_masked[0:2] [33:35]=mu_FSM [36:63]=rdata[43:16]"
    puts $fh "ILA3 [23:0]=PC [24:26]=ctrl_FSM [27:29]=mu_FSM [30]=data_req [31]=data_gnt [32]=data_rvalid [33]=mshr_vld [34]=ctrl_miss_req [35]=ctrl_miss_rtrn [36:37]=ctrl_kill/tag [38:63]=rdata[71:44]"
    puts $fh "ctrl FSM: IDLE=0 READ=1 MISS_REQ=2 MISS_WAIT=3 KILL_MISS=4 KILL_MISS_ACK=5 REPLAY_REQ=6 REPLAY_READ=7"
    puts $fh "mu FSM: IDLE=0 DRAIN=1 AMO=2 FLUSH=3 STORE_WAIT=4 LOAD_WAIT=5 AMO_WAIT=6"
    puts $fh "stable stop: PC=0xffffffff8018a7a6"
    close $fh
    write_checkpoint -force $pre_route_dcp
} else {
    puts "Resuming from Build 93 pre-route checkpoint"
}
puts "Routing Build 93 diagnostic probe loads"
route_design -eco
report_route_status -file $route_report
report_timing_summary -delay_type min_max -max_paths 20 -file $timing_report
report_drc -file $drc_report
write_debug_probes -force $ltx_file
if {![file exists $ltx_file] || [file size $ltx_file] == 0} { error "Build 93 LTX missing: $ltx_file" }
cd $output_dir
write_device_image -force -file $pdi_file
if {![file exists $pdi_file] || [file size $pdi_file] == 0} { error "Build 93 PDI missing: $pdi_file" }
write_checkpoint -force $routed_dcp
puts "SUCCESS: Build 93 load-path diagnostic image generated"
puts "  PDI:    $pdi_file"
puts "  LTX:    $ltx_file"
puts "  DCP:    $routed_dcp"
puts "  map:    $probe_map"
