# p3_ila_capture_build70_8x8_uart_sd_diag.tcl -- Capture Build 70 ILAs.

set env(P3_CAPTURE_PROJECT_NAME) "huaprop3_build70_8x8_uart_sd_diag"
set env(P3_CAPTURE_PDI_BASENAME) "p3_top_build70_8x8_uart_sd_diag"
set env(P3_CAPTURE_TAG) "build70"

source [file normalize "[file dirname [info script]]/p3_ila_capture_build52_sd_cd_mask.tcl"]
