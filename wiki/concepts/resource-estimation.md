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
| 2026-05-30 | P3 / VP1902 | Build 42-A no-stack ASM UART | 86,756 | 59,526 | 82 | 2 | 19 | One OpenPiton/Ariane tile plus BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, RTL SiFive/Chipyard `TLUART`, and two narrow BD-owned ILAs. Route completed cleanly, PDI/LTX generated successfully, hardware debug capture found both ILAs, but the no-stack UART smoke image still produced no serial output. |
| 2026-05-30 | P3 / VP1902 | Build 41 fetch/bootrom debug ILAs | 88,467 | 62,001 | 86 | 2 | 19 | One OpenPiton/Ariane tile plus BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, RTL SiFive/Chipyard `TLUART`, and three narrow BD-owned ILAs. Route completed cleanly, PDI/LTX generated successfully, and hardware debug capture found all three ILAs through `PMC_AXI_NOC0`. |
| 2026-05-29 | P3 / VP1902 | Build 40 SiFive TLUART debug variant | 32,702 | 25,526 | 14 | 2 | 1 | Separate `huaprop3_sifive_uart_debug` project with one OpenPiton/Ariane tile, BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, RTL SiFive/Chipyard `TLUART`, and two narrow BD-owned ILAs. The LTX contains the expected `PMC_AXI_NOC0` debug hub path plus `axis_ila_0`/`axis_ila_1`; PDI/LTX generated successfully. |
| 2026-05-29 | P3 / VP1902 | Build 39 SiFive TLUART variant | 31,081 | 23,308 | 14.5 | 2 | 1 | Separate `huaprop3_sifive_uart` project with one OpenPiton/Ariane tile, BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, one BD-owned ILA, and RTL SiFive/Chipyard `TLUART` behind the P3-only AXI4-Lite to TileLink-UL bridge. The Xilinx `axi_uart16550` IP is not present. PDI/LTX generated successfully. |
| 2026-05-29 | P3 / VP1902 | Build 37 live-narrow UART ILAs | 86,919 | 59,540 | 83.5 | 2 | 19 | One OpenPiton/Ariane tile plus BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, ns16550 UART, and two BD-owned ILAs. Build avoids the registered last-write payload and exports a live 56-bit UART/Core AXI-lite payload through the normal chipset status wrapper. Route completed cleanly; PDI writeout hit the PLM BSP path issue before recovery. |
| 2026-05-28 | P3 / VP1902 | Build 36 narrow UART last-write ILAs | 86,831 | 59,685 | 83.5 | 2 | 19 | One OpenPiton/Ariane tile plus BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, ns16550 UART, and two BD-owned ILAs. Build preserves the chipset status wrapper and exports the 56-bit UART last-write payload in `p3_dbg_uart_bus64_i[63:8]`; PDI/LTX generated successfully. |
| 2026-05-27 | P3 / VP1902 | Build 27 BD-owned RTL debug ILA | 85,876 | 59,778 | 102 | 2 | 19 | One OpenPiton/Ariane tile plus BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, ns16550 UART, and widened 7-probe BD `axis_ila_0`; PDI generated, but the expected LTX did not materialize and routed DCP reopen reports ILA-internal site routing overlap. |
| 2026-05-27 | P3 / VP1902 | Build 26 BD-owned minimal ILA | 85,386 | 57,534 | 84.5 | 2 | 19 | One OpenPiton/Ariane tile plus BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, ns16550 UART, and 2-probe BD `axis_ila_0`; routed successfully. |
