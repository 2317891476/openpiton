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
| Current scaling candidate | Build 68 8x8 / 64-core OpenSBI/Linux path created; wrapper, OpenSBI bundle bootrom mode, 64-hart DTB generator, and SD bundle packer are in place. Build 67 remains the latest programmed multicore hardware result and exposes the unresolved 2-hart SMP forward-progress risk. |
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
