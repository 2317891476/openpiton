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
| Single-core status | **P3 Build 66 unchanged PDI + OpenSBI v1.8 + Linux 5.1.0-rc7 now reaches an interactive BusyBox shell, mounts the SD ext2 second partition, and completes XSBench with 1,000 particles x 1 lookup.** The separate OpenSBI/Linux 6.6 image passes SD/GPT/copy and reaches OpenSBI v1.8 with one hart and the corrected 234375 Hz timer, but its Linux shell and exact synchronous trap cause remain unproven. |
| **A/B result (2026-07-27)** | **Same OpenSBI v1.8 + same DTB + same Build 66 PDI: Linux 5.1.0-rc7 boots fully to `Run /init as init process` (banner, memory, timer, SMP, devtmpfs, networking, USB, RPC/NFS, piton_sd, kernel init complete), while Linux 6.6 cannot even print a banner.** This isolates the blocker to Linux 6.6 specifically (early S-mode boot code, kernel config, or its OpenSBI interaction), not the firmware or hardware contract. |
| Current P3 baseline | Build 66 self-contained rerun target: `p3b66/source_snapshot/`; published PDI `huaprop3_build66_baseline/debug_build/p3_top_build66_normal_spi_sd_boot.pdi` |
| Current scaling candidate | **2-core (2x1) bring-up in progress.** Leaving Ariane L1 D-cache enabled clears the CSR 0x701 OpenSBI gate, the timer reports the corrected 234375 Hz, and the `mem=1G` control crosses the stale-aperture page-table stop into later Linux init. The corrected 2 GiB aperture PDI still lacks formal board closure. The single-hart control now points to an active repeating OpenSBI trap/CSR-emulation path; the next boundary is commit PC plus mcause/mepc/mtval and decoded CSR, not another generic L1.5 or commit-stall probe. Linux SMP completion and a current-stack shell remain unproven. **See [HANDOFF_codex_2core_opensbi.md](HANDOFF_codex_2core_opensbi.md) for the full handoff.** |
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
| [P3 Multicore NoC Topology](concepts/p3-multicore-noc-topology.md) | 2x1 and 8x8 mesh structure, chipset gateway, and interrupt sidebands |
 
## Weekly Reports

- [周报 - 64核OpenSBI启动调试 (2026-06-16~22)](weekly_report_2026-06-16_to_2026-06-22.md) — 5个根因定位+修复，首次跑到OpenSBI banner
- [周报 - 64核Linux shell打通 + stop_machine IPI死锁定位 (2026-06-23~07-06)](weekly_report_2026-06-23_to_2026-07-06.md) — 64核nproc=64 shell；stop_machine IPI死锁(6/64响应)；纠正L1 coherence/timer/gcc误诊
- [周报 - 2核Build 73打通至Linux早期 + CSR/定时器修复 (2026-07-07~07-13)](weekly_report_2026-07-07_to_2026-07-13.md) — 2核链路通过OpenSBI进入Linux早期；关闭CSR 0x701和mtimer注册问题；Linux页表阶段待A/B
- [周报 - 单核OpenSBI/Linux TIME CSR修复与ILA证据链纠偏 (2026-07-14~07-20)](weekly_report_2026-07-14_to_2026-07-20.md) — 单核复现后期问题；TIME CSR RTL闭环；adapter实现敏感性已证实但具体根因待定位
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
| P0 | Single core | OpenSBI v1.8 + Linux 5.1 interactive shell, SD ext2 mount, and XSBench 1,000 x 1 completion verified on unchanged Build 66 PDI; Linux 6.6 remains a separate early-boot blocker |
| P1 | 2x2 (4 cores) | Multi-core coherence validated |
| P2 | 4x4 (16 cores) | Speedup measurement baseline |
| P3 | 8x8 (64 cores) | P3 Pro / VP1902 board boots Linux with 64 CPUs online |
| P4 | 32x32 (1024 cores) | Kilo-core target, final speedup measurement |
