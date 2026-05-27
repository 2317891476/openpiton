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
| 2026-05-27 | P3 / VP1902 | Build 27 BD-owned RTL debug ILA | 85,876 | 59,778 | 102 | 2 | 19 | One OpenPiton/Ariane tile plus BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, ns16550 UART, and widened 7-probe BD `axis_ila_0`; PDI generated, but the expected LTX did not materialize and routed DCP reopen reports ILA-internal site routing overlap. |
| 2026-05-27 | P3 / VP1902 | Build 26 BD-owned minimal ILA | 85,386 | 57,534 | 84.5 | 2 | 19 | One OpenPiton/Ariane tile plus BD AXI NoC, DDRMC, Clock Wizard, proc_sys_reset, ns16550 UART, and 2-probe BD `axis_ila_0`; routed successfully. |
