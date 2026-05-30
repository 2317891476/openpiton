# Create the OpenPiton P3 project variant for Build 42-A no-stack UART ASM.
# Usage:
#   vivado -mode batch -source scripts/p3_create_bd_build42a_asm_uart.tcl

set script_dir [file dirname [info script]]
set P3_PROJECT_NAME "huaprop3_build42a_asm_uart"
set P3_ENABLE_SIFIVE_UART 1
set P3_ENABLE_SIFIVE_DEBUG_ILA 1
source "${script_dir}/p3_create_bd.tcl"
