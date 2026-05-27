# p3_prepare_build31_runmgr_split_ila.tcl -- Patch the existing P3 BD for Build 31.
# Usage:
#   vivado -mode batch -source scripts/p3_prepare_build31_runmgr_split_ila.tcl
#
# Build 31 keeps the Build 30 split 128-bit probe payload. The implementation
# flow changes to Vivado's project run manager so BD/IP Integrator keeps the
# Chipscope debug-core metadata instead of stitching ILA OOC DCPs manually.

set script_dir [file dirname [info script]]
set p3_split_ila_build_number 31
set p3_split_ila_build_label "Build 31"
set p3_split_ila_input_pipe_stages 0
set p3_split_ila_data_depth 1024

source [file normalize "${script_dir}/p3_prepare_build28_split_ila.tcl"]
