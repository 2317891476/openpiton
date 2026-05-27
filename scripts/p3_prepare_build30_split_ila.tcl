# p3_prepare_build30_split_ila.tcl -- Patch the existing P3 BD for Build 30.
# Usage:
#   vivado -mode batch -source scripts/p3_prepare_build30_split_ila.tcl
#
# Build 30 keeps the Build 29 two-ILA, 128-bit probe payload. The change is in
# the direct implementation flow: debug child IP is stitched before
# implementation so route-time LTX generation sees a resolved AXI debug hub.

set script_dir [file dirname [info script]]
set p3_split_ila_build_number 30
set p3_split_ila_build_label "Build 30"
set p3_split_ila_input_pipe_stages 0
set p3_split_ila_data_depth 1024

source [file normalize "${script_dir}/p3_prepare_build28_split_ila.tcl"]
