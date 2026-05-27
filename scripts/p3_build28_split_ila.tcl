# p3_build28_split_ila.tcl -- Build 28 using split compact BD-owned RTL ILAs.
# Usage:
#   vivado -mode batch -source scripts/p3_build28_split_ila.tcl
#   vivado -mode batch -source scripts/p3_build28_split_ila.tcl -tclargs -reuse_synth

set script_dir [file dirname [info script]]
set prepare_tcl [file normalize "${script_dir}/p3_prepare_build28_split_ila.tcl"]
set direct_flow [file normalize "${script_dir}/p3_build24_direct_flow.tcl"]

set direct_args [list -build28_split_ila]
set do_prepare 1
foreach arg $argv {
    switch -- $arg {
        -reuse_synth {
            lappend direct_args -reuse_synth
            set do_prepare 0
        }
        -skip_prepare {
            set do_prepare 0
        }
        default {
            puts "ERROR: unknown argument: $arg"
            puts "Usage: vivado -mode batch -source scripts/p3_build28_split_ila.tcl ?-tclargs -reuse_synth|-skip_prepare?"
            exit 1
        }
    }
}

if {$do_prepare} {
    source $prepare_tcl
} else {
    puts "Skipping Build 28 BD preparation step."
}

set argv $direct_args
source $direct_flow
