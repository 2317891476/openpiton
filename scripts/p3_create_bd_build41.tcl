# Create the OpenPiton P3 project variant for Build 41 (Fetch Debug ILA).
# Usage:
#   vivado -mode batch -source scripts/p3_create_bd_build41.tcl

set script_dir [file dirname [info script]]
set P3_PROJECT_NAME "huaprop3_build41_debug"
set P3_ENABLE_SIFIVE_UART 1
set P3_ENABLE_SIFIVE_DEBUG_ILA 1
set P3_ENABLE_BUILD41_DEBUG_ILA 1
source "${script_dir}/p3_create_bd.tcl"
