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
| Current scaling candidate | 8x8 / 64-core OpenSBI/Linux reaches an interactive shell (`nproc=64`) but hangs intermittently under load (stop_machine at boot, XSBench in heavy compute). All coh_* sims PASS (RTL coherence functionally correct), so the failure is load-gated and not in a layer the fixed-latency sim models. **Leading hypothesis (2026-07-09): the L1.5 WMT write-guard `!stall_s3` was removed "for timing" (`l15_pipeline.v.pyv:3776`); under 64-core CPX/NoC3 congestion s3 stalls, and the WMT RAM's 2-cycle unbypassed write can race a same-index WMT read, dropping/misdirecting an L1 invalidation -> stale L1 line -> spin forever.** See devlog 2026-07-09. Next: reproduce on 2 cores first, then test re-adding the guard. |
| Prior scaling notes | Older `coh_ipi64.c` logs are stale leads (2026-07-01 three-pass sweep). The "stop_machine IPI deadlock / 58 harts miss MSIP" reading was falsified 2026-07-07 (SMP bringup already proves MSIP works for all 64). |
| Simulation | VCS when licensed; current local Ariane path uses Verilator 5.046 with `--hierarchical + -O0` for 8x8 |
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

- [周报 - 64核OpenSBI启动调试 (2026-06-16~22)](weekly_report_2026-06-16_to_2026-06-22.md) — 5个根因定位+修复，首次跑到OpenSBI banner
- [周报 - 64核Linux shell打通 + stop_machine IPI死锁定位 (2026-06-23~07-06)](weekly_report_2026-06-23_to_2026-07-06.md) — 64核nproc=64 shell；stop_machine IPI死锁(6/64响应)；纠正L1 coherence/timer/gcc误诊
- [Weekly Report - 64-core Scaling and Toolchain Debugging](weekly_report_64core_diagnostics.md)
- [Weekly Report - Single-core Boot and 2x1 Multicore Bring-up](weekly_report_multicore_bringup.md)
- [Weekly Report - SD Card Issue on P3](weekly_report_sd_issue.md)
- [Weekly Report - UART Issue on P3](weekly_report_uart_issue.md)

## Dev Log

Entries in `devlog/` are organized by month, newest first, append-only.

| Month | File |
|-------|------|
| 2026-07 | [2026-07](devlog/2026-07.md) |
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
