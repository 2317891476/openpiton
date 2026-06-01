# p3_build53_sd_cmd_debug.tcl -- Build 53 wrapper for SD command-layer debug.
#
# Usage:
#   vivado -mode batch -source scripts/p3_build53_sd_cmd_debug.tcl -tclargs -jobs 1

set env(P3_BUILD52_PROJECT_NAME) "huaprop3_build53_sd_cmd_debug"
set env(P3_BUILD52_WORK_DIR) "D:/p3b53"
set env(P3_BUILD52_PDI_BASENAME) "p3_top_build53_sd_cmd_debug"
set env(P3_BUILD52_EXTRA_DEFINES) "P3_BD_SD_CMD_DEBUG_ILA"

source [file normalize "[file dirname [info script]]/p3_build52_sd_cd_mask.tcl"]
