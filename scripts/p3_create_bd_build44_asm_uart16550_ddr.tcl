# Create the OpenPiton P3 project variant for Build 44 no-stack AXI16550 DDR probe.
# Usage:
#   vivado -mode batch -source scripts/p3_create_bd_build44_asm_uart16550_ddr.tcl

set script_dir [file dirname [info script]]
set P3_PROJECT_NAME "huaprop3_build44_asm_uart16550_ddr"
set P3_ENABLE_SIFIVE_UART 0
set P3_ENABLE_SIFIVE_DEBUG_ILA 0
set P3_ENABLE_BUILD41_DEBUG_ILA 0
source "${script_dir}/p3_create_bd.tcl"
