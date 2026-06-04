# p3_build67_2x1_normal_spi_sd_boot.tcl -- Build 67 normal bootrom with
# the validated Build 66 P3 SPI-mode SD path scaled to a 2x1 Ariane mesh.
#
# Usage:
#   vivado -mode batch -source scripts/p3_build67_2x1_normal_spi_sd_boot.tcl -tclargs -jobs 1
#   vivado -mode batch -source scripts/p3_build67_2x1_normal_spi_sd_boot.tcl -tclargs -skip_create -skip_prepare -reuse_synth -jobs 1

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]

set env(PITON_X_TILES) 2
set env(PITON_Y_TILES) 1
set env(PITON_NUM_TILES) 2

set env(P3_BUILD52_PROJECT_NAME) "huaprop3_build67_2x1_baseline"
if {[info exists env(P3_BUILD67_WORK_DIR)] && $env(P3_BUILD67_WORK_DIR) ne ""} {
    set env(P3_BUILD52_WORK_DIR) $env(P3_BUILD67_WORK_DIR)
} else {
    set env(P3_BUILD52_WORK_DIR) [file normalize "${repo_dir}/p3b67_2x1"]
}
set env(P3_BUILD52_PDI_BASENAME) "p3_top_build67_2x1_normal_spi_sd_boot"
set env(P3_BUILD52_EXTRA_DEFINES) "P3_SPI_SD_BOOT P3_SPI_SD_BLOCK_DEBUG"
set env(P3_BUILD52_BOOTROM_REBUILD_SH) [file normalize "${script_dir}/p3_rebuild_build67_2x1_normal_spi_sd_boot.sh"]

source [file normalize "${script_dir}/p3_build52_sd_cd_mask.tcl"]
