# p3_build100_adapter_keep.tcl -- Rebuild the validated one-hart P3 design
# with architectural TIME and KEEP/mark_debug on the adapter handshake.
#
# This build tests the hypothesis that Vivado synthesis absorbs the
# dcache_data_ack_o / dcache_data_full combinational path, breaking the
# STORE_WAIT exit feedback loop.  Adding (* keep = "true" *) forces
# synthesis to preserve these signals as real nets.
#
# Usage:
#   P3_BUILD100_WORK_DIR=D:/p3b100_adapter_keep \
#     vivado -mode batch -source scripts/p3_build100_adapter_keep.tcl \
#       -tclargs -jobs 16

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]

set env(PITON_X_TILES) 1
set env(PITON_Y_TILES) 1
set env(PITON_NUM_TILES) 1

set env(P3_BUILD52_PROJECT_NAME) "huaprop3_build100_adapter_keep"
if {[info exists env(P3_BUILD100_WORK_DIR)] && $env(P3_BUILD100_WORK_DIR) ne ""} {
    set env(P3_BUILD52_WORK_DIR) $env(P3_BUILD100_WORK_DIR)
} else {
    set env(P3_BUILD52_WORK_DIR) \
        [file normalize "${repo_dir}/p3b100_adapter_keep"]
}
set env(P3_BUILD52_PDI_BASENAME) "p3_top_build100_adapter_keep"
set env(P3_BUILD52_EXTRA_DEFINES) \
    "P3_SPI_SD_BOOT P3_SPI_SD_BLOCK_DEBUG P3_TIME_CSR_DIV128"
set env(P3_BUILD52_PREPARE_TCL) \
    [file normalize "${script_dir}/p3_prepare_build90_time_csr_rtl.tcl"]
set env(P3_BUILD52_POST_SYNTH_TCL) \
    [file normalize "${script_dir}/p3_build90_insert_debug.tcl"]
set env(P3_BUILD52_REQUIRED_LTX_TOKENS) \
    "u_ila_build90 commit_instr_id_commit csr_addr_ex_csr cycle_q"
set env(P3_BUILD52_BOOTROM_REBUILD_SH) \
    [file normalize "${script_dir}/p3_rebuild_build66_normal_spi_sd_boot.sh"]
set env(P3_SELF_CONTAINED_SOURCES) 1
if {![info exists env(P3_BUILD52_DEFAULT_JOBS)] ||
    $env(P3_BUILD52_DEFAULT_JOBS) eq ""} {
    set env(P3_BUILD52_DEFAULT_JOBS) 16
}

source [file normalize "${script_dir}/p3_build52_sd_cd_mask.tcl"]
