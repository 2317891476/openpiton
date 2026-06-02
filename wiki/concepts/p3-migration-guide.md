# P3 Migration Guide: OpenPiton+Ariane from AX7203 to HuaPro P3

## 0. Executive Summary

This document describes porting the single-core OpenPiton+Ariane (CVA6 RISC-V) SoC from AX7203 (Artix-7 XC7A200T) to HuaPro P3 (Versal VP1902). The P3's massive fabric (~900k+ LUT, multi-SLR) is the target platform for scaling OpenPiton toward the 1000-core Quicksilver benchmark goal. Scope: single-core Linux boot first (P0 on P3), then scale.

A reference project (`huaprop3onecore/`) already runs Chipyard+Rocket on the P3. It provides proven pin assignments, clock/DDR4/SD configurations, and a Vivado 2024.2 Block Design template. The migration reuses this hardware-level knowledge while replacing the Chipyard SoC with OpenPiton+Ariane.

**Build flow decision**: Start with Vivado Block Design (wrap OpenPiton RTL as a module, DDRMC/NoC/PMC via IP Integrator). After single-core boots, evaluate migrating to protosyn for multi-core scaling.

---

## 1. Hardware Comparison

| Aspect | AX7203 | P3 (VP1902) |
|--------|--------|-------------|
| **FPGA device** | XC7A200T-2FBG484I | xcvp1902-vsva6865-1MP-e-S |
| **Architecture** | 7-series | Versal Prime (multi-SLR, has PS/PMC) |
| **LUT** | ~134k | ~900k+ |
| **BRAM** | 365 (36Kb) | Much larger (exact TBD from Vivado) |
| **System clock** | 200 MHz diff, DIFF_SSTL15, R4/T4 | 100 MHz diff, LVDS15, CE6/CF6 (free-run) |
| **DDR type** | DDR3, MIG 7-series, 32-bit, 1 GB | DDR4, Versal DDRMC + AXI NoC, 72-bit (w/ECC), SODIMM |
| **DDR ref clock** | Derived from sys clock via MMCM | Separate LVDS15 ref, CP83/CP82 |
| **Clock generation** | 7-series MMCM (`clk_mmcm`) | Versal Clock Wizard (`clk_wizard_0`) |
| **UART** | CP2102 on-board, P20/N15, LVCMOS33 | FT232HQ on daughter card, CM59/CN59 (PHC3), LVCMOS15 |
| **SD card** | On-board MicroSD, LVCMOS33, no extra signals | SD-SPIFLASH daughter card via PHC3, LVCMOS15, needs VSD_EN/SD_SEL/SD_RESET# |
| **SD mode** | SPI over SD bus (ODDR for clock) | SPI over SD bus (no ODDR on Versal) |
| **Reset** | T6, active-LOW, LVCMOS15, PULLUP | A6, active-HIGH, LVCMOS15 |
| **LEDs** | W5 + B13/C13/D14/D15 (5 total) | CF60/CF59 on daughter card (2 total) |
| **I/O voltage** | Mixed 3.3V (UART/SD/LEDs) / 1.5V (DDR/reset) | PHC all LVCMOS15 (1.5V) |
| **PS subsystem** | None | PS/PMC requires initialization (ps_wizard) |
| **Build flow** | `protosyn` (flat Verilog, command-line) | Vivado Block Design (IP Integrator) |
| **Vivado version** | 2024.2 | 2024.2 |

---

## 2. Layer-by-Layer Migration Analysis

### Layer 1: FPGA Hardware

#### 1.1 Pin Constraints (XDC)

**Entire XDC must be rewritten from scratch.** Cannot reuse any AX7203 pin assignments.

The SD-SPIFLASH daughter card is plugged into **PHC3 (Bank 705)**, matching the P3 reference project. All PHC I/O uses LVCMOS15.

**PHC3 pin mapping** (from `p3_io.md` section 3.2):

| Signal | PHC Logic Pin | FPGA PACKAGE_PIN | Direction |
|--------|---------------|------------------|-----------|
| SD_CLK | A0 | CW60 | Output |
| VSD_EN | A1 | CY60 | Output |
| SD_CMD | A2 | DB61 | Bidirectional |
| SD_CD# | A3 | DC61 | Input |
| SD_D0 | A4 | DC60 | Bidirectional |
| SD_D1 | A5 | DC59 | Bidirectional |
| SD_D2 | A6 | CY58 | Bidirectional |
| SD_D3 | A7 | DA58 | Bidirectional |
| SD_WP | A9 | DA61 | Output |
| SD_RESET# | A10 | DA60 | Output |
| SD_SEL | A11 | DA59 | Output |
| UART_TXD | C8 | CM59 | Output (FPGA → PC) |
| UART_RXD | C9 | CN59 | Input (PC → FPGA) |
| LED0 | C10 | CF60 | Output |
| LED1 | C11 | CF59 | Output |

**P3 reference XDC comparison** (from `huaprop3onecore/.../shell.xdc`):

The reference project uses slightly different PHC pins than the p3_io.md PHC3 table for SD. It routes SD signals through different PHC logical pins (using PMOD positions), with actual FPGA pins: `sdio_spi_clk=CV57`, `sdio_spi_cs=DB57`, `sdio_spi_dat_0=DC56`. This is because the reference uses a **different PHC slot or different daughter card wiring**. For OpenPiton migration, we should follow `p3_io.md` section 3.2 (PHC3) pin assignments unless the actual daughter card is wired to match the reference project.

**Decision needed at implementation time**: verify which physical pin mapping the actual daughter card + PHC3 slot uses. Compare against reference XDC.

**System clock**:
```
# 100 MHz LVDS15 free-run clock
set_property PACKAGE_PIN CE6 [get_ports {sys_clk_p}]
set_property PACKAGE_PIN CF6 [get_ports {sys_clk_n}]
set_property IOSTANDARD LVDS15 [get_ports {sys_clk_p}]
set_property IOSTANDARD LVDS15 [get_ports {sys_clk_n}]
```

**Reset**:
```
# Active-HIGH reset button
set_property PACKAGE_PIN A6 [get_ports {reset}]
set_property IOSTANDARD LVCMOS15 [get_ports {reset}]
```

**DDR4**: Extensive pin assignments from reference XDC (72-bit DQ, DQS, DM, address, control). Use the P3 reference XDC DDR4 section verbatim -- these are fixed by the SODIMM socket physical wiring.

#### 1.2 Clock Generation

Replace 7-series MMCM with Versal Clock Wizard IP.

| Parameter | AX7203 (MMCM) | P3 (Clock Wizard) |
|-----------|----------------|---------------------|
| Input | 200 MHz DIFF_SSTL15 | 100 MHz LVDS15 |
| chipset_clk | 30 MHz | 30 MHz (keep same for minimal software changes) |
| sd_sys_clk | 30 MHz | 30 MHz |
| mc_sys_clk | 200 MHz (for MIG) | Not needed (DDRMC has its own clock) |
| core_ref_clk | 250 MHz (for SPARC) | Not needed for Ariane |

The Clock Wizard IP core must be created in Vivado for Versal. The existing `piton/design/chipset/xilinx/a7203x/ip_cores/clk_mmcm/` cannot be reused (7-series MMCM XCI files are incompatible with Versal).

#### 1.3 DDR Memory Controller

**This is the largest single change.**

| Aspect | AX7203 | P3 |
|--------|--------|-----|
| Controller | MIG 7-series (mig_7series_0) | Versal DDRMC (hard block) |
| Interface | Native MIG → noc_mig_bridge | AXI4 → noc_axi4_bridge |
| Data width | 32-bit | 72-bit (64 data + 8 ECC) |
| Topology | Direct instantiation in chipset_impl | Block Design: DDRMC ↔ AXI NoC ↔ AXI4 master |

The P3 reference project uses `axi_noc_0` (AXI Network-on-Chip IP) to connect the Rocket core's AXI master to the DDRMC. For OpenPiton, the path is:

```
OpenPiton NoC → noc_axi4_bridge → AXI4 master port → [BD boundary] → axi_noc → DDRMC → DDR4 SODIMM
```

OpenPiton already has `noc_axi4_bridge` (`piton/design/chipset/noc_axi4_bridge/rtl/`). The key is to use `PITONSYS_AXI4_MEM` define instead of the MIG path (`PITONSYS_DDR4`/`PITONSYS_NO_MC`). This bridge presents a standard AXI4 interface that can connect to the Versal AXI NoC in the Block Design.

