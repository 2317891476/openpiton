# OpenPiton Manycore Quicksilver Project Wiki

## Project Goal

Run **Quicksilver** on a 1000-core OpenPiton instance and measure parallel speedup.

**Deployment path**: single-core validated → incremental scale-up → kilo-core target.

---

## Quick Reference Card

| Item | Value |
|------|-------|
| Current FPGA board | AX7203 (Artix-7 XC7A200T) |
| Migration target | HuaPro P3 (Versal VP1902) |
| Core type | Ariane/CVA6 (RISC-V 64-bit) |
| Single-core status | P3 Build 66 boots Linux shell; SD ext2 + XSBench launch verified |
| Current P3 baseline | Build 66 self-contained rerun target: `p3b66/source_snapshot/`; published PDI `huaprop3_build66_baseline/debug_build/p3_top_build66_normal_spi_sd_boot.pdi` |
| Current scaling candidate | Build 68 8x8 / 64-core OpenSBI/Linux completed VP1902 implementation, PDI/LTX generation, P3 Pro programming, debug-hub refresh, bundle-bootrom UART, and final source-rebuilt Linux 6.6/OpenSBI/64-hart SD image generation. Build 69 programmed successfully on 2026-06-13 with `DONE bit: HIGH` and four ILAs but emitted 0 UART bytes; its ILA capture proved reset release, core/NOC activity, successful DDR reads, then an SPI-SD transaction-manager read error. Build 70 retained direct UART/SD evidence but failed main synthesis because the new `piton_spi_sd_top` instance was present while its source was omitted from `git archive HEAD`. Build 71 is the active automatic successor; committed source closure, archive preflight, four ILA OOC runs, and self-contained 8x8/64-tile validation passed. Main synthesis completed with 0 errors and 52.27% CLB LUT / 71.06% BRAM utilization; `link_design`, `opt_design`, and `place_design` passed, with final peak local congestion 1.04 and cache BRAM `WEBWE[8]` replacement warnings retained as board-validation risks. |
| Simulation | `sims -sys=manycore -x_tiles=N -y_tiles=M -vcs_build` |
| FPGA synthesis | `protosyn -b <board> -d system --core=ariane --uart-dmw ddr` |
| Wiki sync rule | **R1** -- every code change must include wiki updates |

---

## Concepts

| Article | Topic |
|---------|-------|
| [Architecture Evolution](concepts/architecture-evolution.md) | Scaling path from 1-core to 1000-core |
| [Timing Closure](concepts/timing-closure.md) | Meeting timing at scale |
| [Routing Congestion](concepts/routing-congestion.md) | NoC and FPGA routing pressure |
| [Resource Estimation](concepts/resource-estimation.md) | LUT/BRAM/DSP budgets per tile count |
| [RAM Mapping Tradeoff](concepts/ram-mapping-tradeoff.md) | BRAM vs URAM vs distributed RAM |
| [SLR Layout](concepts/slr-layout.md) | Multi-SLR floorplanning for large FPGAs |
| [Simulation](concepts/simulation.md) | VCS/Verilator simulation strategies |
| [RTL Coding Rules](concepts/rtl-coding-rules.md) | Verilog/SV conventions for manycore |
| [Vivado Tooling](concepts/vivado-tooling.md) | Synthesis/impl scripts and tips |
| [ASIC Extrapolation](concepts/asic-extrapolation.md) | Projecting FPGA results to ASIC |
| [RTL-ASIC Port](concepts/rtl-asic-port.md) | Preparing RTL for tape-out |
| [P3 Migration Guide](concepts/p3-migration-guide.md) | Porting OpenPiton+Ariane from AX7203 to HuaPro P3 (VP1902) |
 
## Weekly Reports

- [Weekly Report - Single-core Boot and 2x1 Multicore Bring-up](weekly_report_multicore_bringup.md)
- [Weekly Report - SD Card Issue on P3](weekly_report_sd_issue.md)
- [Weekly Report - UART Issue on P3](weekly_report_uart_issue.md)

## Dev Log

Entries in `devlog/` are organized by month, newest first, append-only.

| Month | File |
|-------|------|
| 2026-06 | [2026-06](devlog/2026-06.md) |
| 2026-05 | [2026-05](devlog/2026-05.md) |

## Timeline

| Phase | Target | Milestone |
|-------|--------|-----------|
| P0 | Single core | Linux shell, SD ext2 mount, and XSBench smoke launch verified on P3 |
| P1 | 2x2 (4 cores) | Multi-core coherence validated |
| P2 | 4x4 (16 cores) | Speedup measurement baseline |
| P3 | 8x8 (64 cores) | P3 Pro / VP1902 board boots Linux with 64 CPUs online |
| P4 | 32x32 (1024 cores) | Kilo-core target, final speedup measurement |
