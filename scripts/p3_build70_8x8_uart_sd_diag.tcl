# p3_build70_8x8_uart_sd_diag.tcl -- 64-core P3 Pro UART-first diagnostic.
#
# Build 70 keeps the Build 69 OpenSBI diagnostic bootrom, but replaces the
# broad chipset payload with direct AXI16550 write/TX history plus compact SD
# block progress. This distinguishes a missing bootrom UART store from an AXI
# bridge, UART IP, TX pin, or later SD failure.
#
# Usage:
#   vivado -mode batch -source scripts/p3_build70_8x8_uart_sd_diag.tcl -tclargs -jobs 32

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]

set env(PITON_X_TILES) 8
set env(PITON_Y_TILES) 8
set env(PITON_NUM_TILES) 64

set env(P3_BUILD52_PROJECT_NAME) "huaprop3_build70_8x8_uart_sd_diag"
if {[info exists env(P3_BUILD70_WORK_DIR)] && $env(P3_BUILD70_WORK_DIR) ne ""} {
    set env(P3_BUILD52_WORK_DIR) $env(P3_BUILD70_WORK_DIR)
} else {
    set env(P3_BUILD52_WORK_DIR) [file normalize "${repo_dir}/p3b70_8x8_uart_sd_diag"]
}
set env(P3_BUILD52_PDI_BASENAME) "p3_top_build70_8x8_uart_sd_diag"
set env(P3_BUILD52_EXTRA_DEFINES) \
    "P3_SPI_SD_BOOT P3_SPI_SD_BLOCK_DEBUG P3_BD_UART_SD_DIAG_ILA P3_BD_UART_WR_NARROW_DEBUG_ILA"
set env(P3_BUILD52_BOOTROM_REBUILD_SH) \
    [file normalize "${script_dir}/p3_rebuild_build69_8x8_opensbi_diag.sh"]
set env(P3_SELF_CONTAINED_SOURCES) 1
if {![info exists env(P3_BUILD52_DEFAULT_JOBS)] || $env(P3_BUILD52_DEFAULT_JOBS) eq ""} {
    set env(P3_BUILD52_DEFAULT_JOBS) 32
}

source [file normalize "${script_dir}/p3_build52_sd_cd_mask.tcl"]
