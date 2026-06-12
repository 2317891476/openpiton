# p3_ila_capture_build69_8x8_opensbi_diag.tcl -- Capture Build 69
# 8x8 OpenSBI diagnostic ILAs.

set env(P3_CAPTURE_PROJECT_NAME) "huaprop3_build69_8x8_opensbi_diag"
set env(P3_CAPTURE_PDI_BASENAME) "p3_top_build69_8x8_opensbi_diag"
set env(P3_CAPTURE_TAG) "build69"

source [file normalize "[file dirname [info script]]/p3_ila_capture_build52_sd_cd_mask.tcl"]