Bring-up note from Builds 44-46: do not assume the P3 BD always sees DDR addresses after subtracting `0x80000000`. The Build 44 top-level ILA observed the BD-facing AXI address `0x84000000` for a bootrom load/store to CPU physical `0x84000000`, while the BD DDR segment was at offset `0x00000000`. Build 45 tried to move the BD DDR segment to `0x80000000`, but Vivado rejected that because the Versal AXI NoC DDR slave only exposes a valid `0x00000000 [2G]` aperture in this BD. Build 46 therefore keeps the BD aperture at `0x0` and adds a gated `P3_AXI_DDR_ADDR_TRANSLATE` path in `p3_top.v` to fold CPU physical DDR addresses into the legal BD low window before `S_AXI_MEM`.

Build 46 hardware validation confirmed that this translation is functional: the no-stack DDR probe still issued a physical `0x84xxxxxx` read, but the BD-facing snapshot retained `0x04000000`, and the AXI R channel returned with OKAY response. Treat the address translation as part of the P3 OpenPiton memory integration baseline; later boot failures should first be checked at the C bootrom, SD, cache, or payload-loading layer before reopening DDR PHY/IP bring-up.

Build 47 carries the same address-translation baseline into the normal C bootrom while returning to the original AXI16550 UART path. Its two small BD-owned ILAs observe DDR sticky flags, a compact DDR transaction snapshot, and UART sticky activity so the next failure point can be separated between C stack/DDR responses, UART logging, SD probing, and payload loading without changing the DDRMC/NoC BD aperture.

Build 47 hardware validation confirmed the corrected baseline: a serial capture window that spans the full PDI programming interval and post-DONE runtime prints the normal OpenPiton+Ariane bootrom banner through the original AXI16550 path. A shorter 90-second capture had ended before the PDI reprogramming completed and should not be used as evidence of UART failure. After Build 47, the active debug target is no longer physical UART or UART IP bring-up; it is the later normal bootrom path where banner output stops before the full platform info and before clear SD/GPT progress.

Build 48 keeps the Build 47 hardware/software baseline and only adds finer debug visibility for that post-banner stop. It uses the original `PITON_UART16550` path, keeps `P3_AXI_DDR_ADDR_TRANSLATE`, keeps `PITONSYS_MEM_ZEROER` disabled, and adds `P3_BD_BOOT_PROGRESS_ILA` to expose three compact 64-bit debug buses plus sticky status. The BD owns four small ILAs: status/sticky, core/L15 payload, UART AXI read/write payload, and DDR AXI payload. This should identify whether the stop is core/L15 progress, UART register sequencing, DDR stack/write response, or later SD/GPT traffic without changing the proven UART path.

Build 48 implementation completed successfully from `D:/p3b48`: route status reported 154,734 fully routed routable nets and 0 routing errors, timing met all user constraints with `WNS=8.965 ns` and `WHS=0.019 ns`, and `p3_top_build48_boot_progress.pdi/.ltx` were published. The hardware validation sequence should start serial capture before PDI programming, then collect all four ILA CSVs so the post-banner stop can be separated between core/L15 progress, UART AXI state, and DDR AXI responses.

Build 48 hardware validation printed the normal banner through AXI16550, then produced no additional serial output in a later 600-second capture. Two ILA captures taken about 18 minutes apart were identical. The last L1.5 address was `0xfff101057c`, which maps to `sd_copy+0xcc` (`bne a1,a4,10570`) in the bootrom block-copy loop. UART-side state showed a final THR write of `0x29` after an LSR read of `0x20`, and DDR-side state showed an OKAY read at translated low address `0x03fffd00` with no DDR write-channel sticky bits. This moves the fault from reset/fetch/UART bring-up to early SD/GPT block-copy progress and cache/DDR write visibility. Build 49 should expose live boot progress or PC plus SD-mapped read and DDR write-channel activity, so a stopped `sd_copy` loop can be separated from a missing SD return, a cached store/writeback issue, or a UART transmitter state issue after the banner.

Build 49 starts with a narrower software experiment before another full normal-boot image: `BOOTROM_MODE=sd_smoke` keeps `startup.S` and the original AXI16550 UART driver, but replaces the normal GPT/payload-copy C path with direct reads from the SD mapped window. It prints LBA0, LBA1/GPT header fields, partition-entry fields, and the first qword of the first partition only after range checks. A valid `EFI PART` signature and sane partition fields would shift the next fault search toward BBL/payload contents and copy/cache/writeback behavior; a bad or missing signature keeps the focus on SD card image preparation or the SD mapped-read path.

Build 49 hardware validation narrowed the stop before any SD-sector data returns. The SD-smoke bootrom printed `B49 SD SMOKE AXI16550`, `mode: direct SD mapped reads, no payload copy`, and stopped after `read lba0[0]`. The four BD-owned ILAs remained accessible through `PMC_AXI_NOC0`; decode showed `top_status=0xff03`, `core_seen=0x7fff`, `sd_seen=0x7f2b`, and `ddr_seen=0xcf01`. The important SD bits were `buf_sd_noc2_valid=1` with `sd_buf_noc2_ready=0`, `sd_req_fire=0`, `sd_buf_noc3_valid=0`, and `sd_resp_fire=0`. DDR read traffic still completed with OKAY response. This does not support "SD card lacks a standard BBL" as the current first failure: the CPU is blocked before the SD path accepts the first mapped LBA0 read, so the next debug target is SD bridge ready/backpressure/reset/clock/address decode rather than GPT/BBL image contents.

Build 50 is a stricter control for the same SD acceptance point. It creates a new `huaprop3_build50_sd_uart_minimal` Vivado variant and leaves the current OpenPiton SD controller, pins, reset, clock, and AXI16550 UART path unchanged. The bootrom mode `asm_uart16550_sdprobe` avoids C, stack setup, DDR, GPT parsing, and payload copying: it prints a fixed AXI16550 banner, performs direct loads from the SD mapped window at `0xF000000000`, and only continues printing if those loads return. Matching Build 49's `sd_buf_noc2_ready=0` in this image would isolate the failure to the native SD bridge/controller acceptance path independent of C bootrom software.

Build 50 hardware validation matched the Build 49 SD-ready hang while removing the C bootrom, stack, DDR, GPT, and BBL variables. The image implemented cleanly from `D:/p3b50` and programmed successfully (`DONE bit: HIGH`). Hardware Manager refreshed all four BD-owned ILAs through `PMC_AXI_NOC0`/debug hub `0x3ffc0000000`. The decoder reported `top_status=0xff02`, `core_seen=0x7fff`, `sd_seen=0x442b`, and `ddr_seen=0x8001`. The SD-side sticky bits were again `buf_sd_noc2_valid=1`, `sd_buf_noc2_ready=0`, `sd_req_fire=0`, `sd_buf_noc3_valid=0`, and `sd_resp_fire=0`. The last L1.5 fetch address was `0xfff1010154`, which maps to the no-stack bootrom around the post-SD-load UART poll; because the SD request never handshakes, treat this as front-end fetch progress around a stalled SD load, not as evidence that the load completed. The next debug target is the native SD `init_done`/reset/backpressure path and its physical pin/clock assumptions.

Build 51 instruments that native SD initialization path without changing the board wiring or software stimulus. The new `P3_BD_SD_INIT_ILA` path exports `piton_sd_init` state/counter plus `piton_sd_top` current/sticky status: `sd_cd`, aggregated SD reset, `init_done`, Wishbone `stb/we/ack/addr/data`, SD command/data interrupt bits, sampled SD clock toggle, and CMD/DAT input/output-enable state. It reuses the same four small BD-owned ILAs and the same no-stack AXI16550 SD-probe bootrom as Build 50. A current `sd_cd=1` with SD reset asserted would prove the card-detect path is holding the controller reset; `sd_cd=0` with `init_done=0` and a stuck `piton_sd_init` state would move the focus to SD clock/CMD/DAT physical response or the Wishbone-facing OpenCores controller.

Build 51 hardware validation proved the first case. The image built cleanly from `D:/p3b51`, programmed with `DONE bit: HIGH`, and refreshed all four ILAs through the known-good `PMC_AXI_NOC0` debug path. The SD-init decode showed raw `sd_cd=1`, aggregated SD reset asserted, `init_done=0`, no SD clock toggle, no CMD/DAT output-enable activity, and no Wishbone ack. Since `piton_sd_top` currently computes internal reset as `sys_rst | sd_cd`, a high card-detect input prevents the native SD init FSM from leaving reset. Build 52 should keep the same SD controller, pins, clocks, UART, and no-stack SD-probe bootrom, but mask `sd_cd` out of the internal reset path while continuing to probe the raw `sd_cd` level. If SD clock/CMD/Wishbone activity starts, the root cause is the P3 card-detect polarity/connection path; if it still does not, the next fault is inside the SD clock/reset or Wishbone controller initialization.

