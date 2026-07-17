# p3_build80_trap_csr_eco.tcl -- Capture a CVA6 S-to-M trap with the
# board-validated Build 66 debug hub and four existing ILAs.
#
# The functional design is unchanged.  This ECO starts from the Build 79
# pre-route checkpoint, reconnects only existing ILA loads, and reroutes those
# loads.  Every probe bit is assigned explicitly.

set default_dcp \
    {D:/p3b79_wfi_irq_eco/p3_top_build79_wfi_irq_eco_pre_route.dcp}
set default_output_dir {D:/p3b80_trap_csr_eco}

if {[llength $argv] > 2} {
    puts "ERROR: expected optional Build 79 pre-route DCP and output directory"
    exit 1
}
set input_dcp $default_dcp
set output_dir $default_output_dir
if {[llength $argv] >= 1} {
    set input_dcp [file normalize [lindex $argv 0]]
}
if {[llength $argv] == 2} {
    set output_dir [file normalize [lindex $argv 1]]
}
if {![file exists $input_dcp]} {
    puts "ERROR: Build 79 pre-route DCP not found: $input_dcp"
    exit 1
}

file mkdir $output_dir
set output_base "${output_dir}/p3_top_build80_trap_csr_eco"
set mapping_file "${output_base}_probe_map.txt"
set pre_route_dcp "${output_base}_pre_route.dcp"
set route_report "${output_base}_route_status.rpt"
set timing_report "${output_base}_timing_summary.rpt"
set drc_report "${output_base}_drc.rpt"
set ltx_file "${output_base}.ltx"
set pdi_file "${output_base}.pdi"
set resume_from_build80 [string equal -nocase \
    [file normalize $input_dcp] [file normalize $pre_route_dcp]]

proc p3_require_one {kind objects name} {
    if {[llength $objects] != 1} {
        error "required exact $kind matched [llength $objects] objects: $name"
    }
    return [lindex $objects 0]
}

proc p3_require_net {name} {
    return [p3_require_one net [get_nets -quiet [list $name]] $name]
}

proc p3_require_cell {name} {
    return [p3_require_one cell [get_cells -quiet [list $name]] $name]
}

proc p3_require_bus {base width} {
    set result [list]
    for {set bit 0} {$bit < $width} {incr bit} {
        lappend result [p3_require_net "${base}\[$bit\]"]
    }
    return $result
}

proc p3_q_net {cell_name} {
    set cell [p3_require_cell $cell_name]
    set qpin [p3_require_one pin [get_pins -quiet -of_objects $cell \
        -filter {DIRECTION == OUT && NAME =~ */Q}] "${cell_name}/Q"]
    return [p3_require_one net [get_nets -quiet -of_objects $qpin] \
        "${cell_name}/Q net"]
}

proc p3_property_is_true {object property} {
    set value [get_property $property $object]
    return [expr {$value eq "1" || [string equal -nocase $value "true"]}]
}

proc p3_reconnect_probe {port_name width nets tag} {
    if {[llength $nets] != $width} {
        error "$port_name received [llength $nets] nets, expected $width"
    }
    set port [p3_require_one debug_port \
        [get_debug_ports -quiet [list $port_name]] $port_name]
    if {[get_property PORT_WIDTH $port] != $width} {
        error "$port_name width is [get_property PORT_WIDTH $port], expected $width"
    }
    for {set bit 0} {$bit < $width} {incr bit} {
        set pin_name "${port_name}\[$bit\]"
        set pin [p3_require_one pin [get_pins -quiet [list $pin_name]] $pin_name]
        if {[get_property DIRECTION $pin] ne "IN"} {
            error "ILA probe pin is not an input: $pin_name"
        }
        set old_net [p3_require_one net \
            [get_nets -quiet -of_objects $pin] "$pin_name existing net"]
        set old_dont_touch [p3_property_is_true $old_net DONT_TOUCH]
        if {$old_dont_touch} {
            set_property DONT_TOUCH false $old_net
        }
        disconnect_net -net $old_net -pinlist $pin
        if {$old_dont_touch} {
            set_property DONT_TOUCH true $old_net
        }
        set new_net [lindex $nets $bit]
        set new_dont_touch [p3_property_is_true $new_net DONT_TOUCH]
        if {$new_dont_touch} {
            set_property DONT_TOUCH false $new_net
        }
        connect_net -hierarchical -basename "${tag}_${bit}" \
            -net $new_net -objects $pin
        if {$new_dont_touch} {
            set_property DONT_TOUCH true $new_net
        }
    }
}

