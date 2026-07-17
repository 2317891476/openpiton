# p3_inspect_build80_trap_nets.tcl -- Inventory retained trap-state nets in
# the board-validated Build 79 pre-route ECO checkpoint.

set default_dcp \
    {D:/p3b79_wfi_irq_eco/p3_top_build79_wfi_irq_eco_pre_route.dcp}
set default_report {D:/p3b79_wfi_irq_eco/build80_trap_net_query.txt}

if {[llength $argv] > 2} {
    puts "ERROR: expected optional Build 79 DCP and report path"
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
    puts "ERROR: Build 79 pre-route DCP not found: $input_dcp"
    exit 1
}

proc p3_puts {fh text} {
    puts $text
    puts $fh $text
}

proc p3_report_cells {fh label pattern} {
    set cells [lsort [get_cells -quiet -hier -filter "NAME =~ $pattern"]]
    p3_puts $fh "$label count=[llength $cells] pattern=$pattern"
    foreach cell $cells {
        set q_pins [get_pins -quiet -of_objects $cell \
            -filter {DIRECTION == OUT && NAME =~ */Q}]
        set q_nets [get_nets -quiet -of_objects $q_pins]
        p3_puts $fh "  cell=$cell q_pins=$q_pins q_nets=$q_nets"
    }
}

proc p3_report_exact_bus {fh label base width} {
    set found 0
    set missing [list]
    for {set bit 0} {$bit < $width} {incr bit} {
        set name "${base}\[$bit\]"
        set nets [get_nets -quiet [list $name]]
        if {[llength $nets] == 1} {
            incr found
        } else {
            lappend missing $bit
        }
    }
    p3_puts $fh "$label exact_bus_found=${found}/${width} missing=$missing"
}

proc p3_report_matching_nets {fh label token} {
    set nets [lsort [get_nets -quiet -hierarchical -filter "NAME =~ *${token}*"]]
    p3_puts $fh "$label matching_nets=[llength $nets] token=$token"
    foreach net [lrange $nets 0 63] {
        p3_puts $fh "  net=$net"
    }
    if {[llength $nets] > 64} {
        p3_puts $fh "  truncated_after=64"
    }
}

set_param general.maxThreads 16
puts "Opening Build 79 pre-route checkpoint: $input_dcp"
open_checkpoint $input_dcp

file mkdir [file dirname $report_file]
set fh [open $report_file w]
p3_puts $fh "Build 80 retained trap-net inventory"
p3_puts $fh "input_dcp=$input_dcp"

set csr \
    {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6/csr_regfile_i}
set scoreboard \
    {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6/issue_stage_i/i_scoreboard}
set cva6 \
    {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6}

foreach reg_name {priv_lvl_q mepc_q mcause_q mtval_q mcounteren_q} {
    p3_report_cells $fh $reg_name "${csr}/${reg_name}_reg*"
}
p3_report_cells $fh ex_valid "${csr}/*ex_i*valid*"
p3_report_cells $fh csr_addr "${csr}/*csr_addr*"

p3_report_exact_bus $fh commit_pc \
    "${scoreboard}/commit_instr_id_commit\[0\]\[pc\]" 64
p3_report_exact_bus $fh commit_fu \
    "${scoreboard}/commit_instr_id_commit\[0\]\[fu\]" 4
p3_report_exact_bus $fh commit_op \
    "${scoreboard}/commit_instr_id_commit\[0\]\[op\]" 8
p3_report_exact_bus $fh commit_instruction \
    "${scoreboard}/commit_instr_id_commit\[0\]\[ex\]\[tval\]" 32
p3_report_exact_bus $fh ex_commit_cause \
    "${cva6}/ex_commit\[cause\]" 64
p3_report_exact_bus $fh ex_commit_tval \
    "${cva6}/ex_commit\[tval\]" 32
p3_report_exact_bus $fh csr_addr_ex_csr \
    "${cva6}/csr_addr_ex_csr" 12
p3_report_exact_bus $fh csr_op_commit_csr \
    "${cva6}/csr_op_commit_csr" 8

foreach name [list \
    "${cva6}/ex_commit\[valid\]" \
    "${cva6}/csr_exception_csr_commit\[valid\]" \
    "${csr}/privilege_violation"] {
    set nets [get_nets -quiet [list $name]]
    p3_puts $fh "exact_net name=$name matches=[llength $nets] nets=$nets"
}
p3_report_matching_nets $fh trap_to_priv_lvl trap_to_priv_lvl
p3_report_matching_nets $fh csr_exception csr_exception_csr_commit
p3_report_matching_nets $fh csr_addr csr_addr_ex_csr
p3_report_matching_nets $fh commit_ex_tval {commit_instr_id_commit[0][ex][tval]}

foreach name [list \
    "${scoreboard}/commit_instr_id_commit\[0\]\[valid\]" \
    "${scoreboard}/commit_ack\[0\]"] {
    set nets [get_nets -quiet [list $name]]
    p3_puts $fh "exact_net name=$name matches=[llength $nets] nets=$nets"
}

close $fh
close_design
puts "SUCCESS: Build 80 trap-net inventory written to $report_file"
