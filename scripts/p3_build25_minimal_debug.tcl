# p3_build25_minimal_debug.tcl -- Build 25 minimal P3 debug-hub recovery image.
# Usage:
#   vivado -mode batch -source scripts/p3_build25_minimal_debug.tcl
#   vivado -mode batch -source scripts/p3_build25_minimal_debug.tcl -tclargs -reuse_synth

set script_dir [file dirname [info script]]
set direct_flow [file normalize "${script_dir}/p3_build24_direct_flow.tcl"]

set direct_args [list -build25_minimal_debug]
foreach arg $argv {
    switch -- $arg {
        -reuse_synth {
            lappend direct_args -reuse_synth
        }
        default {
            puts "ERROR: unknown argument: $arg"
            puts "Usage: vivado -mode batch -source scripts/p3_build25_minimal_debug.tcl ?-tclargs -reuse_synth?"
            exit 1
        }
    }
}

set argv $direct_args
source $direct_flow