proc p3_probe_clock_net {cell_name} {
    set pin [p3_require_one pin \
        [get_pins -quiet [list "${cell_name}/clk"]] "${cell_name}/clk"]
    return [p3_require_one net [get_nets -quiet -of_objects $pin] \
        "${cell_name}/clk net"]
}

set_param general.maxThreads 16
set_msg_config -id {Vivado 12-3773} -suppress
set_msg_config -id {Constraints 18-549} -suppress
puts "Opening Build 79 pre-route checkpoint: $input_dcp"
open_checkpoint $input_dcp

set ila_cells [list \
    {u_bd/openpiton_top_i/axis_ila_0} \
    {u_bd/openpiton_top_i/axis_ila_1} \
    {u_bd/openpiton_top_i/axis_ila_2} \
    {u_bd/openpiton_top_i/axis_ila_3}]
foreach name [linsert $ila_cells 0 {axi_dbg_hub}] {
    p3_require_one debug_core [get_debug_cores -quiet [list $name]] $name
}
set common_clock [p3_probe_clock_net [lindex $ila_cells 0]]
foreach name [lrange $ila_cells 1 end] {
    set clock [p3_probe_clock_net $name]
    if {$clock ne $common_clock} {
        error "Build 80 ILAs are not synchronous: $name clock=$clock expected=$common_clock"
    }
}
puts "All four Build 80 ILAs use clock net: $common_clock"

