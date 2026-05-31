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
| Single-core status | Linux boots, SD + UART working |
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

## Dev Log

Entries in `devlog/` are organized by month, newest first, append-only.

| Month | File |
|-------|------|
| 2026-06 | [2026-06](devlog/2026-06.md) |
| 2026-05 | [2026-05](devlog/2026-05.md) |

## Timeline

| Phase | Target | Milestone |
|-------|--------|-----------|
| P0 | Single core | Linux boots, Quicksilver runs on 1 core |
| P1 | 2x2 (4 cores) | Multi-core coherence validated |
| P2 | 4x4 (16 cores) | Speedup measurement baseline |
| P3 | 8x8 (64 cores) | Large-FPGA or multi-FPGA prototype |
| P4 | 32x32 (1024 cores) | Kilo-core target, final speedup measurement |
