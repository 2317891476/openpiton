# p3_b94_adapter_noc_probe.tcl -- Resolve-check for adapter/L1.5/NoC signals
# in the Build 93 routed DCP. No ILA rewiring; just probes what nets exist.
set input_dcp {D:/p3b93_load_path/p3_top_build93_load_path_routed.dcp}
if {[llength $argv] >= 1} { set input_dcp [file normalize [lindex $argv 0]] }
puts "Opening: $input_dcp"
open_checkpoint $input_dcp

set cva6 {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6}
set cache "${cva6}/i_cache_subsystem"
set adapter "${cache}/i_adapter"
set l15 "u_openpiton/system_inst/chip/tile0/l15"

proc chk {label name} {
    set n [lsort -unique [get_nets -quiet [list $name]]]
    set cnt [llength $n]
    if {$cnt == 1} { puts "OK   $label : [lindex $n 0]" } else { puts "FAIL $label ($cnt) : $name" }
}
proc chk_hier {label pattern} {
    set n [lsort -unique [get_nets -quiet -hier -filter "NAME =~ ${pattern}"]]
    set cnt [llength $n]
    puts "HIER $label ($cnt) : $pattern"
    if {$cnt <= 5} { foreach x $n { puts "  $x" } }
}

puts "\n=== adapter FIFO state ==="
chk adapter_dcache_data_full  "${adapter}/dcache_data_full"
chk adapter_dcache_data_empty "${adapter}/dcache_data_empty"
chk adapter_icache_data_full  "${adapter}/icache_data_full"
chk adapter_icache_data_empty "${adapter}/icache_data_empty"
chk adapter_arb_req0 "${adapter}/arb_req\[0\]"
chk adapter_arb_req1 "${adapter}/arb_req\[1\]"
chk adapter_arb_ack0 "${adapter}/arb_ack\[0\]"
chk adapter_arb_ack1 "${adapter}/arb_ack\[1\]"
chk adapter_arb_idx  "${adapter}/arb_idx"

puts "\n=== L1.5 request interface (transducer side) ==="
chk l15_transducer_ack         "${l15}/l15_transducer_ack"
chk l15_transducer_header_ack  "${l15}/l15_transducer_header_ack"
chk l15_transducer_val         "${l15}/l15_transducer_val"
chk transducer_l15_val         "${l15}/transducer_l15_val"
chk transducer_l15_rqtype_0    "${l15}/transducer_l15_rqtype\[0\]"

puts "\n=== L1.5↔core PCX/CPX ==="
chk_hier pcx_transducer_req "u_openpiton/system_inst/chip/tile0/pcx_transducer_req*"
chk_hier transducer_pcx_grant "u_openpiton/system_inst/chip/tile0/transducer_pcx_grant*"

puts "\n=== NoC interface at tile boundary ==="
chk_hier noc1_val "u_openpiton/system_inst/chip/tile0/*noc1*val*"
chk_hier noc1_ack "u_openpiton/system_inst/chip/tile0/*noc1*ack*"
chk_hier noc2_val "u_openpiton/system_inst/chip/tile0/*noc2*val*"
chk_hier noc2_ack "u_openpiton/system_inst/chip/tile0/*noc2*ack*"

puts "\n=== L1.5 NOC1/NOC2 buffer FIFO status ==="
chk_hier noc1_fifo "u_openpiton/system_inst/chip/tile0/l15/*noc1*fifo*"
chk_hier noc2_fifo "u_openpiton/system_inst/chip/tile0/l15/*noc2*fifo*"

puts "\n=== L2 MSHR / state ==="
set l2 "u_openpiton/system_inst/chip/tile0/l2"
chk_hier l2_mshr "${l2}/*mshr*val*"
chk_hier l2_state "${l2}/*state*"

puts "\n=== done ==="
close_design
