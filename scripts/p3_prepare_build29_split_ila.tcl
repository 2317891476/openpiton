# p3_prepare_build29_split_ila.tcl -- Patch the existing P3 BD for Build 29.
# Usage:
#   vivado -mode batch -source scripts/p3_prepare_build29_split_ila.tcl
#
# Build 29 keeps the Build 28 split 128-bit probe set, but uses the more
# conservative no-input-pipe ILA setting that matched the verified Build 26
# runtime debug path.

set script_dir [file dirname [info script]]
set p3_split_ila_build_number 29
set p3_split_ila_build_label "Build 29"
set p3_split_ila_input_pipe_stages 0
set p3_split_ila_data_depth 1024

source [file normalize "${script_dir}/p3_prepare_build28_split_ila.tcl"]
