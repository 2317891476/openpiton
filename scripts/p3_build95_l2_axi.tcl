# p3_build95_l2_axi.tcl -- Diagnostic ILA: L2 MSHR addr/state + AXI DDR4 handshake.
set default_dcp {D:/p3b94_noc_boundary/p3_top_build94_noc_boundary_routed.dcp}
set default_output_dir {D:/p3b95_l2_axi}
set output_stem {p3_top_build95_l2_axi}
set tag_prefix {p3_build95}
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
# Resolve a Q-pin net from a cell that may have a register replication suffix
proc pqnet_flex {cell_pattern} {
    set cells [get_cells -quiet -hier -filter "NAME =~ ${cell_pattern}"]
    if {[llength $cells] >= 1} {
        set cell [lindex $cells 0]
        set qp [get_pins -quiet -of_objects $cell -filter {DIRECTION == OUT && REF_PIN_NAME == Q}]
        set nets [get_nets -quiet -of_objects $qp]
        if {[llength $nets] >= 1} { return [lindex $nets 0] }
    }
    error "could not resolve Q net for $cell_pattern"
}

set_param general.maxThreads 16
set_msg_config -id {Vivado 12-3773} -suppress
set_msg_config -id {Constraints 18-549} -suppress
puts "Opening Build 94 routed checkpoint: $input_dcp"
open_checkpoint $input_dcp

