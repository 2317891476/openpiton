# p3_ila_capture_build92_udelay_caller.tcl -- Capture Build 92 ra/a0/sp.

set script_dir [file dirname [file normalize [info script]]]
set env(P3_UDELAY_CAPTURE_ID) {build92}
source [file join $script_dir p3_ila_capture_build91_udelay_values.tcl]
