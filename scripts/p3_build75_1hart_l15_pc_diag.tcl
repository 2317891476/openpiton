# p3_build75_1hart_l15_pc_diag.tcl -- Build 66-compatible single-hart
# OpenSBI/Linux diagnostic with PC and L1.5 stall-cause probes.
#
# Usage:
#   vivado -mode batch -source scripts/p3_build75_1hart_l15_pc_diag.tcl \
#     -tclargs -jobs 16

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]

set env(PITON_X_TILES) 1
set env(PITON_Y_TILES) 1
set env(PITON_NUM_TILES) 1

set env(P3_BUILD52_PROJECT_NAME) "huaprop3_build75_1hart_l15_pc_diag"
if {[info exists env(P3_BUILD75_WORK_DIR)] && $env(P3_BUILD75_WORK_DIR) ne ""} {
    set env(P3_BUILD52_WORK_DIR) $env(P3_BUILD75_WORK_DIR)
} else {
    set env(P3_BUILD52_WORK_DIR) [file normalize "${repo_dir}/p3b75_1hart_diag"]
}
set env(P3_BUILD52_PDI_BASENAME) "p3_top_build75_1hart_l15_pc_diag"
set env(P3_BUILD52_EXTRA_DEFINES) \
    "P3_SPI_SD_BOOT P3_SPI_SD_BLOCK_DEBUG P3_BUILD75_PC_L15_DEBUG"
set env(P3_BUILD52_EXTRA_PYHP_TEMPLATES) \
    "piton/design/chip/tile/l15/rtl/l15_pipeline.v.pyv"
set env(P3_BUILD52_POST_SYNTH_TCL) \
    [file normalize "${script_dir}/p3_build75_insert_debug.tcl"]
set env(P3_BUILD52_REQUIRED_LTX_TOKENS) \
    "u_ila_build75 p3_build75_noack_trigger p3_build75_l15_req_bus p3_build75_l15_stall_bus commit_instr_id_commit"
set env(P3_BUILD52_BOOTROM_REBUILD_SH) \
    [file normalize "${script_dir}/p3_rebuild_build66_normal_spi_sd_boot.sh"]
set env(P3_SELF_CONTAINED_SOURCES) 1
if {![info exists env(P3_BUILD52_DEFAULT_JOBS)] || $env(P3_BUILD52_DEFAULT_JOBS) eq ""} {
    set env(P3_BUILD52_DEFAULT_JOBS) 16
}

source [file normalize "${script_dir}/p3_build52_sd_cd_mask.tcl"]
