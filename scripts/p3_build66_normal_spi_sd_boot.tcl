# p3_build66_normal_spi_sd_boot.tcl -- Build 66 normal bootrom with the
# validated P3 SPI-mode SD path.
#
# Usage:
#   vivado -mode batch -source scripts/p3_build66_normal_spi_sd_boot.tcl -tclargs -jobs 1
#   vivado -mode batch -source scripts/p3_build66_normal_spi_sd_boot.tcl -tclargs -skip_create -skip_prepare -reuse_synth -jobs 1
#
# Build 66 keeps the original AXI16550 UART path and the Build 65 SPI-mode SD
# block-read hardware, but replaces the Build 52 no-stack SD-probe bootrom with
# the normal C bootrom so the board can load GPT/BBL/Linux from the SD card.

set script_dir [file dirname [info script]]
set env(P3_BUILD52_PROJECT_NAME) "huaprop3_build66_normal_spi_sd_boot"
set env(P3_BUILD52_WORK_DIR) "D:/p3b66"
set env(P3_BUILD52_PDI_BASENAME) "p3_top_build66_normal_spi_sd_boot"
set env(P3_BUILD52_EXTRA_DEFINES) "P3_SPI_SD_BOOT P3_SPI_SD_BLOCK_DEBUG"
set env(P3_BUILD52_BOOTROM_REBUILD_SH) [file normalize "${script_dir}/p3_rebuild_build66_normal_spi_sd_boot.sh"]

source [file normalize "${script_dir}/p3_build52_sd_cd_mask.tcl"]
