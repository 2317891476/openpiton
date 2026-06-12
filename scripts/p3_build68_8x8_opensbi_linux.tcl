# p3_build68_8x8_opensbi_linux.tcl -- 64-core P3 Pro / VP1902
# OpenPiton+Ariane candidate using the OpenSBI/Linux SD bundle bootrom.
#
# Usage:
#   vivado -mode batch -source scripts/p3_build68_8x8_opensbi_linux.tcl -tclargs -jobs 16
#   vivado -mode batch -source scripts/p3_build68_8x8_opensbi_linux.tcl -tclargs -skip_create -skip_prepare -reuse_synth -jobs 16

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]

set env(PITON_X_TILES) 8
set env(PITON_Y_TILES) 8
set env(PITON_NUM_TILES) 64

set env(P3_BUILD52_PROJECT_NAME) "huaprop3_build68_8x8_opensbi_linux"
if {[info exists env(P3_BUILD68_WORK_DIR)] && $env(P3_BUILD68_WORK_DIR) ne ""} {
    set env(P3_BUILD52_WORK_DIR) $env(P3_BUILD68_WORK_DIR)
} else {
    set env(P3_BUILD52_WORK_DIR) [file normalize "${repo_dir}/p3b68_8x8"]
}
set env(P3_BUILD52_PDI_BASENAME) "p3_top_build68_8x8_opensbi_linux"
set env(P3_BUILD52_EXTRA_DEFINES) "P3_SPI_SD_BOOT P3_SPI_SD_BLOCK_DEBUG"
set env(P3_BUILD52_BOOTROM_REBUILD_SH) [file normalize "${script_dir}/p3_rebuild_build68_8x8_opensbi_linux.sh"]
set env(P3_SELF_CONTAINED_SOURCES) 1
if {![info exists env(P3_BUILD52_DEFAULT_JOBS)] || $env(P3_BUILD52_DEFAULT_JOBS) eq ""} {
    set env(P3_BUILD52_DEFAULT_JOBS) 16
}

source [file normalize "${script_dir}/p3_build52_sd_cd_mask.tcl"]
