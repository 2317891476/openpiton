# Create the OpenPiton P3 project variant for Build 52 AXI16550 SD card-detect mask debug
# debug with top-level CPU-physical to BD-low address translation.
# Usage:
#   vivado -mode batch -source scripts/p3_create_bd_build52_sd_cd_mask.tcl

set script_dir [file dirname [info script]]
if {![info exists P3_PROJECT_NAME] || $P3_PROJECT_NAME eq ""} {
    set P3_PROJECT_NAME "huaprop3_build52_sd_cd_mask"
}
set P3_ENABLE_SIFIVE_UART 0
set P3_ENABLE_SIFIVE_DEBUG_ILA 0
set P3_ENABLE_BUILD41_DEBUG_ILA 0
set P3_DDR_AXI_OFFSET 0x00000000
set P3_DDR_AXI_RANGE 2G
set P3_DISABLE_MEM_ZEROER 1
source "${script_dir}/p3_create_bd.tcl"