Build 52 implements that narrow card-detect control. The RTL adds `P3_SD_IGNORE_CARD_DETECT_RESET` around the `piton_sd_top` internal reset calculation so raw `sd_cd` remains visible in the ILA, but the SD controller/init reset ignores it for this experiment. The Vivado runner is `scripts/p3_build52_sd_cd_mask.tcl`, defaults to `D:/p3b52`, and publishes `p3_top_build52_sd_cd_mask.pdi/.ltx`. All other Build 51 variables are intentionally held constant: original AXI16550 UART, no-stack SD-probe bootrom, native SD controller, SD pinout, SD clocks, DDR address translation, and the same compact four-ILA layout.

Builds 53 through 55 narrowed the SD failure to the external command-response boundary. Build 53 exposed the command-layer state and showed `ST_ACMD41_CMD55_WAIT_INT`, command index 55, command master `EXECUTE`, serial host `READ_WAIT`, `cmd_oe_o=0`, and `sd_cmd_dat_i=1`: the controller releases CMD and waits for the card to pull CMD low for the response start bit. Build 54 added native idle-line pull-ups, and Build 55 registered the SD clock output near the I/O boundary; neither changed the live state. Build 56 therefore stops spending full OpenPiton builds on single physical hypotheses and creates a standalone dual-pin, dual-protocol SD probe. The same bitstream tests the reference SPI pin map and the `p3_io.md` PHC3 native pin map, each in SPI mode and native CMD mode. Because Vivado rejected `vio:3.0` for the VP1902 part during the first Build 56 attempt, the implementation uses an RTL auto-run sequencer instead of VIO: after reset it runs all four combinations in order and stores sticky per-case pass/fail/timeout summaries for ILA capture.

The first Build 56 hardware capture already resolved one major ambiguity: `ref_spi` passed and observed a card response, while `ref_native` timed out. The same capture exposed a probe-local bug before the remaining two cases completed: the SPI response timeout counter could underflow on a no-response path and hold the sequencer in `SPI_RESP_HIGH`. The Build 56 revision fixes only that timeout bookkeeping and the ILA debug-bus width declarations, then reruns the same standalone experiment; if `phc3_native` remains silent after the fixed four-case run, the next full OpenPiton direction should be a reference-pin SPI-mode SD path rather than more native-controller physical tweaks.

Build 57 implements that direction without changing the UART decision from Builds 43 and 49-55: the board UART stays on the original AXI16550 path. Only the SD hardware behind the existing OpenPiton SD NoC/MMIO window changes. `P3_SPI_SD_BOOT` selects `piton_spi_sd_top`, which preserves the `piton_sd_top` NoC-facing and top-level SD ports but internally connects `noc_axilite_bridge`, `axi_sd_bridge`, and `spi_master`. The P3 pin use follows the Build 56 passing reference-SPI case: `sd_clk_out` is SPI SCK, `sd_cmd` is MOSI, `sd_dat[0]` is MISO, and `sd_dat[3]` is CS#. Build 57 also keeps the Build 52-derived compact ILA layout and repacks the SD debug bus around NoC, AXI-Lite, Wishbone, and SPI-level progress so one hardware capture can distinguish missing NoC acceptance, missing SPI initialization, card-response errors, and successful SD block-cache reads.

The SPI backend needs two P3-specific protocol fixes before it is a valid full-boot experiment. First, the original OpenCores initializer uses the legacy CMD0/CMD1 flow, which is not sufficient for modern SDHC cards; `HUAPROP3_BOARD` therefore selects `init_sd_p3`, which sends CMD0, CMD8, and repeated CMD55/ACMD41 with the HCS bit set. Second, once a card is in SDHC mode, CMD17/CMD24 use a 512-byte block number rather than a byte address. The P3 transaction manager now writes `req_addr >> 9` into the SPI address registers while leaving the old byte-address behavior untouched for non-P3 builds.

Build 57's first hardware capture proved that the replacement SD path is being reached from OpenPiton: NoC request, Wishbone access, init transaction selection, and SPI clock toggle all appeared in the ILA. It did not prove card communication, because MISO never sampled low and the SPI controller reported error `0x01` after the init attempt. Build 58 therefore keeps the same reference SPI pin map and AXI16550 UART decision, but adds a 100 ms `init_sd_p3` power-wait before idle clocks/CMD0 and repacks the ILA bus to expose the initializer's state, command byte, response byte, timeout, ready/request, CS, and error fields. This lets the next capture distinguish an early CMD0 no-response condition from a later CMD8 or ACMD41 protocol failure without another wide-probe build.

Build 58 completed on hardware and confirmed the early no-response case: the initializer stayed in `CMD0_WAIT` with `cmd=0x40`, `resp=0xff`, `miso_low_seen=0`, and SPI error `0x01`. The card power/reset control pins were not the immediate issue (`sd_vsd_en=1`, `sd_sel=0`, `sd_resetn=1`), and the debug hub, NoC request, Wishbone write, init transaction, and SPI clock all worked. Build 59 therefore makes the smallest protocol-level change that matches the standalone Build 56 passing probe: the OpenCores SPI wire engine now drives MOSI high during reset and idle states instead of holding the SD CMD line low before the first queued `0xff` idle byte. If Build 59 still cannot see MISO go low during CMD0, the remaining difference is likely the OpenCores byte-FIFO command/response timing rather than the board pin map.

#### 1.4 ODDR Primitive

**ODDR (7-series) and ODDRE1 (UltraScale+) do not exist on Versal.**

In `chipset.v` (line 1659-1678), the SD clock is generated using ODDR/ODDRE1:
```verilog
`ifdef VCU118_BOARD
    ODDRE1 sd_clk_oddr (...);  // UltraScale+
`else
    ODDR sd_clk_oddr (...);    // 7-series
`endif
```

For Versal, replace with a behavioral output register:
```verilog
`ifdef HUAPROP3_BOARD
    reg sd_clk_out_reg;
    always @(posedge sd_clk_out_internal or posedge rst)
        if (rst) sd_clk_out_reg <= 1'b0;
        else     sd_clk_out_reg <= ~sd_clk_out_reg;
    assign sd_clk_out = sd_clk_out_reg;
`elsif VCU118_BOARD
    ...
```

Or use Versal's `OBUFDS`/output register inference. The behavioral approach is simplest and works at SD SPI clock speeds (<=25 MHz).

### Layer 2: NoC / IO Crossbar Device Map

**`devices_ariane.xml` can be copied from AX7203 with minimal changes.**

The address map is logical, not tied to physical FPGA pins. Peripheral addresses stay the same:

| Port | Base Address | Length | Change? |
|------|-------------|--------|---------|
| chip | - | - | No |
| mem | `0x80000000` | `0x40000000` | **Update length if DDR > 1 GB** |
| iob | `0x9f00000000` | `0x10` | No |
| sd | `0xf000000000` | `0xff0300000` | No |
| uart | `0xfff0c2c000` | `0xd4000` | No |
| ariane_debug | `0xfff1000000` | `0x1000` | No |
| ariane_bootrom | `0xfff1010000` | `0x10000` | No |
| ariane_clint | `0xfff1020000` | `0xc0000` | No |
| ariane_plic | `0xfff1100000` | `0x4000000` | No |

If the DDR4 SODIMM on P3 is larger than 1 GB, update the `mem` port length accordingly. All other addresses remain unchanged.

### Layer 3: Chipset RTL Configuration

#### 3.1 New Board Define

Add `HUAPROP3_BOARD` to the ifdef chain in `chipset.v`. This board needs:
- `PITON_FPGA_RST_ACT_HIGH` -- reset is active-HIGH on P3
- `PITONSYS_SPI` -- SD card support
- `PITONSYS_UART` -- UART support
- `PITONSYS_UART_BOOT` -- boot mode control
- `PITON_FPGA_SD_BOOT` -- SD boot path
- `PITONSYS_AXI4_MEM` -- AXI4 memory path (instead of direct MIG)

#### 3.2 Reset Polarity

`chipset.v` line 775-779:
```verilog
`ifdef PITON_FPGA_RST_ACT_HIGH
    rst_n_rect = ~rst_n;
`else
    rst_n_rect = rst_n;
`endif
```

P3 needs `PITON_FPGA_RST_ACT_HIGH` defined. AX7203 uses active-LOW (no inversion).

#### 3.3 uart_boot_en

`chipset.v` line 818-824 (AX7203 pattern):
```verilog
`elsif A7203X_BOARD
    `ifdef PITON_FPGA_SD_BOOT
    assign uart_boot_en = 1'b0;
    `else
    assign uart_boot_en = 1'b1;
    `endif
```

P3 needs the same pattern: `uart_boot_en = 1'b0` for SD boot (no DIP switches on daughter card).

#### 3.4 SD Control Signals (New)

P3 daughter card requires three additional signals not present on AX7203:

| Signal | Purpose | Required Value |
|--------|---------|----------------|
| `vsd_en` | SD power/level enable | `1'b1` (enable after reset) |
| `sd_sel` | Voltage select (1=1.5V, 0=3.3V) | `1'b0` (3.3V for SD init) |
| `sd_reset_n` | SD card reset (active-low) | `1'b1` (deasserted during normal op) |

