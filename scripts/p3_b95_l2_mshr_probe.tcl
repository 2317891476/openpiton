# p3_b95_l2_mshr_probe.tcl -- Resolve-check for L2 MSHR address/state and L2 NoC output.
set input_dcp {D:/p3b94_noc_boundary/p3_top_build94_noc_boundary_routed.dcp}
if {[llength $argv] >= 1} { set input_dcp [file normalize [lindex $argv 0]] }
open_checkpoint $input_dcp
set l2 "u_openpiton/system_inst/chip/tile0/l2"

proc chk {label name} {
    set n [lsort -unique [get_nets -quiet [list $name]]]
    set cnt [llength $n]
    if {$cnt == 1} { puts "OK   $label : [lindex $n 0]" } else { puts "FAIL $label ($cnt) : $name" }
}
proc chk_hier {label pattern {max 10}} {
    set nets [lsort -unique [get_nets -quiet -hier -filter "NAME =~ ${pattern}"]]
    set cnt [llength $nets]
    puts "HIER $label ($cnt) : $pattern"
    set i 0
    foreach n $nets { if {$i >= $max} { puts "  ... ($cnt total)" ; break }; puts "  $n"; incr i }
}
proc chk_cell {label cell_name} {
    set cells [get_cells -quiet [list $cell_name]]
    set cnt [llength $cells]
    if {$cnt == 1} {
        set qp [get_pins -quiet -of_objects [lindex $cells 0] -filter {DIRECTION == OUT && REF_PIN_NAME == Q}]
        set nets [get_nets -quiet -of_objects $qp]
        puts "OKC  $label : [lindex $cells 0] qnet=[lindex $nets 0]"
    } else { puts "FAIL $label ($cnt) : $cell_name" }
}

puts "\n=== L2 MSHR state ==="
chk_hier "mshr_state" "${l2}/mshr_wrap/*state_mem*" 16
chk_hier "mshr_addr" "${l2}/mshr_wrap/*addr*" 16

puts "\n=== L2 msg_send (NoC1 output) ==="
chk_hier "msg_send_valid" "${l2}/*msg_send_valid*" 10
chk_hier "msg_send_type" "${l2}/*msg_send_type*" 10
chk_hier "msg_send_mshrid" "${l2}/*msg_send_mshrid*" 5

puts "\n=== L2 noc1 output ==="
chk_hier "noc1_msg_val" "${l2}/*noc1*val*" 10
chk_hier "noc1_msg_data" "${l2}/*noc1*data*" 5

puts "\n=== L2 pipe1 state ==="
chk_hier "pipe1_valid_S2" "${l2}/*valid_S2*" 10
chk_hier "pipe1_stall" "${l2}/*stall*" 10

puts "\n=== L2 input from NoC2 (responses) ==="
chk_hier "noc2_msg" "${l2}/*noc2*" 10
chk_hier "l2_msg_header" "${l2}/*msg_header*" 10

puts "\n=== chipset memory bridge NoC interface ==="
set cs "u_openpiton/system_inst/chipset/chipset_impl"
chk_hier "mc_flit_in" "${cs}/*mc_flit_in*" 10
chk_hier "mc_flit_out" "${cs}/*mc_flit_out*" 10

puts "\n=== AXI interface ==="
chk_hier "axi_arvalid" "u_openpiton/*axi_arvalid*"
chk_hier "axi_arready" "u_openpiton/*axi_arready*"
chk_hier "axi_rvalid" "u_openpiton/*axi_rvalid*"
chk_hier "axi_rready" "u_openpiton/*axi_rready*"

close_design
puts "SUCCESS"
