# p3_build71_8x8_uart_sd_source_closure.tcl -- Build 70 diagnostic hardware
# with a reproducible SPI-SD source closure.
#
# Usage:
#   vivado -mode batch \
#     -source scripts/p3_build71_8x8_uart_sd_source_closure.tcl \
#     -tclargs -jobs 32

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]

proc p3_build71_require_token {path token} {
    if {![file exists $path]} {
        puts "ERROR: Build 71 required source is missing: $path"
        exit 1
    }

    set fh [open $path r]
    set data [read $fh]
    close $fh
    if {[string first $token $data] < 0} {
        puts "ERROR: Build 71 required token '$token' is missing from $path"
        exit 1
    }
}

p3_build71_require_token \
    "${repo_dir}/piton/design/chipset/noc_sd_bridge/rtl/piton_spi_sd_top.v" \
    "module piton_spi_sd_top"
p3_build71_require_token \
    "${repo_dir}/piton/design/chipset/axi_sd_bridge/rtl/init_sd_p3.v" \
    "module init_sd_p3"
p3_build71_require_token \
    "${repo_dir}/piton/tools/src/proto/common/rtl_setup.tcl" \
    "noc_sd_bridge/rtl/piton_spi_sd_top.v"
p3_build71_require_token \
    "${repo_dir}/piton/tools/src/proto/common/rtl_setup.tcl" \
    "axi_sd_bridge/rtl/init_sd_p3.v"

set env(PITON_X_TILES) 8
set env(PITON_Y_TILES) 8
set env(PITON_NUM_TILES) 64

set env(P3_BUILD52_PROJECT_NAME) "huaprop3_build71_8x8_uart_sd_source_closure"
if {[info exists env(P3_BUILD71_WORK_DIR)] && $env(P3_BUILD71_WORK_DIR) ne ""} {
    set env(P3_BUILD52_WORK_DIR) $env(P3_BUILD71_WORK_DIR)
} else {
    set env(P3_BUILD52_WORK_DIR) \
        [file normalize "${repo_dir}/p3b71_8x8_uart_sd_source_closure"]
}
set env(P3_BUILD52_PDI_BASENAME) \
    "p3_top_build71_8x8_uart_sd_source_closure"
set env(P3_BUILD52_EXTRA_DEFINES) \
    "P3_SPI_SD_BOOT P3_SPI_SD_BLOCK_DEBUG P3_BD_UART_SD_DIAG_ILA P3_BD_UART_WR_NARROW_DEBUG_ILA"
set env(P3_BUILD52_BOOTROM_REBUILD_SH) \
    [file normalize "${script_dir}/p3_rebuild_build69_8x8_opensbi_diag.sh"]
set env(P3_SELF_CONTAINED_SOURCES) 1
if {![info exists env(P3_BUILD52_DEFAULT_JOBS)] ||
    $env(P3_BUILD52_DEFAULT_JOBS) eq ""} {
    set env(P3_BUILD52_DEFAULT_JOBS) 32
}

source [file normalize "${script_dir}/p3_build52_sd_cd_mask.tcl"]
