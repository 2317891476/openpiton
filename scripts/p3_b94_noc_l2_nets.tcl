# Probe-specific NoC and L2 net names from Build 93 routed DCP.
set input_dcp {D:/p3b93_load_path/p3_top_build93_load_path_routed.dcp}
if {[llength $argv] >= 1} { set input_dcp [file normalize [lindex $argv 0]] }
open_checkpoint $input_dcp

set tile "u_openpiton/system_inst/chip/tile0"
set l15 "${tile}/l15"
set l2  "${tile}/l2"

proc list_nets {label pattern {max 30}} {
    set nets [lsort -unique [get_nets -quiet -hier -filter "NAME =~ ${pattern}"]]
    set cnt [llength $nets]
    puts "\n${label} ($cnt nets, pattern=$pattern)"
    set i 0
    foreach n $nets {
        if {$i >= $max} { puts "  ... ($cnt total)" ; break }
        puts "  $n"
        incr i
    }
}

# NoC1 (request: L1.5 -> L2) interface signals
list_nets "NOC1_val" "${tile}/*noc1*val*" 15
list_nets "NOC1_ack" "${tile}/*noc1*ack*" 10

# NoC2 (response: L2 -> L1.5) interface signals
list_nets "NOC2_val" "${tile}/*noc2*val*" 15
list_nets "NOC2_ack" "${tile}/*noc2*ack*" 10

# NoC3 (forward: L2 -> L1.5)
list_nets "NOC3_val" "${tile}/*noc3*val*" 10

# L1.5 NOC1 encoder/buffer request/ack
list_nets "L15_noc1_req" "${l15}/*noc1*req*" 15
list_nets "L15_noc1buffer_val" "${l15}/*noc1buffer*val*" 10

# L1.5 NOC2 decoder
list_nets "L15_noc2_val" "${l15}/*noc2*val*" 15

# L2 MSHR valid bits
list_nets "L2_mshr_val" "${l2}/*mshr*val*" 25

# L2 pipeline state (narrower search)
list_nets "L2_pipe1_state" "${l2}/*pipe1*state*" 15
list_nets "L2_mshr_state" "${l2}/*mshr*state*" 15

# L2 NOC1 interface (L2 receiving from L1.5)
list_nets "L2_noc1_val" "${l2}/*noc1*val*" 10
list_nets "L2_noc2_val" "${l2}/*noc2*val*" 10

# noc2decoder header_ack (L1.5 accepting NOC2 responses)
list_nets "L15_noc2decoder_ack" "${l15}/*noc2decoder*ack*" 10
list_nets "L15_noc2decoder_header_ack" "${l15}/*noc2*header_ack*" 10

close_design
puts "SUCCESS"
