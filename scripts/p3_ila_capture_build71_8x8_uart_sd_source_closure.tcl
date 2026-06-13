# p3_ila_capture_build71_8x8_uart_sd_source_closure.tcl -- Capture Build 71.

set env(P3_CAPTURE_PROJECT_NAME) \
    "huaprop3_build71_8x8_uart_sd_source_closure"
set env(P3_CAPTURE_PDI_BASENAME) \
    "p3_top_build71_8x8_uart_sd_source_closure"
set env(P3_CAPTURE_TAG) "build71"

source [file normalize \
    "[file dirname [info script]]/p3_ila_capture_build52_sd_cd_mask.tcl"]