if {!$resume_from_build80} {
set cva6 \
    {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6}
set csr "${cva6}/csr_regfile_i"
set scoreboard "${cva6}/issue_stage_i/i_scoreboard"
set commit_base "${scoreboard}/commit_instr_id_commit\[0\]"

set trigger_net [p3_q_net "${csr}/priv_lvl_q_reg\[1\]"]
set priv_nets [list \
    [p3_q_net "${csr}/priv_lvl_q_reg\[0\]"] \
    $trigger_net]
set commit_pc [p3_require_bus "${commit_base}\[pc\]" 64]
set commit_valid [p3_require_net "${commit_base}\[valid\]"]
set commit_ack [p3_require_net "${scoreboard}/commit_ack\[0\]"]
set commit_fu [p3_require_bus "${commit_base}\[fu\]" 4]
set commit_op [p3_require_bus "${commit_base}\[op\]" 8]
set ex_commit_valid [p3_require_net "${cva6}/ex_commit\[valid\]"]

set mepc_nets [list]
set mcause_nets [list]
set mtval_nets [list]
for {set bit 0} {$bit < 64} {incr bit} {
    lappend mepc_nets [p3_q_net "${csr}/mepc_q_reg\[${bit}\]"]
    lappend mcause_nets [p3_q_net "${csr}/mcause_q_reg\[${bit}\]"]
    lappend mtval_nets [p3_q_net "${csr}/mtval_q_reg\[${bit}\]"]
}

# The optimized 12-bit CSR address crosses two hierarchy prefixes.  Require
# exactly the split observed by p3_inspect_build80_trap_nets.tcl.
set csr_addr_nets [list]
for {set bit 0} {$bit < 12} {incr bit} {
    set candidates [list \
        "${cva6}/csr_addr_ex_csr\[${bit}\]" \
        "${cva6}/ex_stage_i/csr_buffer_i/csr_addr_ex_csr\[${bit}\]"]
    set matches [list]
    foreach candidate $candidates {
        set matches [concat $matches [get_nets -quiet [list $candidate]]]
    }
    lappend csr_addr_nets [p3_require_one net $matches \
        "CSR address bit $bit across optimized hierarchy"]
}

set csr_illegal [p3_require_net "${cva6}/csr_exception_csr_commit\[cause\]\[1\]"]
set wfi [p3_q_net "${csr}/wfi_q_reg"]
set mcounteren [list]
for {set bit 0} {$bit < 6} {incr bit} {
    lappend mcounteren [p3_q_net "${csr}/mcounteren_q_reg\[${bit}\]"]
}
set mstatus_mie [p3_q_net "${csr}/mstatus_q_reg\[mie\]"]
set mstatus_sie [p3_q_net "${csr}/mstatus_q_reg\[sie\]"]
set mie [list]
foreach bit {1 3 5 7 9 11} {
    lappend mie [p3_q_net "${csr}/mie_q_reg\[${bit}\]"]
}
set mip [list]
foreach bit {1 5 9} {
    lappend mip [p3_q_net "${csr}/mip_q_reg\[${bit}\]"]
}
set mideleg [list]
foreach bit {1 5 9} {
    lappend mideleg [p3_q_net "${csr}/mideleg_q_reg\[${bit}\]"]
}
set no_st_pending [p3_require_net "${cva6}/no_st_pending_ex"]
set wbuffer_empty [p3_require_net "${cva6}/dcache_commit_wbuffer_empty"]

# ILA0 probe0 is the common S-to-M trigger.  probe1..4 retain all 64 PC bits.
p3_reconnect_probe \
    {u_bd/openpiton_top_i/axis_ila_0/probe0} 1 \
    [list $trigger_net] p3_build80_ila0_trigger
for {set word 0} {$word < 4} {incr word} {
    set first [expr {$word * 16}]
    set last [expr {$first + 15}]
    p3_reconnect_probe \
        "u_bd/openpiton_top_i/axis_ila_0/probe[expr {$word + 1}]" 16 \
        [lrange $commit_pc $first $last] \
        "p3_build80_ila0_pc_[expr {$word * 16}]"
}

# ILA1 bit 0 is the common trigger.  mepc[0] is architecturally zero, so bits
# 1..63 preserve the complete architectural value.
set ila1_nets [concat [list $trigger_net] [lrange $mepc_nets 1 63]]
p3_reconnect_probe \
    {u_bd/openpiton_top_i/axis_ila_1/probe0} 64 $ila1_nets p3_build80_ila1

# ILA2 is an explicit packed state vector.  Channel order is LSB first.
set ila2_nets [concat \
    [list $ex_commit_valid $csr_illegal $commit_valid $commit_ack] \
    $commit_fu \
    $commit_op \
    $csr_addr_nets \
    $priv_nets \
    [lrange $mcause_nets 0 5] \
    [list [lindex $mcause_nets 63]] \
    $mcounteren \
    [list $wfi $mstatus_mie $mstatus_sie] \
    $mie \
    $mip \
    $mideleg \
    [list $no_st_pending $wbuffer_empty] \
    [lrange $mcause_nets 6 8] \
    [list $trigger_net]]
if {[llength $ila2_nets] != 64} {
    error "Build 80 packed state has [llength $ila2_nets] bits, expected 64"
}
p3_reconnect_probe \
    {u_bd/openpiton_top_i/axis_ila_2/probe0} 64 $ila2_nets p3_build80_ila2

# ILA3 keeps mtval[62:0] and uses bit63 for the common trigger.  Illegal
# instructions are 32-bit zero-extended values, so this loses no target data.
set ila3_nets [concat [lrange $mtval_nets 0 62] [list $trigger_net]]
p3_reconnect_probe \
    {u_bd/openpiton_top_i/axis_ila_3/probe0} 64 $ila3_nets p3_build80_ila3

set fh [open $mapping_file w]
puts $fh "Build 80 probe map (least-significant bit first)"
puts $fh "common trigger: priv_lvl_q[1] rising edge; S=01 to M=11"
puts $fh "axis_ila_0/probe0[0]: common trigger"
puts $fh "axis_ila_0/probe1..4: commit PC[63:0], four 16-bit words"
puts $fh "axis_ila_1/probe0[0]: common trigger; mepc[0] reconstructed as zero"
puts $fh "axis_ila_1/probe0[63:1]: mepc_q[63:1]"
puts $fh "axis_ila_2/probe0[0]: ex_commit.valid"
puts $fh "axis_ila_2/probe0[1]: csr_exception_csr_commit.cause[1] (CSR illegal)"
puts $fh "axis_ila_2/probe0[2]: commit valid"
puts $fh "axis_ila_2/probe0[3]: commit ack"
puts $fh "axis_ila_2/probe0[7:4]: commit FU[3:0]"
puts $fh "axis_ila_2/probe0[15:8]: commit op[7:0]"
puts $fh "axis_ila_2/probe0[27:16]: CSR address[11:0]"
puts $fh "axis_ila_2/probe0[29:28]: priv_lvl_q[1:0]"
puts $fh "axis_ila_2/probe0[35:30]: mcause_q[5:0]"
puts $fh "axis_ila_2/probe0[36]: mcause_q[63]"
puts $fh "axis_ila_2/probe0[42:37]: mcounteren_q[5:0]"
puts $fh "axis_ila_2/probe0[43]: wfi_q"
puts $fh "axis_ila_2/probe0[44]: mstatus.MIE"
puts $fh "axis_ila_2/probe0[45]: mstatus.SIE"
puts $fh "axis_ila_2/probe0[51:46]: mie[1,3,5,7,9,11]"
puts $fh "axis_ila_2/probe0[54:52]: mip[1,5,9]"
puts $fh "axis_ila_2/probe0[57:55]: mideleg[1,5,9]"
puts $fh "axis_ila_2/probe0[58]: no_st_pending_ex"
puts $fh "axis_ila_2/probe0[59]: dcache_commit_wbuffer_empty"
puts $fh "axis_ila_2/probe0[62:60]: mcause_q[8:6]"
puts $fh "axis_ila_2/probe0[63]: common trigger"
puts $fh "axis_ila_3/probe0[62:0]: mtval_q[62:0]"
puts $fh "axis_ila_3/probe0[63]: common trigger"
close $fh

write_checkpoint -force $pre_route_dcp
} else {
    if {![file exists $mapping_file] || [file size $mapping_file] == 0} {
        error "Build 80 resume requires the existing probe map: $mapping_file"
    }
    puts "Resuming from the exact Build 80 pre-route checkpoint; probe loads are already connected"
}
puts "Routing only Build 80 ECO probe loads"
route_design -eco
report_route_status -file $route_report