These must be added as top-level ports in `chipset.v` and `chipset_impl.v.pyv`, gated behind `HUAPROP3_BOARD`.

#### 3.5 Memory Controller Path

`chipset_impl.v.pyv` line 29-30:
```verilog
`ifdef PITONSYS_AXI4_MEM
`include "noc_axi4_bridge_define.vh"
```

Line 90-101 shows the ifdef structure:
```verilog
`ifndef PITONSYS_NO_MC
    `ifdef PITONSYS_DDR4
        // DDR4 MIG path
    `else
        // DDR3 MIG path
    `endif
`endif
```

For P3: use `PITONSYS_AXI4_MEM` define. This instantiates `noc_axi4_bridge` which exposes a standard AXI4 interface. That AXI4 interface becomes a port of the OpenPiton wrapper module, connecting to the Versal AXI NoC in the Block Design.

Files involved:
- `piton/design/chipset/noc_axi4_bridge/rtl/noc_axi4_bridge.v` -- main bridge
- `piton/design/chipset/noc_axi4_bridge/rtl/noc_axi4_bridge_read.v` -- read channel
- `piton/design/chipset/noc_axi4_bridge/rtl/noc_axi4_bridge_write.v` -- write channel

### Layer 4: Bootrom (ZSBL)

Source: `piton/design/chipset/rv64_platform/bootrom/linux/`

| Parameter | AX7203 | P3 |
|-----------|--------|-----|
| `UART_FREQ` | 30000000 (30 MHz) | 30000000 (keep same if chipset_clk = 30 MHz) |
| `MAX_HARTS` | 1 | 1 (single core for P0) |
| Toolchain | `riscv64-unknown-elf-gcc` 7.2.0 | Same (no change) |
| DTB | `a7203x.dtb` embedded | **New `huaprop3.dtb`** embedded |

**If chipset_clk stays at 30 MHz, the only bootrom change is the embedded DTB.**

Rebuild:
```bash
cd piton/design/chipset/rv64_platform/bootrom/linux/
# Copy new DTB
cp $PITON_ROOT/build/huaprop3/huaprop3.dtb rv64_platform.dtb
make clean && make
# Output: bootrom_linux.sv
```

### Layer 5: Device Tree (DTS/DTB)

New file: `build/huaprop3/huaprop3.dts`

Changes from AX7203 DTS (`build/a7203x/a7203x.dts`):

| Field | AX7203 | P3 | Change needed? |
|-------|--------|-----|----------------|
| clock-frequency | 30000000 | 30000000 | No (if chipset_clk = 30 MHz) |
| timebase-frequency | 234375 | 234375 | No (30M / 128) |
| Memory `reg` | `<0x0 0x80000000 0x0 0x40000000>` | Possibly larger | **If DDR > 1 GB** |
| PLIC `reg` | `0xfff1100000` | `0xfff1100000` | No |
| UART `reg` | `0xfff0c2c000` | `0xfff0c2c000` | No |
| CLINT `reg` | `0xfff1020000` | `0xfff1020000` | No |
| bootargs earlycon | `uart8250,mmio,0xfff0c2c000` | Same | No |

**Address consistency rule** (from CLAUDE.md): all addresses must match across:
1. `devices_ariane.xml` (hardware routing)
2. RTL instantiation (hardware implementation)
3. DTS `reg` fields (software description)
4. Bootrom hardcoded addresses
5. BBL hardcoded UART address

### Layer 6: BBL (Berkeley Boot Loader)

- Rebuild with new DTB (`huaprop3.dtb` → `embedded_dtb.h`)
- Build flags unchanged: `-fno-stack-protector -U_FORTIFY_SOURCE`
- Toolchain unchanged: `riscv64-linux-gnu-gcc`
- No fundamental code changes expected

### Layer 7: Linux Kernel & Rootfs

- Should boot if layers 1-6 are correct
- `bootargs` in DTS `/chosen` node stays the same (UART address unchanged)
- `piton_sd` driver works if SD hardware interface is correctly adapted
- Static-linked test programs work without change

---

## 3. Critical Failure Points (Ranked by Severity)

### 3.1 ODDR Primitive Does Not Exist on Versal (SYNTHESIS FAILURE)

**Impact**: Synthesis will fail immediately.

`chipset.v:1669` instantiates `ODDR` for SD clock. Versal has neither `ODDR` (7-series) nor `ODDRE1` (UltraScale+). Must add a `HUAPROP3_BOARD` ifdef with a behavioral replacement.

### 3.2 DDR Controller Is Completely Different (ARCHITECTURE CHANGE)

**Impact**: No memory = nothing works.

MIG 7-series cannot be instantiated on Versal. The entire memory path must use `noc_axi4_bridge` → AXI4 → Versal AXI NoC → DDRMC. This is the deepest change and has no direct OpenPiton precedent on Versal. The P3 reference project's AXI NoC + DDRMC configuration is the starting point.

### 3.3 SD CMD/DATA Are Bidirectional on P3 Daughter Card (SILENT FAILURE)

**Impact**: SD reads may return garbage if tristate not handled.

`piton_sd_top.v` already declares `sd_cmd` as `inout` and `sd_dat[3:0]` as `inout`, so synthesis should infer IOBUF. However, must verify that:
1. The top-level wrapper correctly propagates `inout` ports (not splitting into separate in/out)
2. Versal synthesis correctly infers I/O buffers for the PHC bank

### 3.4 VSD_EN / SD_SEL / SD_RESET# Not in AX7203 Design (POWER FAILURE)

**Impact**: SD card won't power up.

These three signals don't exist in the AX7203 constraints or chipset RTL. Must be added as new top-level output ports, driven to correct default values:
- `vsd_en = 1'b1` (enable SD power)
- `sd_sel = 1'b0` (select 3.3V)
- `sd_reset_n = 1'b1` (deassert reset)

### 3.5 Reset Polarity Inverted (CHIP WON'T RESET)

**Impact**: System never comes out of reset, or never enters reset.

P3 reference uses active-HIGH reset (A6). AX7203 uses active-LOW (T6). Enable `PITON_FPGA_RST_ACT_HIGH` define.

### 3.6 PS/PMC Initialization Required (FABRIC MAY NOT FUNCTION)

**Impact**: Unclear -- Versal PL fabric may not be fully operational without PMC init.

The P3 reference includes `ps_wizard_0` in its Block Design. Whether this is strictly required for PL-only designs is unclear. **Include it in the BD to be safe** -- the reference project proves this configuration works.

### 3.7 Clock Input Frequency Change (WRONG TIMING)

**Impact**: All derived clocks wrong, baud rate wrong, DDR timing wrong.

200 MHz → 100 MHz input. All Clock Wizard divider ratios must be reconfigured. If targeting the same 30 MHz chipset_clk:
- AX7203: 200 MHz ÷ 6.667 = 30 MHz
- P3: 100 MHz ÷ 3.333 = 30 MHz

### 3.8 UART Transmitter Deadlock & LSR Polling Hang (Build 37-38)

**Impact**: Bootrom execution hangs indefinitely in the print loop; no characters are printed on the serial terminal (`uart_tx` remains stuck at 1).

**Problem Description**:
During P3 hardware bring-up, the PDI is successfully programmed and Vivado reports `DONE: HIGH`. However, there is no console output. ILA analysis (Build 37-38) shows that the Ariane core executes and issues AXI-Lite write transactions to configure the UART registers (receiving `OKAY` responses), but the UART transmitter never drives `uart_tx` low. The CPU then spins in an infinite read loop, polling the Line Status Register (LSR, offset 5, translated AXI address `0x1014`) and constantly reading `0x00` instead of the expected Transmit Holding Register Empty (THRE) bit (`0x20` or `0x60`).

**Root Causes**:
1. **Autoflow Control (AFE) Deadlock (Software/Hardware Mismatch)**:
   - By default, the OpenPiton bootrom `init_uart()` writes `0x20` to `UART_MODEM_CONTROL` (MCR), which enables Automatic Flow Control (AFE).
   - On the HuaPro P3 board/subcard, only `TXD` (CM59) and `RXD` (CN59) pins are physically routed. The physical flow-control pins (`CTS`/`RTS`) are completely absent.
   - When AFE is active, the UART transmitter refuses to send any data unless its incoming `ctsn` pin is asserted. Without physical CTS pins, the transmitter hangs. (Although `uart_top.v` ties `.ctsn(1'b0)`, the Xilinx AXI UART 16550 IP PG143 notes that enabling AFE without enabling FIFOs via `FCR` results in undefined behavior).
   - *Resolution*: Modify the bootrom `init_uart()` to write `0x00` to MCR, disabling Autoflow. Verified in Build 38.