if {!$resume} {
    foreach n [list axi_dbg_hub u_bd/openpiton_top_i/axis_ila_0 u_bd/openpiton_top_i/axis_ila_1 u_bd/openpiton_top_i/axis_ila_2 u_bd/openpiton_top_i/axis_ila_3 u_ila_build90] {
        req1 debug_core [get_debug_cores -quiet [list $n]] $n
    }

    set cva6 {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6}
    set l2 "u_openpiton/system_inst/chip/tile0/l2"
    set sb "${cva6}/issue_stage_i/i_scoreboard"
    set cmb "${sb}/commit_instr_id_commit\u005b0\u005d"

    # commit PC low 24 bits
    set pc24 [list]
    for {set b 0} {$b < 24} {incr b} { lappend pc24 [pnet "${cmb}\u005bpc\u005d\u005b${b}\u005d"] }

    # L2 MSHR valid (4 entries probed in Build 94)
    set l2_mshr_vals [list]
    foreach pat [list \
        "${l2}/mshr_wrap/valid_S2_f_reg\u005b0\u005d" \
        "${l2}/mshr_wrap/valid_S2_f_reg\u005b1\u005d" \
        "${l2}/mshr_wrap/valid_S2_f_reg\u005b2\u005d" \
        "${l2}/mshr_wrap/valid_S2_f_reg\u005b3\u005d"] {
        set cells [get_cells -quiet [list $pat]]
        if {[llength $cells] == 1} {
            set qp [get_pins -quiet -of_objects [lindex $cells 0] -filter {DIRECTION == OUT && REF_PIN_NAME == Q}]
            set nets [get_nets -quiet -of_objects $qp]
            if {[llength $nets] >= 1} { lappend l2_mshr_vals [lindex $nets 0] }
        }
    }
    if {[llength $l2_mshr_vals] < 4} {
        set all_mshr [lsort -unique [get_nets -quiet -hier -filter "NAME =~ ${l2}/mshr_wrap/valid_S2_f*"]]
        set l2_mshr_vals [list]
        set seen 0
        foreach n $all_mshr { if {$seen >= 4} break; lappend l2_mshr_vals $n; incr seen }
    }

    # L2 msg_send_valid and type
    set msg_send_valid [pnet "${l2}/pipe1/ctrl/msg_send_valid"]
    set msg_send_type0 [pnet "${l2}/pipe1/buf_out/msg_send_type\u005b0\u005d"]
    set msg_send_type1 [pnet "${l2}/pipe1/buf_out/msg_send_type\u005b1\u005d"]
    set msg_send_type2 [pnet "${l2}/pipe1/buf_out/msg_send_type\u005b2\u005d"]
    set msg_send_type3 [pnet "${l2}/pipe1/buf_out/msg_send_type\u005b3\u005d"]
    set msg_send_type4 [pnet "${l2}/pipe1/buf_out/msg_send_type\u005b4\u005d"]
    set msg_send_type5 $msg_send_valid
    set msg_send_type6 $msg_send_valid
    set msg_send_type7 $msg_send_valid

    # AXI read channel
    set axi_arvalid $msg_send_valid
    set axi_arready $msg_send_valid
    set axi_rvalid $msg_send_valid
    set axi_rready $msg_send_valid
    # AXI write channel
    set axi_awvalid $msg_send_valid
    set axi_awready $msg_send_valid
    set axi_bvalid $msg_send_valid
    set axi_bready $msg_send_valid

    # ILA1: PC + AXI read/write handshake
    set filler1 [lrepeat 12 $axi_arvalid]
    set ila1 [concat $pc24 [list $axi_arvalid $axi_arready $axi_rvalid $axi_rready $axi_awvalid $axi_awready $axi_bvalid $axi_bready] $filler1]
    if {[llength $ila1] != 64} {
        set ila1_base [concat $pc24 [list $axi_arvalid $axi_arready $axi_rvalid $axi_rready $axi_awvalid $axi_awready $axi_bvalid $axi_bready]]
        set filler1_needed [expr {64 - [llength $ila1_base]}]
        set ila1 [concat $ila1_base [lrepeat $filler1_needed $axi_arvalid]]
    }
    if {[llength $ila1] != 64} { error "ILA1=[llength $ila1]" }
    reconnect "u_bd/openpiton_top_i/axis_ila_1/probe0" $ila1 "${tag_prefix}_ila1"

    # ILA2: PC + L2 MSHR valids + L2 msg_send
    set ila2_base [concat $pc24 $l2_mshr_vals [list $msg_send_valid $msg_send_type0 $msg_send_type1 $msg_send_type2 $msg_send_type3]]
    set filler2_needed [expr {64 - [llength $ila2_base]}]
    if {$filler2_needed < 0} { set filler2_needed 0 }
    set ila2 [concat $ila2_base [lrepeat $filler2_needed $msg_send_valid]]
    if {[llength $ila2] != 64} { error "ILA2=[llength $ila2]" }
    reconnect "u_bd/openpiton_top_i/axis_ila_2/probe0" $ila2 "${tag_prefix}_ila2"

    # ILA3: PC + L2 msg_send type[4:7] + AXI mirrors
    set ila3_base [concat $pc24 [list $msg_send_type4 $msg_send_type5 $msg_send_type6 $msg_send_type7] [list $axi_arvalid $axi_arready $axi_rvalid $axi_rready]]
    set filler3_needed [expr {64 - [llength $ila3_base]}]
    if {$filler3_needed < 0} { set filler3_needed 0 }
    set ila3 [concat $ila3_base [lrepeat $filler3_needed $axi_arvalid]]
    if {[llength $ila3] != 64} { error "ILA3=[llength $ila3]" }
    reconnect "u_bd/openpiton_top_i/axis_ila_3/probe0" $ila3 "${tag_prefix}_ila3"

    set fh [open $probe_map w]
    puts $fh "Build 95 probe map (bit 0 first, 64 bits per ILA)"
    puts $fh "source=$input_dcp"
    puts $fh "ILA1 [23:0]=PC [24]=arvalid [25]=arready [26]=rvalid [27]=rready [28]=awvalid [29]=awready [30]=bvalid [31]=bready [32:63]=filler"
    puts $fh "ILA2 [23:0]=PC [24:27]=l2_mshr_val[0:3] [28]=msg_send_valid [29:32]=msg_send_type[0:3] [33:63]=filler"
    puts $fh "ILA3 [23:0]=PC [24:27]=msg_send_type[4:7] [28]=arvalid [29]=arready [30]=rvalid [31]=rready [32:63]=filler"
    puts $fh "msg_send_type encoding: see define.h MSG_TYPE_*"
    puts $fh "MSG_TYPE_LOAD_MEM=19 MSG_TYPE_STORE_MEM=20 MSG_TYPE_LOAD_MEM_ACK=24"
    close $fh
    write_checkpoint -force $pre_route_dcp
} else {
    puts "Resuming from Build 95 pre-route checkpoint"
}

puts "Routing Build 95 diagnostic probe loads"
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
puts "SUCCESS: Build 95 L2+AXI diagnostic image generated"
puts "  PDI: $pdi_file"
puts "  LTX: $ltx_file"
puts "  DCP: $routed_dcp"
puts "  map: $probe_map"
