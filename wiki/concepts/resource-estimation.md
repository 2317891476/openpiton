# Resource Estimation

LUT, BRAM, DSP, and FF budgets per tile count.

## Per-Tile Resource (Ariane, approximate)

| Resource | Per Tile | Notes |
|----------|----------|-------|
| LUT | ~30k | Core + L1.5 + L2 slice + NoC router |
| FF | ~20k | |
| BRAM | ~40 | Caches, TLB, directory |
| DSP | ~4 | Multiplier |

## FPGA Capacity Targets

| FPGA | LUT | BRAM | Max Tiles (est.) |
|------|-----|------|------------------|
| XC7A200T (AX7203) | 134k | 365 | 1-2 |
| **VP1902 (P3)** | **~900k+** | **TBD** | **~25-30** |
| XCVU9P | 1.18M | 2160 | ~16-25 |
| XCVU13P | 1.73M | 3780 | ~30-40 |

## Notes

- Chipset overhead is ~15-20k LUT (constant regardless of tile count)
- Estimates need validation with actual synthesis runs at each scale point

## Observed FPGA Results

| Date | Platform | Build | CLB LUTs | Registers | BRAM Tiles | URAM | DSP | Notes |
|------|----------|-------|----------|-----------|------------|------|-----|-------|
| 2026-06-13 | P3 / VP1902 | Build 69 8x8 OpenSBI diagnostic synthesis | 4,424,784 synth | 2,553,637 synth | 4,837 synth | 128 | 1,153 | Remote offline-Ubuntu Vivado 2024.2.2 `synth_1` completed with 0 errors and 0 critical warnings. `p3_top_utilization_synth.rpt` reports 52.30% CLB LUTs, 15.09% registers, 71.05% block RAM tiles, 5.82% URAM, and 16.80% DSP. The run then launched `impl_1`; route, PDI/LTX generation, and board validation are still pending. |
| 2026-06-12 | P3 / VP1902 | Build 68 8x8 OpenSBI/Linux setup | 4,424,744 synth / 4,394,422 placed | 2,553,630 synth / 2,557,136 placed | 4,836 synth / 4,844 placed | 128 | 1,153 | Remote offline-Ubuntu Vivado 2024.2.2 run completed main 64-core `synth_1` at 04:29 CST and `route_design` later completed successfully. Post-place utilization was 51.30% LUT-as-logic, 1.29% LUT-as-memory, 15.11% registers, 71.15% BRAM tiles, 5.82% URAM, and 16.80% DSP. The route status had 6,943,224 fully routed routable nets and 0 routing errors. PDI/LTX generation and board boot are still pending. |
| 2026-06-05 | P3 / VP1902 | Build 67 repo-local 2x1 normal SPI SD boot | 154,407 | 102,308 | 165 | 4 | 36 | First two-tile OpenPiton/Ariane expansion candidate rebuilt from repository-local `p3b67_2x1/source_snapshot/` with the Build 66 AXI16550 UART, SPI-mode SD boot path, DDR address translation, four small BD-owned ILAs, and consistent `PITON_X_TILES=2`, `PITON_Y_TILES=1`, `PITON_NUM_TILES=2` PyHP output. Route completed cleanly with 258,405 fully routed routable nets and 0 routing errors; timing met all user constraints with `WNS=16.312 ns`. Hardware validation is pending, so Build 66 remains the current validated baseline. |
| 2026-06-04 | P3 / VP1902 | Build 66 repo-local normal SPI SD boot | 87,430 | 62,786 | 89.5 | 2 | 18 | Canonical one OpenPiton/Ariane tile baseline rebuilt from repository-root `p3b66/` with BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, original Xilinx AXI16550 UART, explicit SD `IOBUF` pad boundary, normal SPI-mode SD boot path, DDR address translation, normal GPT/BBL/Linux bootrom, and four small BD-owned ILAs. Route completed cleanly with 151,579 fully routed routable nets and 0 routing errors; timing met all user constraints with `WNS=16.514 ns`. |
| 2026-06-03 | P3 / VP1902 | Build 64 normal SPI SD IOBUF history ILAs | 87,434 | 62,767 | 87.5 | 2 | 18 | One OpenPiton/Ariane tile plus BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, original Xilinx AXI16550 UART, explicit SD `IOBUF` pad boundary, normal OpenCores SPI SD path, and four small BD-owned ILAs for status, core/L15, SPI SD history, and DDR payloads. Route completed cleanly, PDI/LTX generated successfully, hardware ILA validation passed, and the normal SPI SD path reached card response and `INIT_DONE`. |
| 2026-05-31 | P3 / VP1902 | Build 49 SD-smoke ILAs | 89,543 | 64,544 | 87.5 | 2 | 19 | One OpenPiton/Ariane tile plus BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, original Xilinx AXI16550 UART, top-level DDR address translation, and four small BD-owned ILAs repurposed for SD-smoke status, core/L15, SD/UART payload, and DDR payloads. Route completed cleanly, PDI/LTX generated successfully, and hardware validation showed the first SD mapped read request was not accepted by the SD-side path. |
| 2026-05-31 | P3 / VP1902 | Build 48 normal boot progress ILAs | 89,681 | 64,477 | 88.5 | 2 | 19 | One OpenPiton/Ariane tile plus BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, original Xilinx AXI16550 UART, top-level DDR address translation, and four small BD-owned ILAs for status, core/L15, UART AXI, and DDR AXI payloads. Route completed cleanly and PDI/LTX generated successfully. |
| 2026-05-30 | P3 / VP1902 | Build 42-A no-stack ASM UART | 86,756 | 59,526 | 82 | 2 | 19 | One OpenPiton/Ariane tile plus BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, RTL SiFive/Chipyard `TLUART`, and two narrow BD-owned ILAs. Route completed cleanly, PDI/LTX generated successfully, hardware debug capture found both ILAs, but the no-stack UART smoke image still produced no serial output. |
| 2026-05-30 | P3 / VP1902 | Build 41 fetch/bootrom debug ILAs | 88,467 | 62,001 | 86 | 2 | 19 | One OpenPiton/Ariane tile plus BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, RTL SiFive/Chipyard `TLUART`, and three narrow BD-owned ILAs. Route completed cleanly, PDI/LTX generated successfully, and hardware debug capture found all three ILAs through `PMC_AXI_NOC0`. |
| 2026-05-29 | P3 / VP1902 | Build 40 SiFive TLUART debug variant | 32,702 | 25,526 | 14 | 2 | 1 | Separate `huaprop3_sifive_uart_debug` project with one OpenPiton/Ariane tile, BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, RTL SiFive/Chipyard `TLUART`, and two narrow BD-owned ILAs. The LTX contains the expected `PMC_AXI_NOC0` debug hub path plus `axis_ila_0`/`axis_ila_1`; PDI/LTX generated successfully. |
| 2026-05-29 | P3 / VP1902 | Build 39 SiFive TLUART variant | 31,081 | 23,308 | 14.5 | 2 | 1 | Separate `huaprop3_sifive_uart` project with one OpenPiton/Ariane tile, BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, one BD-owned ILA, and RTL SiFive/Chipyard `TLUART` behind the P3-only AXI4-Lite to TileLink-UL bridge. The Xilinx `axi_uart16550` IP is not present. PDI/LTX generated successfully. |
| 2026-05-29 | P3 / VP1902 | Build 37 live-narrow UART ILAs | 86,919 | 59,540 | 83.5 | 2 | 19 | One OpenPiton/Ariane tile plus BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, ns16550 UART, and two BD-owned ILAs. Build avoids the registered last-write payload and exports a live 56-bit UART/Core AXI-lite payload through the normal chipset status wrapper. Route completed cleanly; PDI writeout hit the PLM BSP path issue before recovery. |
| 2026-05-28 | P3 / VP1902 | Build 36 narrow UART last-write ILAs | 86,831 | 59,685 | 83.5 | 2 | 19 | One OpenPiton/Ariane tile plus BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, ns16550 UART, and two BD-owned ILAs. Build preserves the chipset status wrapper and exports the 56-bit UART last-write payload in `p3_dbg_uart_bus64_i[63:8]`; PDI/LTX generated successfully. |
| 2026-05-27 | P3 / VP1902 | Build 27 BD-owned RTL debug ILA | 85,876 | 59,778 | 102 | 2 | 19 | One OpenPiton/Ariane tile plus BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, ns16550 UART, and widened 7-probe BD `axis_ila_0`; PDI generated, but the expected LTX did not materialize and routed DCP reopen reports ILA-internal site routing overlap. |
| 2026-05-27 | P3 / VP1902 | Build 26 BD-owned minimal ILA | 85,386 | 57,534 | 84.5 | 2 | 19 | One OpenPiton/Ariane tile plus BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, ns16550 UART, and 2-probe BD `axis_ila_0`; routed successfully. |
