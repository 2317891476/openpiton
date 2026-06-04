# p3_ila_capture_build66_normal_spi_sd_boot.tcl -- Capture Build 66 normal
# SPI-SD boot ILAs.

set env(P3_CAPTURE_PROJECT_NAME) "huaprop3_build66_baseline"
set env(P3_CAPTURE_PDI_BASENAME) "p3_top_build66_normal_spi_sd_boot"
set env(P3_CAPTURE_TAG) "build66"

source [file normalize "[file dirname [info script]]/p3_ila_capture_build52_sd_cd_mask.tcl"]
