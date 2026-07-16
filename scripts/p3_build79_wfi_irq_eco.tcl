# p3_build79_wfi_irq_eco.tcl -- Probe the CVA6 WFI / interrupt-wake state.
#
# Build 78 proved the one-hart stop is non-deterministic: commit idle, store
# queue drained, write buffer empty, no L1.5 stall, timer_irq_i=1.  The next
# boundary is whether the core is in WFI and whether the interrupt-wake
# conditions (mip & mie & mstatus.MIE/mstatus.SIE with mideleg and priv_lvl)
# are actually met.
#
# This ECO keeps probe0[0:27] (Build 77 commit/L1.5 status) and replaces
# probe0[28:63] with:
#   [28]      wfi_q
#   [29:30]   priv_lvl_q[1:0]
#   [31]      mstatus.MIE
#   [32]      mstatus.SIE
#   [33:38]   mie[1,3,5,7,9,11]  (SSIE,MSIE,STIE,MTIE,SEIE,MEIE)
#   [39:41]   mip[1,5,9]         (SSIP,STIP,SEIP)
#   [42:44]   mideleg[1,5,9]
#   [45]      no_st_pending_ex   (store-path context)
#   [46]      dcache_commit_wbuffer_empty
#   [47:63]   Build 78 store-path detail (unchanged)
#
# The functional Build 66 routed logic is unchanged.  Only ILA2 probe loads
# in the Build 78 pre-route checkpoint are reconnected.

set default_dcp \
    {D:/p3b78_store_path_eco/p3_top_build78_store_path_eco_pre_route.dcp}
set default_output_dir {D:/p3b79_wfi_irq_eco}

if {[llength $argv] > 2} {
    puts "ERROR: expected optional pre-route DCP and output directory"
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
    puts "ERROR: pre-route DCP not found: $input_dcp"
    exit 1
}

file mkdir $output_dir
set output_base "${output_dir}/p3_top_build79_wfi_irq_eco"
set mapping_file "${output_base}_probe_map.txt"
set pre_route_dcp "${output_base}_pre_route.dcp"
set route_report "${output_base}_route_status.rpt"
set timing_report "${output_base}_timing_summary.rpt"
set drc_report "${output_base}_drc.rpt"
set ltx_file "${output_base}.ltx"
set pdi_file "${output_base}.pdi"

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

# Return the net driven by the Q pin of a register cell.  This is more
# robust than guessing the optimized net name.
proc p3_q_net {cell_name} {
    set cell [p3_require_cell $cell_name]
    set qpin [p3_require_one pin [get_pins -quiet -of_objects $cell \
        -filter {DIRECTION == OUT && NAME =~ */Q}] "${cell_name}/Q"]
    set net [get_nets -quiet -of_objects $qpin]
    return [p3_require_one net $net "${cell_name}/Q net"]
}

proc p3_property_is_true {object property} {
    set value [get_property $property $object]
    return [expr {$value eq "1" || [string equal -nocase $value "true"]}]
}

proc p3_reconnect_pin {pin_name new_net basename} {
    set pin [p3_require_one pin [get_pins -quiet [list $pin_name]] $pin_name]
    if {[get_property DIRECTION $pin] ne "IN"} {
        error "ILA probe pin is not an input: $pin_name"
    }
    set old_net [p3_require_one net \
        [get_nets -quiet -of_objects $pin] $pin_name]
    set old_dont_touch [p3_property_is_true $old_net DONT_TOUCH]
    if {$old_dont_touch} {
        set_property DONT_TOUCH false $old_net
    }
    disconnect_net -net $old_net -pinlist $pin
    if {$old_dont_touch} {
        set_property DONT_TOUCH true $old_net
    }
    set new_dont_touch [p3_property_is_true $new_net DONT_TOUCH]
    if {$new_dont_touch} {
        set_property DONT_TOUCH false $new_net
    }
    connect_net -hierarchical -basename $basename -net $new_net -objects $pin
    if {$new_dont_touch} {
        set_property DONT_TOUCH true $new_net
    }
}

set_param general.maxThreads 16
set_msg_config -id {Vivado 12-3773} -suppress
set_msg_config -id {Constraints 18-549} -suppress
puts "Opening Build 78 pre-route ECO checkpoint: $input_dcp"
open_checkpoint $input_dcp

foreach name [list \
    {axi_dbg_hub} \
    {u_bd/openpiton_top_i/axis_ila_0} \
    {u_bd/openpiton_top_i/axis_ila_1} \
    {u_bd/openpiton_top_i/axis_ila_2} \
    {u_bd/openpiton_top_i/axis_ila_3}] {
    p3_require_one debug_core [get_debug_cores -quiet [list $name]] $name
}

