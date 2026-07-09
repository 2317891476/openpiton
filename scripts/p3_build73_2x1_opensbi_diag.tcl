# p3_build73_2x1_opensbi_diag.tcl -- 2-core P3 Pro / VP1902
# OpenSBI/Linux diagnostic candidate.
#
# Build 69 keeps the Build 68 2x1 hardware target and OpenSBI bundle layout,
# but uses a low-level diagnostic bootrom that proves UART, DDR, SD bundle
# reads, and hart release before entering OpenSBI.
#
# Usage:
#   vivado -mode batch -source scripts/p3_build73_2x1_opensbi_diag.tcl -tclargs -jobs 32
#   vivado -mode batch -source scripts/p3_build73_2x1_opensbi_diag.tcl -tclargs -skip_create -skip_prepare -reuse_synth -jobs 32

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]

set env(PITON_X_TILES) 2
set env(PITON_Y_TILES) 1
set env(PITON_NUM_TILES) 2

set env(P3_BUILD52_PROJECT_NAME) "huaprop3_build73_2x1_opensbi_diag"
if {[info exists env(P3_BUILD73_WORK_DIR)] && $env(P3_BUILD73_WORK_DIR) ne ""} {
    set env(P3_BUILD52_WORK_DIR) $env(P3_BUILD73_WORK_DIR)
} else {
    set env(P3_BUILD52_WORK_DIR) [file normalize "${repo_dir}/p3b73_2x1_diag"]
}
set env(P3_BUILD52_PDI_BASENAME) "p3_top_build73_2x1_opensbi_diag"
set env(P3_BUILD52_EXTRA_DEFINES) "P3_SPI_SD_BOOT P3_SPI_SD_BLOCK_DEBUG"
set env(P3_BUILD52_BOOTROM_REBUILD_SH) [file normalize "${script_dir}/p3_rebuild_build73_2x1_opensbi_diag.sh"]
set env(P3_SELF_CONTAINED_SOURCES) 1
if {![info exists env(P3_BUILD52_DEFAULT_JOBS)] || $env(P3_BUILD52_DEFAULT_JOBS) eq ""} {
    set env(P3_BUILD52_DEFAULT_JOBS) 32
}

source [file normalize "${script_dir}/p3_build52_sd_cd_mask.tcl"]
