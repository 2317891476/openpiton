# p3_inspect_build81_wbuffer_nets.tcl -- Inventory retained WT D-cache write
# buffer progress nets before defining the Build 81 probe-only ECO.

set default_dcp \
    {D:/p3b80_trap_csr_eco/p3_top_build80_trap_csr_eco_pre_route.dcp}
set default_report {D:/p3b80_trap_csr_eco/build81_wbuffer_net_query.txt}

if {[llength $argv] > 2} {
    puts "ERROR: expected optional Build 80 pre-route DCP and report path"
    exit 1
}
set input_dcp $default_dcp
set report_file $default_report
if {[llength $argv] >= 1} {
    set input_dcp [file normalize [lindex $argv 0]]
}
if {[llength $argv] == 2} {
    set report_file [file normalize [lindex $argv 1]]
}
if {![file exists $input_dcp]} {
    puts "ERROR: Build 80 pre-route DCP not found: $input_dcp"
    exit 1
}

open_checkpoint $input_dcp
set fh [open $report_file w]
puts $fh "Build 81 retained WT D-cache write-buffer net inventory"
puts $fh "checkpoint=$input_dcp"

set patterns [list \
    {.*i_wt_dcache_wbuffer/(miss_req_o|miss_ack_i|miss_rtrn_vld_i|miss_rtrn_id_i).*$} \
    {.*i_wt_dcache_wbuffer/(rtrn_empty|rtrn_id|rtrn_ptr|evict3_out|evict|free_tx_slots|dirty_rd_en).*$} \
    {.*i_wt_dcache_wbuffer/(rd_req_o|rd_ack_i|wr_req_o|wr_ack_i|check_en_q|check_en_q1).*$} \
    {.*i_wt_dcache_wbuffer/(valid|dirty|tocheck|tx_vld_o|tx_stat_q_reg|dirty_ptr).*$} \
    {.*i_wt_dcache_wbuffer/wbuffer_q_reg.*(valid|dirty|txblock|checked).*$}]

foreach pattern $patterns {
    puts $fh ""
    puts $fh "pattern=$pattern"
    set matches [lsort [get_nets -quiet -hierarchical -regexp $pattern]]
    puts $fh "count=[llength $matches]"
    foreach net $matches {
        puts $fh $net
    }
}

puts $fh ""
puts $fh "parent wt_dcache progress nets"
set parent_patterns [list \
    {.*i_wt_dcache/(miss_req|miss_ack|miss_rtrn_vld|miss_rtrn_id|rd_req|rd_ack|wr_req|wr_ack).*$} \
    {.*i_wt_dcache/(mem_data_req_o|mem_data_ack_i|mem_data_if|missunit).*$}]
foreach pattern $parent_patterns {
    puts $fh "pattern=$pattern"
    set matches [lsort [get_nets -quiet -hierarchical -regexp $pattern]]
    puts $fh "count=[llength $matches]"
    foreach net $matches {
        puts $fh $net
    }
}

puts $fh ""
puts $fh "write-buffer register cells"
set cell_pattern \
    {.*i_wt_dcache_wbuffer/(wbuffer_q_reg|tx_stat_q_reg|check_en_q|check_en_q1).*$}
set cells [lsort [get_cells -quiet -hierarchical -regexp $cell_pattern]]
puts $fh "count=[llength $cells]"
foreach cell $cells {
    puts $fh $cell
}

close $fh
puts "SUCCESS: Build 81 write-buffer inventory written to $report_file"
close_design
