# Read-only Build 98 endpoint audit. This resolves nets from implemented
# hierarchical ports and primitive pins, avoiding assumptions about RTL names
# that synthesis may remove.

if {[llength $argv] != 2} {
    error "Usage: p3_inspect_build98_storewait_pins.tcl <routed.dcp> <report.txt>"
}
set input_dcp [file normalize [lindex $argv 0]]
set report_file [file normalize [lindex $argv 1]]
if {![file exists $input_dcp] || [file size $input_dcp] == 0} {
    error "Routed checkpoint is missing or empty: $input_dcp"
}
file mkdir [file dirname $report_file]

proc req1 {kind objects label} {
    if {[llength $objects] != 1} {
        error "expected one $kind for $label, found [llength $objects]"
    }
    return [lindex $objects 0]
}

proc emit_cell_pins {fh label cell_name} {
    set cell [req1 cell [get_cells -quiet [list $cell_name]] $cell_name]
    puts $fh "\nCELL $label name=[get_property NAME $cell] ref=[get_property REF_NAME $cell]"
    foreach pin [lsort -dictionary [get_pins -quiet -of_objects $cell]] {
        set nets [get_nets -quiet -of_objects $pin]
        puts $fh "  pin=[get_property NAME $pin] ref=[get_property REF_PIN_NAME $pin] dir=[get_property DIRECTION $pin] nets=$nets"
    }
}

proc emit_pin_driver {fh label cell_name ref_pin} {
    set cell [req1 cell [get_cells -quiet [list $cell_name]] $cell_name]
    set pin [req1 pin [get_pins -quiet -of_objects $cell \
        -filter "REF_PIN_NAME == ${ref_pin}"] "${cell_name}/${ref_pin}"]
    set net [req1 net [get_nets -quiet -of_objects $pin] \
        "${cell_name}/${ref_pin} net"]
    puts $fh "\nPIN_DRIVER $label pin=[get_property NAME $pin] net=[get_property NAME $net]"
    set drivers [get_pins -quiet -of_objects $net -filter {DIRECTION == OUT}]
    if {[llength $drivers] == 0} {
        puts $fh {  drivers=<none>}
    }
    foreach driver [lsort -dictionary $drivers] {
        set driver_cell [get_cells -quiet -of_objects $driver]
        puts $fh "  driver_pin=[get_property NAME $driver] cell=$driver_cell"
        foreach source_cell $driver_cell {
            puts $fh "  driver_cell_name=[get_property NAME $source_cell] ref=[get_property REF_NAME $source_cell] init=[get_property INIT $source_cell]"
            foreach source_pin [lsort -dictionary [get_pins -quiet -of_objects $source_cell]] {
                set source_nets [get_nets -quiet -of_objects $source_pin]
                puts $fh "    pin=[get_property NAME $source_pin] ref=[get_property REF_PIN_NAME $source_pin] dir=[get_property DIRECTION $source_pin] nets=$source_nets"
            }
        }
    }
}

proc emit_pin_fanout {fh label cell_name ref_pin} {
    set cell [req1 cell [get_cells -quiet [list $cell_name]] $cell_name]
    set pin [req1 pin [get_pins -quiet -of_objects $cell \
        -filter "REF_PIN_NAME == ${ref_pin}"] "${cell_name}/${ref_pin}"]
    set net [req1 net [get_nets -quiet -of_objects $pin] \
        "${cell_name}/${ref_pin} net"]
    puts $fh "\nPIN_FANOUT $label pin=[get_property NAME $pin] net=[get_property NAME $net]"
    set sinks [all_fanout -from $net -flat -only_cells -levels 1]
    foreach sink [lsort -dictionary $sinks] {
        puts $fh "  sink_name=[get_property NAME $sink] ref=[get_property REF_NAME $sink] init=[get_property INIT $sink]"
        foreach sink_pin [lsort -dictionary [get_pins -quiet -of_objects $sink]] {
            if {[lsearch -exact [get_nets -quiet -of_objects $sink_pin] $net] >= 0} {
                puts $fh "    pin=[get_property NAME $sink_pin] ref=[get_property REF_PIN_NAME $sink_pin] dir=[get_property DIRECTION $sink_pin]"
            }
        }
    }
}

puts "Opening routed checkpoint: $input_dcp"
open_checkpoint $input_dcp
set fh [open $report_file w]
puts $fh "Build 98 STORE_WAIT endpoint audit"
puts $fh "checkpoint=$input_dcp"

set tile {u_openpiton/system_inst/chip/tile0}
set cva6 "${tile}/g_ariane_core.core/ariane/i_cva6"
set cache "${cva6}/i_cache_subsystem"
set dcache "${cache}/i_wt_dcache"
set missunit "${dcache}/i_wt_dcache_missunit"
set adapter "${cache}/i_adapter"
set dcfifo "${adapter}/i_dcache_data_fifo/i_fifo_v3"

emit_cell_pins $fh cache_subsystem $cache
emit_cell_pins $fh dcache $dcache
emit_cell_pins $fh missunit $missunit
emit_cell_pins $fh adapter $adapter
emit_cell_pins $fh dcache_fifo $dcfifo
for {set bit 0} {$bit < 3} {incr bit} {
    emit_cell_pins $fh "missunit_state_${bit}" "${missunit}/FSM_sequential_state_q_reg\[${bit}\]"
}
for {set bit 0} {$bit < 2} {incr bit} {
    emit_cell_pins $fh "dcache_fifo_count_${bit}" "${dcfifo}/status_cnt_q_reg\[${bit}\]"
}
emit_cell_pins $fh dcache_fifo_read_pointer "${dcfifo}/read_pointer_q_reg\[0\]"
emit_cell_pins $fh dcache_fifo_write_pointer "${dcfifo}/write_pointer_q_reg\[0\]"
emit_pin_driver $fh missunit_state_ce "${missunit}/FSM_sequential_state_q_reg\[0\]" CE
emit_pin_driver $fh dcache_fifo_count_ce "${dcfifo}/status_cnt_q_reg\[0\]" CE
for {set bit 0} {$bit < 6} {incr bit} {
    emit_pin_driver $fh "missunit_state_ce_lut_i${bit}" \
        "${missunit}/FSM_sequential_state_q\[2\]_i_1__0" "I${bit}"
}
for {set bit 0} {$bit < 2} {incr bit} {
    emit_pin_fanout $fh "dcache_fifo_count_q_${bit}" \
        "${dcfifo}/status_cnt_q_reg\[${bit}\]" Q
}

close $fh
close_design
puts "SUCCESS: Build 98 endpoint audit written to $report_file"
