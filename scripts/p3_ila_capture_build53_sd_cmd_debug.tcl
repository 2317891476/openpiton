# p3_ila_capture_build53_sd_cmd_debug.tcl -- Capture Build 53 SD command debug ILAs.

set env(P3_CAPTURE_PROJECT_NAME) "huaprop3_build53_sd_cmd_debug"
set env(P3_CAPTURE_PDI_BASENAME) "p3_top_build53_sd_cmd_debug"
set env(P3_CAPTURE_TAG) "build53"

source [file normalize "[file dirname [info script]]/p3_ila_capture_build52_sd_cd_mask.tcl"]
