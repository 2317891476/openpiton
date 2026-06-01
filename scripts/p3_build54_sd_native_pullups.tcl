# p3_build54_sd_native_pullups.tcl -- Build 54 wrapper for native SD pull-up debug.
#
# Usage:
#   vivado -mode batch -source scripts/p3_build54_sd_native_pullups.tcl -tclargs -jobs 1

set env(P3_BUILD52_PROJECT_NAME) "huaprop3_build54_sd_native_pullups"
set env(P3_BUILD52_WORK_DIR) "D:/p3b54"
set env(P3_BUILD52_PDI_BASENAME) "p3_top_build54_sd_native_pullups"
set env(P3_BUILD52_EXTRA_DEFINES) "P3_BD_SD_CMD_DEBUG_ILA"

source [file normalize "[file dirname [info script]]/p3_build52_sd_cd_mask.tcl"]