2. **Register Address/Data Bus Alignment Mismatch (Bridge Shifting Constraint)**:
   - The CPU accesses the UART over a 64-bit NoC, translated to AXI-Lite by `noc_axilite_bridge`.
   - The Xilinx `axi_uart16550` IP uses 32-bit registers spaced by 4 bytes. In `uart_top.v`, unmasked register offsets are shifted left by 2:
     `core_axi_araddr = (core_axi_araddr_unmasked[12:0] << 2) | 13'h1000;`
     Reading LSR (offset 5) translates to AXI address `0x1014`.
   - Since the IP has a 32-bit bus, it returns the 8-bit LSR value on bits [7:0] of `s_axi_rdata` (byte lane 0).
   - However, because the original unmasked address is `0xFFF0C2C005` (low 3 bits are 5), the `noc_axilite_bridge` expects the data to return on byte lane 5. It performs:
     `a_axi_rdata_shifted = (m_axi_rdata >> {m_axi_araddr[2:0], 3'b000})` (shifted right by 40 bits).
   - Since `m_axi_rdata` is connected to the 32-bit `core_axi_rdata` bus, its upper 32 bits are zero-extended. Shifting right by 40 bits discards the valid register data and returns `0x00`, locking the CPU in the THRE polling loop.
   - *Proposed Fix*: In `uart_top.v`, replicate the UART read data byte 0 across all 8 byte lanes of the bridge read bus (i.e., `.m_axi_rdata({8{core_axi_rdata[7:0]}})`), ensuring the bridge always receives the correct register byte regardless of the address offset lane.

3. **Transition to SiFive UART (Build 40) & Instruction Fetch Hang Analysis**:
   - To isolate the Xilinx AXI UART IP and custom bridge shifting complexity, Build 40 migrated the UART block to the SiFive Custom UART (TLUART) template.
   - Hardware bring-up of Build 40 showed that `DONE` went HIGH, the AXI debug hub and ILAs were fully accessible, but no console output was produced.
   - High-priority signals captured in `axis_ila_0` showed `top_status = 0xff02` (resets released, clocks stable) and `chip_seen = 0x750f` (resets released, core wake-up counter active, and some L1.5 cache activity).
   - However, no transactions ever reached the SiFive UART registers. This rules out the UART peripheral block or board-level routing as the source of the hang, indicating instead that the Ariane core is stuck earlier in the boot sequence (e.g. instruction fetch from the bootrom or memory access).
   - *Build 41 implementation*: keep the proven BD-owned debug hub path, but split the payload across three small ILAs instead of one wide post-synthesis probe. `axis_ila_0` captures heartbeat/top status/chipset seen/chip-tile seen. `axis_ila_1` captures a 64-bit core-side payload from `p3_debug_bus[63:0]`: last L1.5 request address `[39:0]`, request type, request size, Ariane wake/reset/interrupt flags, and live L1.5 handshake flags. `axis_ila_2` captures a 64-bit chipset-side payload from `p3_debug_bus[127:64]`: last chip-to-chipset NoC2 low data, last bootrom request low data, last bootrom response low data, and sticky bootrom/UART/AXI/NoC flags.
   - Build 41 uses explicit BD ports `p3_dbg_b41_core_bus64_i` and `p3_dbg_b41_chipset_bus64_i` rather than reusing the Build 40 UART payload port. The P3 creation flow now forces a single-core Ariane PyHP context and Vivado defines (`PITON_ARIANE`, RV64 platform/debug/CLINT/PLIC, `WT_DCACHE`) so the debug build cannot silently synthesize a non-Ariane/default-tile configuration.
   - Build 41 must also apply the Vivado `unread` shim. The first Build 41 implementation attempt completed top-level synthesis but failed `opt_design` DRC `INBB-3` on seven Ariane frontend `unread` black boxes, matching the earlier Build 24 failure mode. The common P3 BD creation flow now swaps the empty common_cells helper for `unread_vivado_impl.sv`, and the Build 41 runner repeats the swap for `-skip_create` resume runs.
   - *Build 41 hardware result*: the image programmed successfully and all three BD-owned ILAs were accessible through debug hub `0x3ffc0000000`. The capture showed resets released (`top_status=0xff03`), chip/tile and chipset sticky activity (`0x7fff` each), a last L1.5 access at `0xfff1010170` in the bootrom window, and bootrom response activity in the chipset payload (`0x00000006ecfff5f9`). Correcting for the outer chipset status-byte wrapper gives inner flags `0xfff5`, with `invalid_access=0` and `cpu_mem_traffic=1`. Two serial captures, including one started before reprogramming, still produced no `/dev/ttyUSB0` output. This moves the main fault past reset/fetch/bootrom reachability and into early boot control flow, SiFive UART MMIO transaction contents, UART TX generation, or DDR/store pressure that needs a no-stack validation build.
   - *Build 42-A validation plan*: use `BOOTROM_MODE=asm_uart` to generate a no-stack bootrom that initializes SiFive UART and repeatedly writes `A` without calling C or touching DDR. The corresponding P3 debug build uses a raw UART ILA payload so a failed serial test can still distinguish no AXI/TL UART transaction from a valid TXDATA write that does not toggle `uart_tx`.
   - *Build 42-A hardware result*: the image built and programmed successfully, both ILAs refreshed through `PMC_AXI_NOC0`, and the no-stack assembly image still produced no `/dev/ttyUSB0` output during a 480-second capture. The decode showed heartbeat activity, `top_status=0xff03`, UART sticky seen `0xffff`, chip/tile sticky seen `0x7fff`, and raw UART live bus `0x000000f008000000`. This invalidates the simple "C stack or DDR store queue prevents first UART byte" explanation for the first failure point. Build 42-B should not be used as the next proof step until the SiFive UART bridge/probe path explains why sticky UART events are latched while the live raw bus shows idle `uart_tx=1` and no retained TXDATA write address/data.
   - *Build 42-B implementation*: add a gated `P3_BUILD42B_BRAM_STACK` AXI interposer for the normal C bootrom. This experiment originally assumed the OpenPiton memory AXI port carried translated DDR addresses. Build 44 later showed the top-level BD boundary can see CPU physical DDR addresses such as `0x84000000`, so any BRAM-stack retry must first re-check the actual AXI address convention in that build rather than relying on the `0x03ff0000..0x04000000` translated-window assumption.

---

## 4. RTL Change List

| File | Change | Severity |
|------|--------|----------|
| `piton/design/chipset/rtl/chipset.v` | Add `HUAPROP3_BOARD` ifdef: behavioral SD clock (replace ODDR), reset polarity, uart_boot_en, SD control signals | **High** |
| `piton/design/chipset/rtl/chipset_impl.v.pyv` | Add VSD_EN/SD_SEL/SD_RESET# output ports, wire through chipset_impl to top level | **High** |
| `piton/design/chipset/mc/rtl/mc_top.v` | Not modified -- bypassed entirely by using `PITONSYS_AXI4_MEM` define | Medium |
| New: `piton/design/xilinx/huaprop3/constraints.xdc` | All PHC3 pin assignments, DDR4, clock, reset, timing constraints | **High** |
| New: `piton/design/xilinx/huaprop3/devices_ariane.xml` | Copy from a7203x, adjust DDR size if needed | Low |
| New: `piton/design/xilinx/huaprop3/devices.xml` | SPARC device map (copy from a7203x) | Low |
| New: Versal Clock Wizard IP | 100 MHz LVDS15 in → 30 MHz chipset + 30 MHz SD out | **High** |
| `piton/tools/src/proto/board.list` | Add `huaprop3` as vivado board | Low |
| `piton/tools/src/proto/block.list` | Add `huaprop3,30,xxxx` config line | Low |
| New: `build/huaprop3/huaprop3.dts` | Device tree for P3 | Medium |
| Rebuild: bootrom `bootrom_linux.sv` | With new DTB embedded | Medium |
| Rebuild: BBL `bbl.bin` | With new DTB | Medium |

---

## 5. New IP Cores (in Block Design)

| IP | Purpose | Configuration |
|----|---------|---------------|
| **Versal Clock Wizard** | Replace 7-series MMCM | 100 MHz LVDS15 input → 30 MHz chipset_clk, 30 MHz sd_sys_clk |
| **Versal DDRMC** | DDR4 memory controller | Hard block, configured via BD. Copy P3 reference config (800 MHz, ROW_COLUMN_BANK, CL11) |
| **AXI NoC** | Route AXI4 traffic to DDRMC | 1 AXI4 slave port (from OpenPiton), 1 MC port (to DDRMC). Copy P3 reference topology |
| **ps_wizard** | Initialize Versal PMC/PS | Minimal config. Required for PL fabric operation. Copy from P3 reference |
| **proc_sys_reset** | Synchronized reset generation | Standard Vivado IP. Feeds synchronized reset to OpenPiton chipset |
| **ILA** (optional) | Debug | Probe key signals during bring-up: DDR4 calib_complete, UART TX, SD signals |

