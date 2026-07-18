# p3_build92_udelay_caller.tcl -- Diagnostic-only udelay caller context.

set script_dir [file dirname [file normalize [info script]]]
set env(P3_UDELAY_OUTPUT_STEM) {p3_top_build92_udelay_caller}
set env(P3_UDELAY_GPR_REGS) {1 10 2}
set env(P3_UDELAY_GPR_NAMES) {ra a0_delay sp}
set env(P3_UDELAY_TAG_PREFIX) {p3_build92}
source [file join $script_dir p3_build91_udelay_values.tcl]
