# p3_inspect_build75_debug_nets.tcl -- Inspect the synthesized Build 66
# single-hart netlist for Build 75 PC/L1.5 diagnostic probe candidates.
#
# Usage:
#   vivado -mode batch -source scripts/p3_inspect_build75_debug_nets.tcl
#   vivado -mode batch -source scripts/p3_inspect_build75_debug_nets.tcl -tclargs \
#     <synth.dcp> <report.txt>

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]
set default_dcp [file normalize \
    "${repo_dir}/p3b66/huaprop3_build66_baseline.runs/synth_1/p3_top.dcp"]
set default_report [file normalize \
    "${repo_dir}/build/huaprop3/build75/build75_debug_net_candidates.txt"]

if {[llength $argv] > 2} {
    puts "ERROR: expected optional synth DCP and report paths"
    exit 1
}
set dcp_file $default_dcp
set report_file $default_report
if {[llength $argv] >= 1} {
    set dcp_file [file normalize [lindex $argv 0]]
}
if {[llength $argv] == 2} {
    set report_file [file normalize [lindex $argv 1]]
}
if {![file exists $dcp_file]} {
    puts "ERROR: synthesized checkpoint not found: $dcp_file"
    exit 1
}

proc p3_report_objects {fh kind pattern objects} {
    puts $fh ""
    puts $fh "${kind}_PATTERN ${pattern}"
    puts $fh "count=[llength $objects]"
    set limit 400
    foreach obj [lrange $objects 0 [expr {$limit - 1}]] {
        set width ""
        set mark_debug ""
        catch {set width [get_property WIDTH $obj]}
        catch {set mark_debug [get_property MARK_DEBUG $obj]}
        puts $fh "  $obj width=$width mark_debug=$mark_debug"
    }
    if {[llength $objects] > $limit} {
        puts $fh "  ... truncated after ${limit} objects"
    }
}

file mkdir [file dirname $report_file]
set fh [open $report_file w]
puts $fh "Build 75 synthesized debug-net candidate report"
puts $fh "DCP: $dcp_file"

open_checkpoint $dcp_file

foreach pattern [list \
    "*commit_instr_id_commit*" \
    "*commit_ack*" \
    "*pc_commit*" \
    "*lsu_addr*" \
    "*lsu_wdata*" \
    "*lsu_wmask*" \
    "*stall_tag_match_stall_s1*" \
    "*stall_index_conflict_stall_s1*" \
    "*stall_mshr_allocation_busy_s1*" \
    "*stall_pcx_noc1_buffer_s1*" \
    "*stall_noc1_command_buffer_unavail_s1*" \
    "*stall_noc1_data_buffer_unavail_s1*" \
    "*stall_s1*" \
    "*stall_s2*" \
    "*stall_s3*" \
    "*pcx_ack_s1*" \
    "*acklogic_pcx_s1*" \
    "*val_s1*" \
    "*transducer_l15_val*" \
    "*l15_transducer_ack*" \
    "*mshr*" \
    "*noc1*credit*" \
    "*noc1*buffer*" \
] {
    p3_report_objects $fh NET $pattern \
        [get_nets -quiet -hier -filter "NAME =~ $pattern"]
}

foreach pattern [list \
    "*ariane*" \
    "*l15*pipeline*" \
    "*noc1*buffer*" \
] {
    p3_report_objects $fh CELL $pattern \
        [get_cells -quiet -hier -filter "NAME =~ $pattern"]
}

close_design
close $fh
puts "Wrote Build 75 debug-net report: $report_file"