# CVA6 CSR register file prefix.
set csr \
    {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6/csr_regfile_i}

# Build the WFI/IRQ probe net list.  Each entry uses p3_q_net to follow the
# Q output of the exact register cell, avoiding Vivado's optimized net names.
set irq_nets [list]

# [28] wfi_q
lappend irq_nets [p3_q_net "${csr}/wfi_q_reg"]

# [29:30] priv_lvl_q[1:0]
lappend irq_nets [p3_q_net "${csr}/priv_lvl_q_reg\[0\]"]
lappend irq_nets [p3_q_net "${csr}/priv_lvl_q_reg\[1\]"]

# [31] mstatus.MIE
lappend irq_nets [p3_q_net "${csr}/mstatus_q_reg\[mie\]"]

# [32] mstatus.SIE
lappend irq_nets [p3_q_net "${csr}/mstatus_q_reg\[sie\]"]

# [33:38] mie[1,3,5,7,9,11]
foreach bit {1 3 5 7 9 11} {
    lappend irq_nets [p3_q_net "${csr}/mie_q_reg\[${bit}\]"]
}

# [39:41] mip[1,5,9]
foreach bit {1 5 9} {
    lappend irq_nets [p3_q_net "${csr}/mip_q_reg\[${bit}\]"]
}

# [42:44] mideleg[1,5,9]
foreach bit {1 5 9} {
    lappend irq_nets [p3_q_net "${csr}/mideleg_q_reg\[${bit}\]"]
}

if {[llength $irq_nets] != 17} {
    error "WFI/IRQ payload has [llength $irq_nets] bits, expected 17"
}

# Reconnect ILA2 probe0[28:44] with the WFI/IRQ state.
for {set index 0} {$index < 17} {incr index} {
    set probe_bit [expr {$index + 28}]
    p3_reconnect_pin \
        "u_bd/openpiton_top_i/axis_ila_2/probe0\[$probe_bit\]" \
        [lindex $irq_nets $index] "p3_build79_irq_${index}"
}

# Keep probe0[45:63] as Build 78 store-path context (unchanged from Build 78).

set fh [open $mapping_file w]
puts $fh "Build 79 probe map (least-significant bit first)"
puts $fh "axis_ila_0: unchanged Build 66 layer-seen probes"
puts $fh "axis_ila_1/probe0\[63:0\]: original Build 66 core/L1.5 history bus"
puts $fh "axis_ila_2/probe0\[27:0\]: unchanged Build 77 commit/L1.5 status"
puts $fh "axis_ila_2/probe0\[28\]: wfi_q"
puts $fh "axis_ila_2/probe0\[29:30\]: priv_lvl_q\[1:0\]"
puts $fh "axis_ila_2/probe0\[31\]: mstatus.MIE"
puts $fh "axis_ila_2/probe0\[32\]: mstatus.SIE"
puts $fh "axis_ila_2/probe0\[33:38\]: mie\[1,3,5,7,9,11\] (SSIE,MSIE,STIE,MTIE,SEIE,MEIE)"
puts $fh "axis_ila_2/probe0\[39:41\]: mip\[1,5,9\] (SSIP,STIP,SEIP)"
puts $fh "axis_ila_2/probe0\[42:44\]: mideleg\[1,5,9\]"
puts $fh "axis_ila_2/probe0\[45\]: no_st_pending_ex"
puts $fh "axis_ila_2/probe0\[46\]: dcache_commit_wbuffer_empty"
puts $fh "axis_ila_2/probe0\[63:47\]: Build 78 store-path detail (unchanged)"
puts $fh "axis_ila_3: unchanged Build 66 DDR history bus"
close $fh

write_checkpoint -force $pre_route_dcp
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
    {p3_build79_irq_0} \
    {p3_build79_irq_16} \
    {p3_build77_commit_valid}] {
    if {[string first $marker $ltx_text] < 0} {
        error "generated Build 79 LTX is missing required marker: $marker"
    }
}

# write_device_image writes intermediate .rnpi files relative to the
# current working directory, so cd to the output directory first.
cd $output_dir
write_device_image -force -file $pdi_file
if {![file exists $pdi_file] || [file size $pdi_file] == 0} {
    error "write_device_image did not create a non-empty PDI: $pdi_file"
}
report_timing_summary -delay_type min_max -max_paths 20 -file $timing_report
report_drc -file $drc_report

puts "SUCCESS: Build 79 WFI/IRQ ECO diagnostic generated"
puts "  pre-route DCP: $pre_route_dcp"
puts "  PDI:           $pdi_file"
puts "  LTX:           $ltx_file"
puts "  probe map:     $mapping_file"
