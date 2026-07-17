# p3_inspect_build81_clock_load.tcl -- Identify any ILA data probe connected
# to a clock-classified net in the Build 81 pre-route checkpoint.

set default_dcp \
    {D:/p3b81_wbuffer_eco/p3_top_build81_wbuffer_eco_pre_route.dcp}
set default_report {D:/p3b81_wbuffer_eco/clock_probe_loads.txt}
set input_dcp $default_dcp
set report_file $default_report
if {[llength $argv] >= 1} {
    set input_dcp [file normalize [lindex $argv 0]]
}
if {[llength $argv] >= 2} {
    set report_file [file normalize [lindex $argv 1]]
}
if {![file exists $input_dcp]} {
    error "Build 81 pre-route DCP not found: $input_dcp"
}

open_checkpoint $input_dcp
set fh [open $report_file w]
puts $fh "Build 81 ILA data loads on clock-classified nets"
set count 0
foreach index {0 1 2 3} {
    set cell "u_bd/openpiton_top_i/axis_ila_${index}"
    foreach port [get_debug_ports -quiet -of_objects \
        [get_debug_cores -quiet [list $cell]]] {
        if {![string match "*/probe*" [get_property NAME $port]]} {
            continue
        }
        set width [get_property PORT_WIDTH $port]
        for {set bit 0} {$bit < $width} {incr bit} {
            set pin [get_pins -quiet "[get_property NAME $port]\[${bit}\]"]
            set net [get_nets -quiet -of_objects $pin]
            set clocks [get_clocks -quiet -of_objects $net]
            if {[llength $clocks]} {
                incr count
                puts $fh "pin=$pin net=$net clocks=$clocks"
            }
        }
    }
}
puts $fh "count=$count"
puts $fh ""
puts $fh "p3_chip_debug_bus_BUFG nets and loads"
foreach net [get_nets -quiet -hierarchical -filter \
    {NAME =~ *p3_chip_debug_bus_BUFG*}] {
    puts $fh "net=$net clocks=[get_clocks -quiet -of_objects $net]"
    foreach pin [get_pins -quiet -of_objects $net] {
        puts $fh "  pin=$pin direction=[get_property DIRECTION $pin]"
    }
}
close $fh
puts "SUCCESS: Build 81 clock-load report written to $report_file"
close_design
