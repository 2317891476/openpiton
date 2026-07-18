# p3_inspect_build91_udelay_nets.tcl -- Audit the clean Build 90 routed
# checkpoint for diagnostic-only Build 91 udelay probes.

set default_dcp \
    {D:/p3b90_time_csr_rtl/huaprop3_build90_time_csr_rtl.runs/impl_1/p3_top_routed.dcp}
set default_report \
    {Z:/home/illya/openpiton/huaprop3_build90_time_csr_rtl/build91_udelay_net_query.txt}

if {[llength $argv] > 2} {
    error "expected optional Build 90 routed DCP and report path"
}
set input_dcp $default_dcp
set report_file $default_report
if {[llength $argv] >= 1} {
    set input_dcp [file normalize [lindex $argv 0]]
}
if {[llength $argv] == 2} {
    set report_file [file normalize [lindex $argv 1]]
}
if {![file exists $input_dcp] || [file size $input_dcp] == 0} {
    error "Build 90 routed DCP is missing or empty: $input_dcp"
}

proc p3_b91_emit_q {fh label cell_name} {
    set cells [get_cells -quiet [list $cell_name]]
    if {[llength $cells] != 1} {
        puts $fh "$label MISSING_CELL count=[llength $cells] cell=$cell_name"
        return 0
    }
    set qpins [get_pins -quiet -of_objects $cells \
        -filter {DIRECTION == OUT && REF_PIN_NAME == Q}]
    set nets [get_nets -quiet -of_objects $qpins]
    puts $fh "$label cell=$cell_name qpins=$qpins nets=$nets"
    return [expr {[llength $qpins] == 1 && [llength $nets] == 1}]
}

puts "Opening Build 90 routed checkpoint: $input_dcp"
open_checkpoint $input_dcp
file mkdir [file dirname $report_file]
set fh [open $report_file w]
puts $fh "Build 91 udelay diagnostic net audit"
puts $fh "checkpoint=$input_dcp"

set cva6 \
    {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6}
set issue "${cva6}/issue_stage_i"
set regfile "${issue}/i_issue_read_operands/i_ariane_regfile"

set complete 1
foreach reg {13 14 15} {
    for {set bit 0} {$bit < 64} {incr bit} {
        if {![p3_b91_emit_q $fh "x${reg}_bit${bit}" \
                "${regfile}/mem_reg\[${reg}\]\[${bit}\]"]} {
            set complete 0
        }
    }
}

puts $fh "\nDEBUG_CORES"
foreach core [lsort [get_debug_cores -quiet]] {
    puts $fh "core=$core"
    foreach port [lsort [get_debug_ports -quiet -of_objects $core]] {
        puts $fh "  port=$port width=[get_property PORT_WIDTH $port] type=[get_property PROBE_TYPE $port]"
    }
}

puts $fh "\nWRITEBACK_CANDIDATES"
foreach token {csr_rdata_csr_commit wdata_commit_id result} {
    puts $fh "TOKEN $token"
    foreach net [lsort [get_nets -quiet -hier -filter \
            "NAME =~ ${cva6}/*${token}*"]] {
        puts $fh "  net=$net"
    }
}

puts $fh "\nRESULT complete_gpr_q=$complete"
close $fh
close_design
if {!$complete} {
    error "Build 91 audit did not find every a3/a4/a5 storage bit"
}
puts "SUCCESS: Build 91 udelay net audit written to $report_file"