---

## 6. SD Interface Adaptation (Detailed)

### 6.1 SPI Mode on P3

OpenPiton's `piton_sd` controller uses SPI-over-SD-bus:
- `sd_cmd` = MOSI (output from FPGA)
- `sd_dat[0]` = MISO (input to FPGA)
- `sd_dat[3]` = CS (active-low chip select)
- `sd_clk_out` = SPI clock

On AX7203, these are effectively unidirectional (the `inout` declaration in `piton_sd_top.v` just means the FPGA-side tristate is inferred, but only one direction is active at a time in SPI mode).

On P3, the daughter card's SD_CMD and SD_D[0:3] are **physically bidirectional** (they pass through a bus transceiver). The same SPI protocol works, but the FPGA must correctly drive tristate enable:
- `sd_cmd`: output only (MOSI) → tristate enable = always drive
- `sd_dat[0]`: input only (MISO) → tristate enable = always high-Z from FPGA
- `sd_dat[1:2]`: unused in SPI mode → pull up
- `sd_dat[3]`: output only (CS) → tristate enable = always drive

Verify that `piton_sd_top.v` handles this correctly in its internal tristate logic.

### 6.2 Voltage Control Signals

```verilog
// New top-level outputs for P3 daughter card
output vsd_en;       // SD power enable (active-high)
output sd_sel;       // Voltage select: 0=3.3V, 1=1.5V
output sd_reset_n;   // SD card reset (active-low)

// Default values during normal operation:
assign vsd_en     = 1'b1;  // Power enabled
assign sd_sel     = 1'b0;  // 3.3V mode (standard SD init)
assign sd_reset_n = 1'b1;  // Reset deasserted
```

### 6.3 SD Clock Generation (No ODDR)

Replace ODDR with behavioral toggle:

