# p3_prepare_build90_time_csr_rtl.tcl -- Sanitize the self-contained Build 90
# source snapshot, then run the normal Build 52 BD/ILA preparation.
#
# The live Ariane tree contains a user-owned dirty nested rv_plic edit unrelated
# to TIME.  Build 90 restores only the snapshot copy of plic_regmap.sv from the
# nested submodule HEAD; it never edits the user's live file.

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]
if {![info exists P3_PROJECT_NAME] || $P3_PROJECT_NAME eq "" ||
    ![info exists P3_PROJECT_DIR] || $P3_PROJECT_DIR eq ""} {
    error "Build 90 prepare requires P3_PROJECT_NAME and P3_PROJECT_DIR"
}

set project_dir [file normalize $P3_PROJECT_DIR]
set snapshot_dir "${project_dir}/source_snapshot"
set snapshot_plic \
    "${snapshot_dir}/piton/design/chip/tile/ariane/corev_apu/rv_plic/rtl/plic_regmap.sv"
set snapshot_csr \
    "${snapshot_dir}/piton/design/chip/tile/ariane/core/csr_regfile.sv"
set plic_repo \
    "${repo_dir}/piton/design/chip/tile/ariane/corev_apu/rv_plic"

foreach {path label} [list \
    $snapshot_dir {Build 90 source snapshot} \
    $snapshot_plic {Build 90 snapshot PLIC RTL} \
    $snapshot_csr {Build 90 snapshot CSR RTL} \
    "${plic_repo}/.git" {nested rv_plic repository metadata}] {
    if {![file exists $path]} {
        error "missing ${label}: $path"
    }
}

set plic_repo_wsl [p3_to_wsl_path $plic_repo]
set snapshot_plic_wsl [p3_to_wsl_path $snapshot_plic]
set clean_cmd \
    "set -e; git -C ${plic_repo_wsl} show HEAD:rtl/plic_regmap.sv > ${snapshot_plic_wsl}; test \"\$(git -C ${plic_repo_wsl} rev-parse HEAD:rtl/plic_regmap.sv)\" = \"\$(git hash-object ${snapshot_plic_wsl})\""
if {[catch {exec bash -lc $clean_cmd 2>@1} clean_log]} {
    puts $clean_log
    error "failed to restore clean rv_plic RTL inside the Build 90 snapshot"
}
puts "Build 90 snapshot PLIC restored from nested submodule HEAD: $snapshot_plic"

set fh [open $snapshot_csr r]
set csr_text [read $fh]
close $fh
foreach token [list \
    {`ifdef P3_TIME_CSR_DIV128} \
    {riscv::CSR_TIME:} \
    {csr_rdata = cycle_q >> 7}] {
    if {[string first $token $csr_text] < 0} {
        error "Build 90 snapshot CSR RTL is missing required token: $token"
    }
}
puts "Build 90 snapshot CSR_TIME RTL guard verified: $snapshot_csr"

source [file normalize "${script_dir}/p3_prepare_build52_sd_cd_mask_ila.tcl"]
