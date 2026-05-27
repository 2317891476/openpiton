# p3_inspect_build32_ila_nets.tcl -- Inspect Build 32 routed ILA probe nets.
#
# Usage:
#   vivado -mode batch -source scripts/p3_inspect_build32_ila_nets.tcl

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]
set run_dir [file normalize "${repo_dir}/huaprop3_openpiton/huaprop3_openpiton.runs/impl_32_runmgr_chipset_ila"]
set routed_dcp "${run_dir}/p3_top_routed.dcp"
set out_file [file normalize "${repo_dir}/huaprop3_openpiton/debug_build/build32_ila_net_inspect.txt"]

proc p3_puts {fh msg} {
    puts $msg
    puts $fh $msg
}

proc p3_report_objects {fh label objects} {
    p3_puts $fh "$label count=[llength $objects]"
    foreach obj $objects {
        p3_puts $fh "  $obj"
    }
}

proc p3_report_pin_net {fh pin_pattern} {
    set pins [get_pins -quiet -hier -filter "NAME =~ $pin_pattern"]
    p3_puts $fh ""
    p3_puts $fh "PIN_PATTERN $pin_pattern"
    p3_report_objects $fh "pins" $pins
    foreach pin $pins {
        set nets [get_nets -quiet -of_objects $pin]
        p3_puts $fh "  PIN $pin"
        p3_report_objects $fh "  nets" $nets
        foreach net $nets {
            set props [list]
            foreach prop [list NAME TYPE IS_CLOCK IS_CONNECTED MARK_DEBUG DONT_TOUCH] {
                if {![catch {get_property $prop $net} v]} {
                    lappend props "${prop}=${v}"
                }
            }
            p3_puts $fh "    NET_PROPS [join $props { }]"
            set drivers [get_pins -quiet -of_objects $net -filter {DIRECTION == OUT}]
            set loads [get_pins -quiet -of_objects $net -filter {DIRECTION == IN}]
            p3_report_objects $fh "    drivers" $drivers
            p3_report_objects $fh "    loads_first20" [lrange $loads 0 19]
        }
    }
}

file mkdir [file dirname $out_file]
set fh [open $out_file w]

p3_puts $fh "Build 32 routed ILA net inspection"
p3_puts $fh "DCP: $routed_dcp"

open_checkpoint $routed_dcp

foreach pat [list \
    "*u_bd/openpiton_top_i/axis_ila_0*probe0*" \
    "*u_bd/openpiton_top_i/axis_ila_0*probe1*" \
    "*u_bd/openpiton_top_i/axis_ila_0*probe2*" \
    "*u_bd/openpiton_top_i/axis_ila_1*probe0*" \
    "*u_bd/openpiton_top_i/axis_ila_0*clk*" \
    "*u_bd/openpiton_top_i/axis_ila_1*clk*" \
    "*u_bd/openpiton_top_i*p3_dbg_heartbeat_bit_i*" \
    "*u_bd/openpiton_top_i*p3_dbg_top_status16_i*" \
    "*u_bd/openpiton_top_i*p3_dbg_chipset_seen16_i*" \
    "*u_bd/openpiton_top_i*p3_dbg_chipset_bus64_i*" \
    "*p3_min_dbg_heartbeat*reg*" \
] {
    p3_report_pin_net $fh $pat
}

p3_puts $fh ""
p3_puts $fh "CELL_SEARCH axis_ila"
p3_report_objects $fh "cells" [get_cells -quiet -hier -filter {NAME =~ *axis_ila*}]

p3_puts $fh ""
p3_puts $fh "NET_SEARCH p3_dbg"
p3_report_objects $fh "nets" [get_nets -quiet -hier -filter {NAME =~ *p3_dbg*}]

p3_puts $fh ""
p3_puts $fh "NET_SEARCH heartbeat"
p3_report_objects $fh "nets" [get_nets -quiet -hier -filter {NAME =~ *heartbeat*}]

close_design
close $fh
puts "Wrote $out_file"
