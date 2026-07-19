# Read-only synthesized-net audit for Build 97's adapter FIFO / L1.5 ingress
# ILA ECO. It emits retained cells, Q nets, and hierarchy pins; it never
# modifies the opened checkpoint.

if {[llength $argv] != 2} {
    error "Usage: p3_b97_resolve_check.tcl <routed.dcp> <report.txt>"
}
set input_dcp [file normalize [lindex $argv 0]]
set report_file [file normalize [lindex $argv 1]]
if {![file exists $input_dcp] || [file size $input_dcp] == 0} {
    error "Routed checkpoint is missing or empty: $input_dcp"
}
file mkdir [file dirname $report_file]

proc emit_nets {fh label pattern} {
    set nets [lsort -unique [get_nets -quiet -hier -filter "NAME =~ ${pattern}"]]
    puts $fh "\nNETS $label count=[llength $nets] pattern=${pattern}"
    foreach net $nets { puts $fh "  [get_property NAME $net]" }
}
proc emit_cells {fh label pattern} {
    set cells [lsort -unique [get_cells -quiet -hier -filter "NAME =~ ${pattern}"]]
    puts $fh "\nCELLS $label count=[llength $cells] pattern=${pattern}"
    foreach cell $cells {
        puts $fh "  CELL [get_property NAME $cell] REF=[get_property REF_NAME $cell]"
        foreach pin [get_pins -quiet -of_objects $cell -filter {DIRECTION == OUT && REF_PIN_NAME == Q}] {
            set nets [get_nets -quiet -of_objects $pin]
            puts $fh "    Q [get_property NAME $pin] NET=[join [get_property NAME $nets] ,]"
        }
    }
}
proc emit_pins {fh label pattern} {
    set pins [lsort -unique [get_pins -quiet -hier -filter "NAME =~ ${pattern}"]]
    puts $fh "\nPINS $label count=[llength $pins] pattern=${pattern}"
    foreach pin $pins {
        set nets [get_nets -quiet -of_objects $pin]
        puts $fh "  PIN [get_property NAME $pin] DIR=[get_property DIRECTION $pin] NET=[join [get_property NAME $nets] ,]"
    }
}

puts "Opening routed checkpoint read-only: $input_dcp"
open_checkpoint $input_dcp
set fh [open $report_file w]
puts $fh "Build 97 synthesized adapter-FIFO resolution audit"
puts $fh "checkpoint=$input_dcp"

emit_cells $fh dcache_fifo_cells {*i_adapter*i_dcache_data_fifo*}
emit_nets  $fh dcache_fifo_nets {*i_adapter*i_dcache_data_fifo*}
emit_pins  $fh dcache_fifo_pins {*i_adapter*i_dcache_data_fifo*}
emit_cells $fh adapter_cells {*i_adapter*}
emit_nets  $fh l15_request_nets {*g_ariane_core.l15_req*}
emit_nets  $fh transducer_request_nets {*transducer_l15*}
emit_nets  $fh transducer_return_nets {*l15_transducer*}
emit_cells $fh l15_pipeline_cells {*tile0/l15/l15/pipeline*}
emit_nets  $fh l15_pipeline_nets {*tile0/l15/l15/pipeline*}
emit_pins  $fh l15_pipeline_pins {*tile0/l15/l15/pipeline*}

close $fh
close_design
puts "SUCCESS: Build 97 resolution audit written to $report_file"
