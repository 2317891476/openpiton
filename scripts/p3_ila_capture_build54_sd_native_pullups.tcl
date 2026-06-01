# p3_ila_capture_build54_sd_native_pullups.tcl -- Capture Build 54 SD command debug ILAs.

set env(P3_CAPTURE_PROJECT_NAME) "huaprop3_build54_sd_native_pullups"
set env(P3_CAPTURE_PDI_BASENAME) "p3_top_build54_sd_native_pullups"
set env(P3_CAPTURE_TAG) "build54"

source [file normalize "[file dirname [info script]]/p3_ila_capture_build52_sd_cd_mask.tcl"]
