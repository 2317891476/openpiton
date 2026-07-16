# p3_build78_store_path_eco.tcl -- Split a blocked Build 77 FENCE into the
# CVA6 store queue, WT D-cache write buffer, and core-to-L1.5 request layers.
#
# The functional Build 66 routed logic is unchanged.  This ECO only moves
# existing axis_ila_1/2 probe loads in the Build 77 pre-route checkpoint.

set default_dcp \
    {D:/p3b77_commit_valid_fix/p3_top_build77_commit_valid_fix_pre_route.dcp}
set default_output_dir {D:/p3b78_store_path_eco}

if {[llength $argv] > 2} {
    puts "ERROR: expected optional Build 77 pre-route DCP and output directory"
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
    puts "ERROR: Build 77 pre-route DCP not found: $input_dcp"
    exit 1
}

file mkdir $output_dir
set output_base "${output_dir}/p3_top_build78_store_path_eco"
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

proc p3_require_regex_net {pattern} {
    set nets [get_nets -quiet -hierarchical -regexp $pattern]
    return [p3_require_one net $nets $pattern]
}

proc p3_require_bus {base width} {
    set result [list]
    for {set bit 0} {$bit < $width} {incr bit} {
        lappend result [p3_require_net "${base}\[$bit\]"]
    }
    return $result
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
puts "Opening Build 77 pre-route ECO checkpoint: $input_dcp"
open_checkpoint $input_dcp

foreach name [list \
    {axi_dbg_hub} \
    {u_bd/openpiton_top_i/axis_ila_0} \
    {u_bd/openpiton_top_i/axis_ila_1} \
    {u_bd/openpiton_top_i/axis_ila_2} \
    {u_bd/openpiton_top_i/axis_ila_3}] {
    p3_require_one debug_core [get_debug_cores -quiet [list $name]] $name
}

# Restore the original Build 66 core history payload.  If a request remains
# asserted without request-ack, this gives its exact 40-bit physical address,
# request type, size, and the live transducer handshake flags.
set core_bus [p3_require_bus \
    {u_bd/openpiton_top_i/p3_dbg_core_bus64_i_1} 64]
for {set bit 0} {$bit < 64} {incr bit} {
    p3_reconnect_pin \
        "u_bd/openpiton_top_i/axis_ila_1/probe0\[$bit\]" \
        [lindex $core_bus $bit] "p3_build78_core_bus_${bit}"
}

set cva6 \
    {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6}
set store_buffer \
    {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6/ex_stage_i/lsu_i/i_store_unit/store_buffer_i}

# axis_ila_2/probe0[0:27] remains the Build 77 valid/ack/FU/op/LSU/L1.5
# payload.  Replace only the unused tail with store-drain layer evidence.
set diag_nets [list \
    [p3_require_net "${cva6}/no_st_pending_ex"] \
    [p3_require_net "${cva6}/dcache_commit_wbuffer_empty"]]
for {set bit 0} {$bit < 3} {incr bit} {
    lappend diag_nets [p3_require_regex_net \
        [format {.*store_buffer_i/commit_status_cnt_q\[%d\]$} $bit]]
}
for {set bit 0} {$bit < 2} {incr bit} {
    lappend diag_nets [p3_require_net \
        "${store_buffer}/commit_read_pointer_q\[$bit\]"]
}
for {set bit 0} {$bit < 8} {incr bit} {
    lappend diag_nets [p3_require_regex_net \
        [format {.*i_wt_dcache_wbuffer/valid\[%d\]$} $bit]]
}
for {set bit 0} {$bit < 8} {incr bit} {
    lappend diag_nets [p3_require_regex_net \
        [format {.*i_wt_dcache_wbuffer/dirty\[%d\]$} $bit]]
}
for {set slot 0} {$slot < 2} {incr slot} {
    lappend diag_nets [p3_require_regex_net \
        [format {.*i_wt_dcache_wbuffer/tx_stat_q_reg\[%d\]\[vld\]_0$} $slot]]
}
for {set slot 0} {$slot < 2} {incr slot} {
    for {set bit 0} {$bit < 3} {incr bit} {
        lappend diag_nets [p3_require_regex_net \
            [format {.*i_wt_dcache_wbuffer/tx_stat_q_reg\[%d\]\[ptr\]\[%d\]$} \
                $slot $bit]]
    }
}
for {set bit 0} {$bit < 3} {incr bit} {
    lappend diag_nets [p3_require_regex_net \
        [format {.*i_wt_dcache_wbuffer/dirty_ptr\[%d\]$} $bit]]
}
lappend diag_nets [p3_require_regex_net \
    {.*i_wt_dcache_wbuffer/evict3_out$}]
lappend diag_nets [p3_require_net \
    {u_bd/openpiton_top_i/p3_dbg_uart_bus64_i_1[0]}]
if {[llength $diag_nets] != 36} {
    error "Build 78 diagnostic payload has [llength $diag_nets] bits, expected 36"
}
for {set index 0} {$index < 36} {incr index} {
    set probe_bit [expr {$index + 28}]
    p3_reconnect_pin \
        "u_bd/openpiton_top_i/axis_ila_2/probe0\[$probe_bit\]" \
        [lindex $diag_nets $index] "p3_build78_diag_${index}"
}

set fh [open $mapping_file w]
puts $fh "Build 78 probe map (least-significant bit first)"
puts $fh "axis_ila_0: unchanged Build 66 layer-seen probes"
puts $fh "axis_ila_1/probe0\[63:0\]: original Build 66 core/L1.5 history bus"
puts $fh "axis_ila_2/probe0\[27:0\]: unchanged Build 77 commit/L1.5 status"
puts $fh "axis_ila_2/probe0\[28\]: no_st_pending_ex"
puts $fh "axis_ila_2/probe0\[29\]: dcache_commit_wbuffer_empty"
puts $fh "axis_ila_2/probe0\[32:30\]: store commit_status_cnt_q"
puts $fh "axis_ila_2/probe0\[34:33\]: store commit_read_pointer_q"
puts $fh "axis_ila_2/probe0\[42:35\]: WT D-cache write-buffer valid"
puts $fh "axis_ila_2/probe0\[50:43\]: WT D-cache write-buffer dirty"
puts $fh "axis_ila_2/probe0\[52:51\]: WT D-cache transaction valid"
puts $fh "axis_ila_2/probe0\[55:53\]: transaction 0 buffer pointer"
puts $fh "axis_ila_2/probe0\[58:56\]: transaction 1 buffer pointer"
puts $fh "axis_ila_2/probe0\[61:59\]: dirty buffer pointer"
puts $fh "axis_ila_2/probe0\[62\]: write-buffer evict"
puts $fh "axis_ila_2/probe0\[63\]: original UART bus bit 0 filler"
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
    {p3_dbg_core_bus64_i_1[0]} \
    {p3_dbg_core_bus64_i_1[63]} \
    {p3_build77_commit_valid} \
    {p3_build78_diag_0} \
    {p3_build78_diag_34} \
    {p3_dbg_uart_bus64_i_1[0]}] {
    if {[string first $marker $ltx_text] < 0} {
        error "generated Build 78 LTX is missing required marker: $marker"
    }
}

write_device_image -force -file $pdi_file
if {![file exists $pdi_file] || [file size $pdi_file] == 0} {
    error "write_device_image did not create a non-empty PDI: $pdi_file"
}
report_timing_summary -delay_type min_max -max_paths 20 -file $timing_report
report_drc -file $drc_report

puts "SUCCESS: Build 78 store-path ECO diagnostic generated"
puts "  pre-route DCP: $pre_route_dcp"
puts "  PDI:           $pdi_file"
puts "  LTX:           $ltx_file"
puts "  probe map:     $mapping_file"
