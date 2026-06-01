# p3_build55_sd_clk_iob_reg.tcl -- Build 55 wrapper for SD clock IOB-register debug.
#
# Usage:
#   vivado -mode batch -source scripts/p3_build55_sd_clk_iob_reg.tcl -tclargs -jobs 1

set env(P3_BUILD52_PROJECT_NAME) "huaprop3_build55_sd_clk_iob_reg"
set env(P3_BUILD52_WORK_DIR) "D:/p3b55"
set env(P3_BUILD52_PDI_BASENAME) "p3_top_build55_sd_clk_iob_reg"
set env(P3_BUILD52_EXTRA_DEFINES) "P3_BD_SD_CMD_DEBUG_ILA P3_SD_CLK_IOB_REG"

source [file normalize "[file dirname [info script]]/p3_build52_sd_cd_mask.tcl"]