```verilog
`ifdef HUAPROP3_BOARD
    // Versal has no ODDR/ODDRE1 -- use behavioral output register
    // sd_clk_out_internal comes from piton_sd_top's clock divider
    // This register forwards it to the output pin
    FDCE sd_clk_reg (
        .Q(sd_clk_out),
        .C(sd_clk_out_internal),
        .CE(1'b1),
        .CLR(1'b0),
        .D(~sd_clk_out)
    );
    // Alternatively, if Versal synthesis can infer an output flip-flop:
    // reg sd_clk_out_r;
    // always @(posedge sd_clk_out_internal) sd_clk_out_r <= ~sd_clk_out_r;
    // assign sd_clk_out = sd_clk_out_r;
`endif
```

At SD SPI speeds (<=25 MHz), timing is not a concern. The ODDR's DDR-to-SDR function was overkill for SPI clock generation.

### 6.4 XDC Constraints for SD (PHC3 / Bank 705)

```
# SD-SPIFLASH daughter card on PHC3 / Bank 705

# SD interface
set_property PACKAGE_PIN CW60 [get_ports sd_clk_out]
set_property PACKAGE_PIN DB61 [get_ports sd_cmd]
set_property PACKAGE_PIN DC61 [get_ports sd_cd]
set_property PACKAGE_PIN DC60 [get_ports {sd_dat[0]}]
set_property PACKAGE_PIN DC59 [get_ports {sd_dat[1]}]
set_property PACKAGE_PIN CY58 [get_ports {sd_dat[2]}]
set_property PACKAGE_PIN DA58 [get_ports {sd_dat[3]}]

# SD control signals (P3 daughter card specific)
set_property PACKAGE_PIN CY60 [get_ports vsd_en]
set_property PACKAGE_PIN DA59 [get_ports sd_sel]
set_property PACKAGE_PIN DA60 [get_ports sd_reset_n]
set_property PACKAGE_PIN DA61 [get_ports sd_wp]

# All PHC3 I/O is LVCMOS15
set_property IOSTANDARD LVCMOS15 [get_ports sd_clk_out]
set_property IOSTANDARD LVCMOS15 [get_ports sd_cmd]
set_property IOSTANDARD LVCMOS15 [get_ports sd_cd]
set_property IOSTANDARD LVCMOS15 [get_ports {sd_dat[*]}]
set_property IOSTANDARD LVCMOS15 [get_ports vsd_en]
set_property IOSTANDARD LVCMOS15 [get_ports sd_sel]
set_property IOSTANDARD LVCMOS15 [get_ports sd_reset_n]
set_property IOSTANDARD LVCMOS15 [get_ports sd_wp]

# Pullup on unused SPI data lines
set_property PULLTYPE PULLUP [get_ports {sd_dat[1]}]
set_property PULLTYPE PULLUP [get_ports {sd_dat[2]}]

# UART (FT232HQ via daughter card)
set_property PACKAGE_PIN CM59 [get_ports uart_tx]
set_property PACKAGE_PIN CN59 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS15 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS15 [get_ports uart_rx]

# User LEDs (daughter card)
set_property PACKAGE_PIN CF60 [get_ports {leds[0]}]
set_property PACKAGE_PIN CF59 [get_ports {leds[1]}]
set_property IOSTANDARD LVCMOS15 [get_ports {leds[*]}]
```

**Note**: There is an unresolved discrepancy between the reference project `shell.xdc` and `p3_io.md` regarding the pin assignment on PHC3. While UART works on `CW58/CW59` (defined as B3/B2 in reference project), the manual specifies `CM59/CN59` for UART. The reference project mapped SD signals to `CV57`, `DB57`, `DC56` etc. (SPI mode pinout), while `p3_io.md` maps them to `CW60`, `DB61`, `DC60` etc. If the reference project layout is physically wired, a native SD controller mapping might suffer from an **SPI Wire-Crossing** mismatch where `sd_cmd` (DB57) and `sd_dat[3]` (CY55) are swapped relative to the card's native input/output requirements. Build 56 is designed to run parallel experiments to resolve this conflict.

### 6.5 SD Timing Constraints

Adapt from AX7203 `constraints.xdc` lines 119-147. The SD clock is still generated from an internal divider chain, but the source changes (Clock Wizard output instead of MMCM):

```
# SD timing -- adapt clock source paths after synthesis
create_generated_clock -name sd_fast_clk -source [get_pins <clock_wizard_output>] -divide_by 2 [get_pins <sd_fast_clk_reg>/Q]
create_generated_clock -name sd_slow_clk -source [get_pins <clock_wizard_output>] -divide_by 200 [get_pins <sd_slow_clk_reg>/Q]

# Output/input delays same as AX7203
set_output_delay -clock [get_clocks sd_clk_out] -min -add_delay -6.000 [get_ports {sd_dat[*]}]
set_output_delay -clock [get_clocks sd_clk_out] -max -add_delay  8.000 [get_ports {sd_dat[*]}]
# ... (same pattern as AX7203 constraints.xdc lines 127-147)
```

The exact `-source` paths depend on the final Clock Wizard configuration and will be determined after initial synthesis.

### 6.6 Build 49 SD Ready Hang and init_done Analysis

**Problem Description (Build 49)**:
During the SD-smoke test (`BOOTROM_MODE=sd_smoke`), the console output prints the banner but hangs at `read lba0[0]`. ILA captures show `buf_sd_noc2_valid=1` but `sd_buf_noc2_ready=0` (corresponding to the internal `sd_splitter_rdy=0`), blocking the AXI/NoC request from firing (`sd_req_fire=0`).

**Build 50 Follow-up**:
Build 50 replaces the Build 49 C smoke code with the no-stack `asm_uart16550_sdprobe` bootrom while preserving the current SD hardware configuration. It is expected to print `B50 UART SD` before the first SD load. If it then hangs with `buf_sd_noc2_valid=1` and `sd_buf_noc2_ready=0`, the stop is independent of stack, DDR, GPT parsing, BBL contents, and C bootrom sequencing.

**Detailed Comparison & Root Causes**:
1. **Controller Architecture Difference**:
   - *Reference Project (Chipyard)*: Communicates with the SD card (or SPI Flash on the daughter card) using an **SPI controller** in **SPI mode**. It maps `sdio_spi_cs` to `DB57` and `sdio_spi_dat_0` to `DC56`.
   - *Our Project (OpenPiton)*: Uses a native **4-bit SD controller (`sdc_controller.v`)** with bidirectional CMD/DAT lines.
2. **The `init_done` Reset Lock**:
   - In OpenPiton's `piton_sd_top.v`, the data-path controller (`sd_core_ctrl`) and cache manager are held in reset using `.rst (~init_done | rst)`.
   - `init_done` is asserted by the hardware initializer `piton_sd_init.v` only after it successfully completes the physical SD card initialization sequence (CMD0, CMD8, ACMD41, etc.).
   - Since `init_done` remains `0` (initialization fails), the core controller remains in reset and drives `sd_splitter_rdy` (NoC2 ready) to `0` permanently, backpressuring the CPU's NoC request.
3. **Physical-Layer Discrepancies causing Initialization Failure**:
   - **Card Detect Polarity**: The reset signal is defined as `rst = sys_rst | sd_cd`. Since `SD_CD#` (DC61) is active-low (0 when card is present), if the signal is read as 1 (due to constraints or card presence sensing), the entire init block is held in reset.
   - **SD Clock Generation**: Direct wire assignment `assign sd_clk_out = sd_clk_out_internal` without an ODDR primitive on Versal can cause clock skew/duty-cycle issues, preventing the physical SD card from responding to command sequences.
   - **Tristate Bidirectional Buffer Delay**: The `inout` `sd_cmd`/`sd_dat` lines rely on inferred `IOBUF`s. On Versal, the bidirectional direction switching must be carefully timed to avoid bus contention with the card.

### 6.7 Build 52 Result and Build 53 CMD55 Debug

Build 52 validates the first part of the SD reset hypothesis. With `P3_SD_IGNORE_CARD_DETECT_RESET`, raw `sd_cd` remains high on P3, but the native SD controller's internal reset releases. Hardware ILA capture then shows Wishbone acks, SD clock toggles, CMD output-enable activity, and at least one command interrupt. Therefore the Build 49/50 backpressure was caused by the SD init gate (`~init_done | rst`), and the raw card-detect signal was a real reset blocker.

Build 52 does not complete card initialization. The live init FSM stops at `0x34`, which maps to `ST_ACMD41_CMD55_WAIT_INT` in `piton_sd_init.v`: CMD0 and CMD8 have completed, and the hardware is waiting for the CMD55 completion interrupt before issuing ACMD41. This narrows the next failure to the command path, not DDR, UART, bootrom stack, or NoC request acceptance.

Build 53 adds `P3_BD_SD_CMD_DEBUG_ILA` while preserving the Build 52 hardware baseline. The compact SD ILA bus is repacked as `{init_state, watchdog_low, command_index, cmd_int_status_sd, cmd_int_status_wb, cmd_timeout, cmd_master_state, cmd_serial_state, start/finish/CMD flags}`. The expected interpretation is:

- CMD start absent in WB or SD clock domain: debug the Wishbone-to-SD FIFO and `cmd_start_sd_clk` generation.
- CMD master executing and serial host in `READ_WAIT`: the controller issued CMD55 and is waiting for the card to pull CMD low for a response.
- SD-domain timeout/error status present but WB-domain `int_cmd` low: debug the SD-to-WB interrupt/status FIFO and interrupt-enable path.
- CMD55 completes but loops back: decode the R1 response bits and card status checks in `ST_ACMD41_CMD55_RD_RESP0`.

Build 53 hardware capture hit the second case consistently. The command starts are observed in both WB and SD clock domains, timeout and command-finish sticky bits have fired, and the live bus repeatedly shows CMD55 active with the serial host in `READ_WAIT`, `cmd_oe_o=0`, and `sd_cmd_dat_i=1`. This means the OpenCores command path is no longer blocked internally; it is waiting for an external CMD-line response from the card.

Build 54 keeps the same controller and probes, but adds P3 native-SD idle pull-ups on `sd_cmd`, `sd_dat[0]`, and `sd_dat[3]`. The primary hypothesis is that DAT3/CS must be high when CMD0 is issued; if it floats or is interpreted low, the card can enter SPI mode and will not answer later native CMD55 traffic on the CMD line. If Build 54 still stops at `READ_WAIT`, the next fault is more likely SD clock output quality or bidirectional CMD timing rather than Wishbone/NoC/bootrom behavior.

Build 54 commands:

```bash
vivado -mode batch -source scripts/p3_build54_sd_native_pullups.tcl -tclargs -jobs 1
vivado -mode batch -source scripts/p3_program_pdi.tcl -tclargs huaprop3_build54_sd_native_pullups/debug_build/p3_top_build54_sd_native_pullups.pdi
vivado -mode batch -source scripts/p3_ila_capture_build54_sd_native_pullups.tcl
python3 scripts/p3_decode_build53_ila_csv.py --tag build54 huaprop3_build54_sd_native_pullups/debug_build
```

Build 54 hardware validation confirmed the deadlock on CMD55 timeouts (stuck in `ST_ACMD41_CMD55_WAIT_INT` and `READ_WAIT` waiting for the card response start bit). Since the added pull-ups did not resolve the silence, we analyzed the board pinout.

A key conflict was highlighted: UART works on `CW58/CW59` (B3/B2) instead of the manual's `CM59/CN59` (C8/C9), proving that `p3_io.md` does not match the actual physical layout directly. This points to the **SPI Wire-Crossing Hypothesis**: the reference project (`shell.xdc`) routed SD in SPI mode, where `DB57` was connected to Card DAT3/CS and `CY55` was connected to Card CMD/DI. By using native SD mode, OpenPiton outputs `sd_cmd` on `DB57` and `sd_dat[3]` on `CY55`, physically swapping command and data lines.

Build 55 is reserved for testing the IOB clock path (`huaprop3_build55_sd_clk_iob_reg.pdi`).

Build 56 is introduced as a dedicated experiment to test physical pin configurations:
- **Hypothesis A (SPI Swap)**: Swap `sd_cmd` (CY55) and `sd_dat[3]` (DB57) in XDC to verify the SPI wire-crossing hypothesis.
- **Hypothesis B (Manual Alignment)**: Remap SD completely to `p3_io.md`'s PHC3 native pins to test the manual alignment.

---


## 7. Device Tree and Bootrom Changes

### 7.1 New DTS (`build/huaprop3/huaprop3.dts`)

Copy `build/a7203x/a7203x.dts` and modify:
- Board/model string → "huaprop3"
- Memory `reg` → update size if DDR4 > 1 GB
- All other fields unchanged if chipset_clk = 30 MHz

### 7.2 Address Consistency Check

| Address | devices_ariane.xml | DTS reg | Bootrom | BBL |
|---------|-------------------|---------|---------|-----|
| Memory | `0x80000000` | `0x80000000` | `DRAM_BASE` in startup.S | - |
| PLIC | `0xfff1100000` | `0xfff1100000` | - | - |
| CLINT | `0xfff1020000` | `0xfff1020000` | - | - |
| UART | `0xfff0c2c000` | `0xfff0c2c000` | UART init code | early debug |
| Bootrom | `0xfff1010000` | - | linker.lds `ROM_BASE` | - |

All addresses stay the same. **No address-related changes needed.**

### 7.3 Bootrom Rebuild

```bash
# Only needed if chipset_clk frequency changes (otherwise just update DTB)
cd piton/design/chipset/rv64_platform/bootrom/linux/
cp $PITON_ROOT/build/huaprop3/huaprop3.dtb rv64_platform.dtb
make clean && make
# Produces bootrom_linux.sv
```

---

## 8. Recommended Bring-Up Sequence

Each step validates a specific hardware layer before adding complexity.

**FPGA scripts** (in `scripts/`):
```bash
vivado -mode batch -source scripts/p3_build_bitstream.tcl   # synth + impl + PDI
vivado -mode batch -source scripts/p3_program.tcl            # program via 100.93.77.36:3121
vivado -mode tcl   -source scripts/p3_debug.tcl              # ILA debug session
```

### Step 1: LED Blinker (no OpenPiton)

**Validates**: Vivado 2024.2 targets VP1902, XDC pin assignments, PHC3 daughter card power, clock wizard locks.

Create minimal BD: Clock Wizard (100 MHz in, 30 MHz out) → counter → LED output. If LEDs blink, the basic infrastructure works.

### Step 2: UART Echo (no OpenPiton)

**Validates**: UART pin assignments (CM59/CN59), FT232HQ communication, baud rate.

Add simple UART TX module to Step 1 project. Send "P3 HELLO\r\n" at 115200 baud. Capture on PC.

### Step 3: DDR4 Memory Test (no OpenPiton)

**Validates**: DDRMC configuration, AXI NoC, DDR4 calibration, memory read/write.

Use the P3 reference project's DDR4 configuration (DDRMC + axi_noc_0). Add a simple AXI master that writes a pattern and reads it back. Monitor `init_calib_complete` via ILA or LED.

**This is the highest-risk step.** If DDR4 calibration fails, nothing downstream works (DDR3 MIG `init_calib_complete` on AX7203 gates the entire chipset reset, and the same is likely true on P3).

### Step 4: OpenPiton Chipset UART-Only (BRAM memory)

**Validates**: OpenPiton core boots, NoC works, chipset UART path, bootrom executes.

Build OpenPiton with `PITONSYS_NO_MC` (no memory controller) and a small BRAM-backed memory. Connect to Clock Wizard and reset. Expect bootrom banner on UART.

### Step 5: Add DDR4

**Validates**: `noc_axi4_bridge` → AXI4 → AXI NoC → DDRMC path, full memory access.

Replace BRAM with the DDR4 path from Step 3. Boot should proceed further (BBL loader starts).

### Step 6: Add SD Card

**Validates**: SD SPI interface, VSD_EN/SD_SEL/SD_RESET# signals, piton_sd controller.

Connect SD signals. BBL should load from SD card. VSD_EN/SD_SEL must be correctly driven or SD card won't respond.

### Step 7: Full Linux Boot

**Validates**: Everything together.

BBL + Linux kernel loads from SD, kernel boots, `piton_sd` driver detects partitions, userspace starts.

### Step 8: Verify and Benchmark

Single-core Quicksilver execution on P3. Compare correctness with AX7203 results.

---

## 9. Risk Analysis

### High Risk

| Risk | Impact | Mitigation |
|------|--------|------------|
| DDRMC integration | No memory = no boot | Start from P3 reference DDR4 config; test independently (Step 3) before integrating with OpenPiton |
| `protosyn` incompatible with Versal BD flow | Cannot use standard build system | Start with manual BD + OpenPiton RTL wrapper; evaluate protosyn later |

### Medium Risk

| Risk | Impact | Mitigation |
|------|--------|------------|
| ODDR replacement affects SD timing | SD clock jitter/phase issues | Test with ILA; SD SPI is slow (<=25 MHz), timing margins are large |
| PS/PMC init requirements | PL fabric may not function | Include ps_wizard in BD (proven by reference project) |
| SD daughter card pin mapping discrepancy | SD signals route to wrong FPGA pins | Cross-check p3_io.md PHC3 table against reference XDC; test with logic analyzer |

### Known Unknowns

| Unknown | How to Resolve |
|---------|---------------|
| VP1902 exact LUT/BRAM/DSP counts | Open Vivado device browser for xcvp1902 |
| DDR4 SODIMM capacity on P3 | Check board documentation or physical SODIMM label |
| Whether piton_sd SPI mode works through P3 bus transceiver | Test at Step 6; fallback: direct-wire SD without transceiver |
| Multi-SLR placement impact on single-core | Likely negligible (single core fits in one SLR); verify post-implementation |
| PHC voltage must be set in System Manager before programming | Confirm procedure with P3 board documentation |

---

## 10. Reference File Index

| Purpose | File Path |
|---------|-----------|
| AX7203 constraints | `piton/design/xilinx/a7203x/constraints.xdc` |
| AX7203 device map | `piton/design/xilinx/a7203x/devices_ariane.xml` |
| AX7203 DTS | `build/a7203x/a7203x.dts` |
| P3 daughter card I/O guide | `p3_io.md` |
| P3 reference XDC | `huaprop3onecore/huaprop3onecore.srcs/constrs_1/imports/.../shell.xdc` |
| P3 reference block design | `huaprop3onecore/huaprop3onecore.srcs/sources_1/bd/huaprop3top/huaprop3top.bd` |
| Chipset top | `piton/design/chipset/rtl/chipset.v` |
| Chipset impl | `piton/design/chipset/rtl/chipset_impl.v.pyv` |
| SD controller | `piton/design/chipset/noc_sd_bridge/rtl/piton_sd_top.v` |
| AXI4 bridge | `piton/design/chipset/noc_axi4_bridge/rtl/noc_axi4_bridge.v` |
| Memory controller | `piton/design/chipset/mc/rtl/mc_top.v` |
| Bootrom source | `piton/design/chipset/rv64_platform/bootrom/linux/` |
| Board registration | `piton/tools/src/proto/board.list` |
| Block registration | `piton/tools/src/proto/block.list` |

---

## 11. UART Migration Variant: SiFive TLUART

Build 39 introduces a reversible P3-only UART migration from Xilinx `axi_uart16550` to the reference `huaprop3onecore` SiFive/Chipyard `TLUART`. This is motivated by Builds 34-38: core-side traffic reached the UART AXI-lite interface and received OKAY responses, but `uart_tx` never toggled, and disabling ns16550 auto-flow-control did not produce serial output.

The hardware variant is selected with `P3_SIFIVE_UART`. It adds the generated SiFive UART RTL under `piton/design/chipset/io_ctrl/rtl/sifive_uart/`, wraps it with an AXI4-Lite to 64-bit TileLink-UL bridge, and removes the ns16550-specific address transform for P3. The register map becomes SiFive word-aligned offsets: `TXDATA=0x00`, `RXDATA=0x04`, `TXCTRL=0x08`, `RXCTRL=0x0c`, `IE=0x10`, `IP=0x14`, and `DIV=0x18`.

The software stack must move with the hardware. Bootrom builds use `PITON_SIFIVE_UART=1` so `uart.c` performs 32-bit MMIO, sets `DIV=freq/baud-1`, enables TX/RX, and polls `TXDATA[31]`. DTS uses `compatible = "sifive,uart0"` so riscv-pk/BBL selects its SiFive UART backend; the backend must use ordinary MMIO writes rather than AMO to TXDATA because the new bridge is AXI4-Lite, not an atomic-capable memory target. Linux config enables `CONFIG_SERIAL_SIFIVE` and `CONFIG_SERIAL_SIFIVE_CONSOLE`.

## 12. P3 SPI SD Debug Builds 59-63

Build 59 tested the smallest protocol-level fix after Build 58: OpenCores `rwspi_wire_data` now drives MOSI/CMD high during reset and idle wait states, matching the standalone Build 56 reference-SPI probe. The hardware result confirmed the fix at the pin-observation level (`spi_mosi=1`, `spi_cs_n=1`) and kept the proven AXI16550 UART path, but `miso_low_seen` was still zero.

The Build 59 capture also showed why another ordinary current-state capture would be ambiguous: the live initializer state was `POWER_WAIT`, while sticky status still showed a previous SPI init error. Build 60 therefore adds `P3_SPI_SD_HISTORY_DEBUG` rather than changing pin maps or boot flow. The existing SD ILA bus is repacked as `{init_history, send_cmd_history}` so one capture can tell whether `init_sd_p3` ever reached `CMD0_SEND/CMD0_WAIT` after reset and whether the OpenCores `send_cmd` block actually queued command bytes. If Build 60 records command progress but no MISO low transition, the remaining gap is no longer reset, UART, NoC, Wishbone, or high-level SD init sequencing; it is the OpenCores byte-FIFO command/response timing versus the known-good Build 56 bit-banged SPI sequence.

Build 60's raw CSV showed `send_cmd` in response-wait states with `tx_count=62/63`, so the next build should not assume the command sender is idle. Build 61 adds `P3_SPI_SD_PAD_DEBUG` and repacks the SD ILA bus as `{captured_bit_count[5:0], first_56_mosi_bits[55:0], capture_active, spi_cs_n}`. The key comparison is whether the first CS#-low window contains `0xff400000000095`, which is the OpenCores pre-response idle byte followed by CMD0. This keeps the proven AXI16550 UART, NoC/Wishbone path, reference SPI pin map, and bootrom stimulus fixed while deciding whether to target the byte/FIFO wire engine or the external card-response boundary.

Build 61 hardware confirmed the OpenCores command launch at the internal pad observation point: the capture reported `cmd_bit_count=56` and `cmd_mosi56=0xff400000000095`. The card response was still absent (`miso_low_seen=0`). This closes the byte-order and first-command launch questions for CMD0. Future builds should avoid broad boot-flow changes and focus on the physical response boundary: exact MISO input sampling, CS#/SCK idle timing, and differences from the Build 56 reference-SPI probe that already saw a response on the same board/card path.

Build 62 moves the known-good Build 56 SPI command sequencer into the full OpenPiton SD wrapper under `P3_SPI_SD_REF_CMD_DEBUG`. In this mode the full shell, constraints, BD debug hub, AXI16550 UART, bootrom stimulus, and SD top-level pads remain in place, but the SD pad drivers are temporarily muxed from the reference bit-banged CMD0/CMD8 engine. A passing Build 62 means the external card path is reachable in the full shell and the next fix should target OpenCores SPI CS/SCK/MOSI/response timing. A failing Build 62 means the problem is not OpenCores byte order; it is full-shell pad, power, reset, or top-level SD control integration.

Build 62 routed successfully but failed at `write_device_image` with Versal DRC `AVAL-352` because top-level tristate assignments on `sd_cmd` and `sd_dat[3]` inferred `OBUFT` cells driving `inout` ports. Build 63 keeps the same reference-SPI boundary test and AXI16550 path, but makes the SD pad boundary explicit: `piton_spi_sd_top.v` instantiates `IOBUF` for `sd_cmd` and every `sd_dat` bit, drives internal output/enable nets, and samples the card through internal input nets. This removes the bitgen DRC as a variable before interpreting the reference-SPI full-shell result.
