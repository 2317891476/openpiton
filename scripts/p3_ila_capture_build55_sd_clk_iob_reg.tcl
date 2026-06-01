# p3_ila_capture_build55_sd_clk_iob_reg.tcl -- Capture Build 55 SD command debug ILAs.

set env(P3_CAPTURE_PROJECT_NAME) "huaprop3_build55_sd_clk_iob_reg"
set env(P3_CAPTURE_PDI_BASENAME) "p3_top_build55_sd_clk_iob_reg"
set env(P3_CAPTURE_TAG) "build55"

source [file normalize "[file dirname [info script]]/p3_ila_capture_build52_sd_cd_mask.tcl"]
