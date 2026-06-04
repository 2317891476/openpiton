# HuaPro P3 Build 66 Baseline

Build 66 is the current validated P3 OpenPiton+Ariane baseline.

- Hardware path: original AXI16550 UART, SPI-mode SD, DDR address translation, four compact BD-owned ILAs.
- Vivado wrapper: `scripts/p3_build66_normal_spi_sd_boot.tcl`.
- Canonical Vivado work directory for future rebuilds: `p3b66/` in the repository root.
- Full validated Vivado snapshot: `p3b66_validated_snapshot/` in the repository root.
- Published local artifacts: `huaprop3_build66_baseline/debug_build/p3_top_build66_normal_spi_sd_boot.pdi` and `.ltx`.
- Validated runtime: Linux shell on `/dev/ttyUSB0` at `115200 8N1`, SD ext2 mount, and XSBench smoke launch.

The `debug_build/` directory contains generated PDI/LTX/CSV files and is intentionally ignored by git. The validated local copies are kept in this workspace for board programming.

Both `p3b66/` and `p3b66_validated_snapshot/` are local Vivado workspaces and are intentionally ignored by git. Keep the snapshot until a fresh `p3b66/` rebuild and hardware boot test pass.

Historical debug projects were moved to:

- `/home/illya/p3_cleanup_archive/2026-06-04-build66-baseline/repo_dirs/`
- `/mnt/d/p3_cleanup_archive/2026-06-04-build66-baseline/workspaces/`

Keep `huaprop3onecore/` as the reference Chipyard/Rocket project for board-level UART, SD, and ILA comparisons.