write_debug_probes -force $ltx_file
if {![file exists $ltx_file] || [file size $ltx_file] == 0} {
    error "write_debug_probes did not create a non-empty LTX: $ltx_file"
}
set fh [open $ltx_file r]
set ltx_text [read $fh]
close $fh
foreach marker [list \
    {0x000003FFC0000000} \
    {p3_build79_irq_2_1} \
    {p3_build76_u_bd_openpiton_top_i_axis_ila_1_probe0_0} \
    {p3_build76_u_bd_openpiton_top_i_axis_ila_1_probe0_63} \
    {p3_build79_irq_2_2} \
    {p3_build80_ila1_63} \
    {p3_build80_ila2_0} \
    {p3_build80_ila2_1} \
    {p3_build80_ila2_27} \
    {p3_build80_ila2_62} \
    {p3_build79_irq_2_4} \
    {p3_build80_ila3_0} \
    {p3_build80_ila3_62} \
    {"name": "u_bd/openpiton_top_i/p3_build79_irq_2"}] {
    if {[string first $marker $ltx_text] < 0} {
        error "generated Build 80 LTX is missing required marker: $marker"
    }
}

cd $output_dir
write_device_image -force -file $pdi_file
if {![file exists $pdi_file] || [file size $pdi_file] == 0} {
    error "write_device_image did not create a non-empty PDI: $pdi_file"
}
report_timing_summary -delay_type min_max -max_paths 20 -file $timing_report
report_drc -file $drc_report

puts "SUCCESS: Build 80 trap/CSR ECO diagnostic generated"
puts "  pre-route DCP: $pre_route_dcp"
puts "  PDI:           $pdi_file"
puts "  LTX:           $ltx_file"
puts "  probe map:     $mapping_file"
