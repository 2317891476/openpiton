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

Build 59 hardware execution confirmed that driving MOSI high during reset and idle states kept the lines clean, but MISO still remained high (timeout error `0x01`), indicating that the card was not responding to CMD0. Build 60 therefore adds history debug tracking (`P3_SPI_SD_HISTORY_DEBUG`) within `init_sd_p3` to record the state transitions and timeouts of the SPI initializer state machine.

Build 60 hardware execution proved that the NoC and Wishbone requests were successfully accepted, and the clock toggled. The state machine successfully reached the `CMD0_WAIT` state, but `miso_low_seen` stayed zero, and it timed out. To determine if the physical command byte actually reached the SD pads, Build 61 adds pad-level monitoring (`P3_SPI_SD_PAD_DEBUG`) to capture the first 56 bits driven on MOSI after CS# falls.

Build 61 captured the correct command format (`0xff400000000095` for idle byte + CMD0) at the internal pad level, but the external card still sent no response. To verify whether the issue lay with the OpenCores SPI master timing or the physical board setup, Build 62 implements a standalone reference SPI sequencer (`P3_SPI_SD_REF_CMD_DEBUG`) inside the full OpenPiton shell, mimicking the exact timing of the successful Build 56 probe.

Build 62 failed during the Vivado `write_device_image` phase with a DRC error **AVAL-352**, because implicit `OBUFT` tri-state drivers were inferred on the top-level `inout` pins, which is illegal on the Versal architecture. Build 63 fixes this by explicitly instantiating FPGA `IOBUF` primitives for `sd_cmd` and `sd_dat[3:0]` in [piton_spi_sd_top.v](file:///L:/home/illya/openpiton/piton/design/chipset/noc_sd_bridge/rtl/piton_spi_sd_top.v).

Build 63 successfully completed bitgen and programmed onto the hardware. The reference SPI probe (CMD0/CMD8 test) succeeded, proving that the physical connection, power controls, and explicit `IOBUF` boundary were correct. Build 64 then returns to the normal OpenCores SPI SD path while keeping Build 63's explicit `IOBUF` configuration.

Build 64 successfully completed the full SPI SD initialization sequence (`CMD0 -> CMD8 -> CMD55 -> ACMD41`), with the initialization FSM asserting `INIT_DONE=1`. Build 65 then replaces the initialization debug logic with AXI SD cache and Wishbone transaction manager block-read debugging (`P3_SPI_SD_BLOCK_DEBUG`).

Build 65 hardware verification confirmed that the block-read transport operates correctly: on a cache miss, the bridge launched Wishbone commands, completed the block transaction, copied data to the RX FIFO, filled the cache, and returned AXI read responses carrying non-zero boot payload data from the SD card.

Build 66 is the first normal-boot retry on top of that validated transport. It keeps the Build 65 SPI-mode SD block-read hardware, explicit SD `IOBUF` boundary, original AXI16550 UART, DDR address translation, and compact four-ILA layout, but replaces the no-stack SD-probe bootrom with the normal C bootrom. The expected serial behavior is therefore GPT/BBL/Linux progress rather than Build 65's intentional repeated `A` loop. If Build 66 fails to reach Linux output, the existing ILA buses should first separate SD block response, DDR AXI response, and core/L15 progress before adding wider probes.

Build 66 hardware validation first reached the BBL layer. The PDI programmed successfully with `DONE bit: HIGH`, `/dev/ttyUSB0` produced the OpenPiton+Ariane banner, SPI-mode SD initialized, GPT parsing found the first payload partition, and the bootrom copied all 65,536 payload blocks. The bootrom readback check printed matching DDR and SD payload words (`DDR[0x80000000] = 0x340111731F80006F`, `SD[sect2048] = 0x340111731F80006F`) before entering `bbl loader` and dumping the debug DTB. This closed the basic UART, SD init, SD block read, DDR copy, and BBL-entry questions for the current board image.

A follow-up read of the full Build 66 UART log showed that Linux did in fact start: it printed `Linux version 5.1.0-rc7`, ran many `initcall_debug` entries, freed kernel memory, and executed `/init`. The active stop is now userspace rootfs initialization at `Initializing random number generator...`, after `Starting logging: OK`. Treat this as evidence that kernel entry, DTB/bootargs, early console, and normal console output are working well enough for kernel/userland progress. The next debug layer is rootfs init behavior, especially random-seed initialization on a minimal board with few entropy sources.

For that isolation step, `build/huaprop3/sd_images/huaprop3_linux_shell.img` patches the BBL embedded bootargs to `rdinit=/bin/sh init=/bin/sh`. After writing that image to the remote SD card and reinserting it into the P3 board, the same Build 66 PDI reached an interactive Linux shell. The UART log showed the forced bootargs in both the BBL DTB dump and the Linux kernel command line, Linux registered the AXI16550 console at `0xfff0c2c000`, and userspace reached `Run /bin/sh as init process` followed by the `/ #` prompt. Slow per-character input over `/dev/ttyUSB0` successfully ran `echo P3_SLOW_OK` and `uname -a`. Bulk UART writes caused `ttyS0 input overrun(s)`, so remote shell testing should throttle input. The remaining standard-image issue is therefore rootfs init policy around the random-seed step, not hardware transport, BBL/Linux handoff, kernel console, or basic userspace availability.

After the XSBench ext2-image validation, Build 66 became the canonical local baseline. The published artifacts are kept under `huaprop3_build66_baseline/debug_build/`, with future clean Vivado rebuilds directed to the repository-root `p3b66/` work directory by `scripts/p3_build66_normal_spi_sd_boot.tcl`. A complete copy of the previously validated `/mnt/d/p3b66` Vivado workspace is kept locally as `p3b66_validated_snapshot/` until a fresh repo-local rebuild and hardware boot test pass. Historical debug projects and old numbered Vivado workspaces were moved to archive directories outside the repository root; `huaprop3onecore/` remains available as the board-level reference project.

The validated benchmark image for this path is `build/huaprop3/sd_images/huaprop3_linux_xsbench_ext2.img` (192 MiB, SHA256 `9f51e506ce65aabeaf09db18a026adf9bbba2437bc05cbe653f8b625c27271ea`). It keeps the shell BBL payload in partition 1 and adds an ext2/no-journal partition 2 named `PITON_XSBENCH` containing the statically linked RISC-V `/XSBench` binary plus `/run_xsbench.sh`. The first ext3 image proved partition discovery but could hang in the ext3/ext4 journal mount path; the ext2 image mounted successfully on hardware.

```sh
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mkdir -p /proc /sys /mnt
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true

ls -l /dev/piton*
cat /proc/partitions

mount -t ext2 -o ro /dev/piton_sd2 /mnt
ls -l /mnt

/mnt/XSBench -s small -p 1 -l 1
```

Hardware validation reached Linux 5.1.0-rc7, enumerated `piton_sd1` and `piton_sd2`, mounted `/dev/piton_sd2` read-only as ext2 through the kernel's ext4 subsystem (`mounted filesystem without journal`), and launched `/mnt/XSBench -s small -l 100`. The XSBench v20 banner and input summary printed successfully. In this XSBench version, `-p <particles>` controls `Particle Histories` and defaults to `500000`; `-l <lookups>` controls history-based XS lookups per particle and defaults to `34` unless overridden. Use `-p 1 -l 1` for a shortest functional smoke test, then increase `-p` for longer runs.

If the driver exposes a different node name, first inspect `/dev/piton*` and `dmesg`. Keep using slow per-character UART input for commands; do not paste the benchmark command block as one bulk write. A common manual error is omitting the space between the block device and mount point: `mount -t ext2 -o ro /dev/piton_sd2 /mnt` is correct, while `/dev/piton_sd2/mnt` is parsed as one path and fails through `/etc/fstab` lookup.

Build 67 is the first 2x1 multicore expansion attempt from the Build 66 baseline. The Build 52/66 Vivado runner and PyHP regeneration path now accept `PITON_X_TILES`, `PITON_Y_TILES`, and `PITON_NUM_TILES` from the environment while defaulting to 1x1, so Build 66 remains the canonical single-core baseline. The Build 67 wrapper fixes those values at `2x1`, keeps the AXI16550 UART, SPI-mode SD, DDR address translation, and compact four-ILA debug shape, and publishes under `huaprop3_build67_2x1_baseline/debug_build/`. Per the current workspace policy, its Vivado work project defaults to the repository-local `p3b67_2x1/` directory rather than a D-drive workspace. The matching XSBench image path is `build/huaprop3/sd_images/huaprop3_linux_xsbench_2x1.img`; it embeds a 2-hart DTB in the forced AXI16550 BBL and keeps the shell bootargs (`rdinit=/bin/sh init=/bin/sh`) so the first Linux SMP validation can reach `/ #` before mounting `/dev/piton_sd2` and running `/mnt/XSBench -s small -p 1 -l 1 -t 2`.

Build 67 implementation completed on 2026-06-05 after the runner was fixed to regenerate `define.tmp.h` together with the 2x1 PyHP topology RTL. The generated PDI/LTX are `huaprop3_build67_2x1_baseline/debug_build/p3_top_build67_2x1_normal_spi_sd_boot.pdi/.ltx`; route completed with 258,405 fully routed nets, 0 routing errors, and final timing met all user constraints (`WNS=16.312 ns`, `WHS=0.005 ns`). Hardware validation is still pending, so Build 66 remains the validated single-core baseline until Build 67 proves debug-hub access, UART boot, SD/DDR handoff, and Linux SMP behavior on the board.

The first Build 67 hardware run proved the 2x1 bitstream through BBL entry. PDI programming succeeded with `DONE bit: HIGH`, the LTX refreshed all four ILAs through debug hub `0x3ffc0000000`, and UART log `ttyUSB0_20260605_175423_b67.log` showed the bootrom completing SPI-mode SD init, GPT parsing, all 65,536 payload-block reads, DDR copy, and DDR/SD readback comparison before entering `bbl loader`. The BBL DTB printed by the board still listed only `cpu@0`, while local inspection of `huaprop3_linux_xsbench_2x1.img` shows `cpu@1` is present. Therefore the active blocker for Linux/SMP validation is SD card image mismatch, not Build 67 PDI, UART, SPI SD, DDR copy, or debug-hub access.

After writing the intended 2x1 SD image and retesting on 2026-06-08, Build 67 cleared that stale-image blocker. UART log `ttyUSB0_20260608_195222_b67_retest.log` printed the 2x1 bootrom banner, completed the full 65,536-block SD-to-DDR payload copy, reported matching DDR/SD payload words, entered `bbl loader`, and dumped a DTB containing both `cpu@0` and `cpu@1` with two-hart CLINT/PLIC interrupt wiring. A later full-log review corrected the earlier "no Linux banner" interpretation: the same log contains `Linux version 5.1.0-rc7` and reaches `Run /bin/sh as init process`. Treat Build 67 as past BBL-to-Linux entry; the next validation gate is shell interaction, CPU topology, SD partition mount, and a 2-thread XSBench smoke run.

The next discriminator is SD-image-only. `scripts/p3_make_build67_linux_handoff_images.sh` emits `huaprop3_linux_xsbench_2x1_nosmp.img` and `huaprop3_linux_xsbench_2x1_bbl_markers.img` from the same base XSBench ext2 image and existing Build 67 BBL payload. The `nosmp` variant keeps the 2x1 bitstream but marks `cpu@1` disabled in the embedded DTB and adds `maxcpus=1 nosmp` to bootargs; BBL's hart filter should then mask hart1 before Linux entry. The `bbl_markers` variant keeps both harts visible, disables the long DTB dump, and prints `B67M` markers before entry selection, per-hart handoff, and `mret`. Verified image hashes are `714e07231ebb85c83bb9c89e5233fd801182a6523ce311530e03238f5e31241d` for `huaprop3_linux_xsbench_2x1_nosmp.img` and `048904f50e8ed101f4b595de7cbfa2936e6924e460e57113165454832be54911` for `huaprop3_linux_xsbench_2x1_bbl_markers.img`. Test `nosmp` first: if it reaches `Linux version` or `/ #`, the active problem is SMP/hart1/CLINT/PLIC/SBI behavior. If it still fails, test `bbl_markers` to distinguish failure before `mret`, at Linux entry, or in early console. For marker images, verify the image partition itself, not just the BBL binary, because an old image can still contain the previous payload even after a successful marker BBL build.

The `nosmp` hardware discriminator was tested on 2026-06-08 with the unchanged Build 67 PDI/LTX. The bootrom again completed SPI-mode SD init, GPT parsing, the full 65,536-block DDR payload copy, and DDR/SD payload word comparison before entering BBL. The printed BBL DTB confirmed the intended payload: bootargs included `maxcpus=1 nosmp`, and `cpu@1` had been rewritten to `status = "masked"`. The run still stopped before any `Linux version` banner or shell prompt, with the same high-bit/garbled bytes after the BBL DTB dump. Therefore the active fault is not simply "Linux tries to bring up hart1"; continue with the `bbl_markers` image to identify whether BBL reaches entry selection and `mret`, and whether control reaches Linux entry but early console never prints.

The `bbl_markers` hardware discriminator was tested on 2026-06-09 with the same Build 67 PDI/LTX. UART log `ttyUSB0_20260609_093656_b67_bbl_markers.log` again cleared the bootrom, SPI-SD, GPT, DDR payload-copy, and BBL-entry path, then printed `B67M boot_loader dtb_in=0x0000000080006708 dtb_out=0x0000000081000000 disabled=0x0000000000000000` and `B67M mret hart_arg=0x0000000000000000 entry=0x0000000080200000 dtb=0x0000000081000000`. The same complete log also contains `Linux version 5.1.0-rc7`, so this proves BBL selects hart0, places the final DTB at `0x81000000`, executes `mret` into the Linux payload at `0x80200000`, and Linux early console prints. A later board-only retest, `ttyUSB0_20260609_103059_b67_retest.log`, still used the marker payload and reached the same `B67M mret` point, but this individual capture ended in high-bit bytes without a stable Linux banner. A follow-up slow-input probe on 2026-06-10 sent `CR`, `echo P3_B67_INPUT_TEST`, and `uname -a` at `115200 8N1`; the fresh log stayed empty, so the current state is not an interactable shell with merely scrambled output. Treat this as a runtime/image-validation gate, not a reason to resynthesize hardware: first rewrite the normal `huaprop3_linux_xsbench_2x1.img` to the SD card, then rerun the long UART capture and slow shell-input test for `uname -a`, CPU topology, `/dev/piton_sd2` mount, and `/mnt/XSBench -s small -p 1 -l 1 -t 2`.

The keep-divisor SD-image discriminator was tested on 2026-06-10 with the unchanged Build 67 PDI/LTX. The image SHA256 was `2fd755442425b508c787ff1b1e601f56dc90a52ea9b49215788e1a4b35f3a980`, and the remote SD-card readback matched. Its embedded bootargs keep `console=ttyS0,115200n8 rdinit=/bin/sh init=/bin/sh` but remove the explicit `,115200n8` baud option from `earlycon=uart8250,mmio,0xfff0c2c000`. The board again cleared programming, debug hub refresh, SPI-SD init, GPT parsing, 65,536-block DDR payload copy, and DDR/SD word comparison. Unlike the previous marker retest, UART output after BBL was stable ASCII: the log printed `Linux version 5.1.0-rc7` and `smp: Brought up 1 node, 2 CPUs`. The run then stopped after `RPC: Registered tcp NFSv4.1 backchannel transport module.` and did not reach `/ #`; a slow `echo P3_KEEP_DIV_PROBE` input produced no echo. This narrows the active Build 67 gate past BBL `mret`, Linux entry, early UART output, and 2-hart bring-up. The next software-only image should add `keep_bootcon loglevel=8 initcall_debug` to distinguish a real kernel stall after RPC init from a console handoff/output loss.

#### Multicore Linux Boot Notes

Do not treat a 2x1-only Linux boot failure as proof that the shared UART, SD path, or DDR path regressed. Build 67 keeps the Build 66 AXI16550 UART, SPI-mode SD transport, DDR address translation, and debug-hub shape; the new variables are the 2-hart DTB, BBL `MAX_HARTS=2` path, secondary-hart wakeup, and Linux SMP initialization. A single-core boot exercises one hart from bootrom through BBL and Linux, so early console output, normal 8250 console registration, timer interrupts, SBI calls, and shell input are effectively serialized. A multicore boot makes Linux parse two CPU nodes, CLINT/PLIC interrupt wiring for both harts, and per-hart timebase data, then starts CPU1 and begins using SMP scheduler, RCU, IPI/timer, and console-lock paths that were not active in the 1x1 shell validation.

The concrete Build 67 code-path suspicion is now in BBL/SBI, not at the RPC line itself. In `riscv-pk/machine/minit.c`, `init_first_hart()` calls `wake_harts()` before `boot_loader()` sets the global Linux `entry_point`; secondary harts therefore wait inside `boot_other_hart()` and may enter the Linux payload as soon as `entry_point` becomes nonzero. Linux then uses its early hart lottery to choose the boot CPU. The keep-divisor hardware log printed `riscv_timer_init_dt: Registering clocksource cpuid [0] hartid [1]`, which means Linux CPU0 was hart1 in that run. That ordering is legal on some RISC-V systems, but it is a real 2x1-only discriminator here because it immediately exercises BBL's per-hart `HLS()->timecmp`, `OTHER_HLS(hart)->ipi`, `SBI_SET_TIMER`, `SBI_SEND_IPI`, and remote fence paths. The single-core Build 66 path cannot expose this class of bug because there is no secondary hart racing into Linux and no cross-hart SBI wait loop.

Use `scripts/p3_make_build67_sbi_trace_image.sh` for the next discriminator. It preserves the stable keep-divisor earlycon form, adds `keep_bootcon loglevel=8 ignore_loglevel initcall_debug`, and embeds `B67S` BBL markers around `entry_point` selection, per-hart Linux entry, `SBI_SET_TIMER`, and `send_ipi_many()`. The first generated image hash is `7bb6ed65ff3bf7e6b1baf3dc067fd32c52faa758a0023a3440e6550f44694543`. If a hardware log shows `B67S ipi_wait` repeating, focus on the target hart failing to clear its CLINT MSIP/HLS IPI state or on BBL's hart-mask mapping. If the `B67S` SBI markers continue past the previous RPC point but the UART still goes quiet, focus on console handoff/output loss after normal 8250 registration. If delaying nonzero harts makes Linux CPU0 become hart0 and boot farther, the root cause is the BBL-to-Linux boot-hart lottery ordering.

The SBI trace image is expected to answer five specific questions. First, `B67S entry_point_set`, `B67S linux_entry_ready`, and `B67S linux_enter` identify which hart actually crosses from BBL into Linux first; this diagnoses a BBL-to-Linux boot-hart ordering problem, not a UART or SD problem. Second, `B67S set_timer hart=... timecmp=...` confirms whether each active hart reaches the SBI timer path and whether BBL is programming the expected per-hart CLINT `mtimecmp` pointer. Third, `B67S ipi_enter`, `B67S ipi_wait`, and `B67S ipi_wait_done` distinguish a real SBI IPI/remote-fence deadlock from later kernel init progress: a repeated `ipi_wait` means the sender is waiting for another hart's HLS/MSIP state to clear. Fourth, Linux `initcall_debug` output after the old RPC/NFS line tells whether the kernel is still advancing and only the shell/console path is delayed. Fifth, `keep_bootcon` keeps early console output alive across normal 8250 registration, so a silent log after clean `B67S` progress points toward console handoff/output loss rather than BBL/SBI deadlock. This image cannot by itself prove a final RTL bug; it narrows the failing software-visible contract so the next RTL or firmware change has a concrete target.

The SBI trace hardware run on 2026-06-10 answered that question: the RPC/NFS line was not the final stop. UART log `~/p3_uart_logs/ttyUSB0_20260610_210818_sbi_trace_continue.log` shows `B67S linux_entry_ready hart=0` and `B67S linux_enter hart=0`, then Linux 5.1.0-rc7, `riscv_timer_init_dt: Registering clocksource cpuid [0] hartid [0]`, and `smp: Brought up 1 node, 2 CPUs`. After `RPC: Registered tcp NFSv4.1 backchannel transport module.`, `initcall init_sunrpc` returned, `populate_rootfs` completed after roughly 30 seconds, `serial8250_init` registered the AXI16550 at `0xfff0c2c000`, and `/bin/sh: can't access tty; job control turned off` printed. That means the current Build 67 software-visible path is through shell launch, not stuck in early BBL entry, Linux SMP bring-up, or the SunRPC initcall itself.

The remaining suspicious code path is narrower. In BBL `mtrap.c`, Linux `SBI_REMOTE_FENCE_I` maps to `IPI_FENCE_I=0x2` and calls `send_ipi_many()`. The trace log contains many `B67S ipi_enter ... event=2 ... mepc=0xffffffe000695c5a` records plus `ipi_wait_done`, but no long `B67S ipi_wait` records with `target_msip` snapshots. Therefore this run does not prove a CLINT/MSIP or HLS remote-fence deadlock: the sender sees the target IPI state clear. The practical next step is not another Vivado build; it is a lower-noise shell-validation image or a throttled trace mode, because the current `B67S` print volume itself can swamp the single UART while testing `/bin/sh` input. A slow `echo P3_B67_SBI_TRACE_OK` plus `uname -a` write did not appear in the same capture, so Build 67 is not yet promoted to an interactable shell/XSBench milestone.

The lower-noise follow-up is `scripts/p3_make_build67_clean_delay_image.sh`. It generates `huaprop3_linux_xsbench_2x1_clean_delay.img` by reusing the keep-divisor 2-hart DTB and adding only the nonzero-hart delay in BBL `boot_other_hart()`; it intentionally removes `B67S` prints and does not add `keep_bootcon`, `ignore_loglevel`, or `initcall_debug`. The first generated image hash is `7936040478b26de64c54b6104469bb35bd5276b46d041be3ce3f17a4abce0241`, with BBL hash `189e0204bdae33192bdef48f8c8c93b03d76f5029b05ee85453ade181cf4611f`. This is the right image for the next shell test because it isolates the candidate timing change from the trace traffic: if it reaches an interactive `/bin/sh`, keep the delay and then reduce or replace it with a cleaner hart-release policy; if it regresses to the RPC/console symptom, the SBI trace result was primarily exposing hidden progress through `keep_bootcon/initcall_debug`.

The clean-delay hardware run on 2026-06-10 took the second branch. The SD readback matched image SHA256 `7936040478b26de64c54b6104469bb35bd5276b46d041be3ce3f17a4abce0241`, the unchanged Build 67 PDI/LTX programmed successfully, and UART log `~/p3_uart_logs/ttyUSB0_20260610_215853_clean_delay.log` again showed BBL entry, Linux 5.1.0-rc7, and `smp: Brought up 1 node, 2 CPUs`. The log stopped at `RPC: Registered tcp NFSv4.1 backchannel transport module.`, did not grow after 22:10:05 CST, and slow `echo P3_CLEAN_DELAY_OK`/`uname -a` input produced no response. Therefore the nonzero-hart delay alone is not the root fix. The trace image's ability to show `initcall init_sunrpc` return, `serial8250_init`, and `/bin/sh` was primarily due to its retained boot console and initcall visibility, not just the hart-delay change. The next low-noise test should keep `keep_bootcon loglevel=8 initcall_debug` while removing the high-volume `B67S` BBL/SBI prints.

The relevant Linux code path confirms this interpretation. Buildroot is configured to build `https://github.com/pulp-platform/linux.git` at `ariane-v0.7`; in that tree `net/sunrpc/sunrpc_syms.c` registers `init_sunrpc` as an `fs_initcall`, and `include/linux/init.h` orders `rootfs_initcall` before `device_initcall`. The next major built-in step after the SunRPC line is therefore `init/initramfs.c:populate_rootfs()`, followed by device initcalls such as `drivers/tty/serial/8250/8250_core.c:serial8250_init()`. The normal 8250 console handoff is also explicit: `kernel/printk/printk.c:register_console()` unregisters boot consoles when a real preferred console enables unless `keep_bootcon` is set. On this platform the early console and real console point at the same AXI16550 MMIO device (`uart@fff0c2c000`), so a failure or stall after the real console path enables can make the last visible clean-image line look like SunRPC even if the CPU has progressed. `initcall_debug` adds before/after printk records around each initcall, which is why the trace image could prove `init_sunrpc` returned and later code ran.

The keep-divisor result suggests the earlier high-bit UART stream was not a physical UART pin failure. Removing the explicit baud from `earlycon=uart8250,mmio,0xfff0c2c000,115200n8` left the bootrom/BBL-programmed divisor alone long enough for stable Linux ASCII output and 2-hart bring-up. The likely explanation is a fragile console handoff or timing assumption exposed by the SMP path: the early console and real 8250 driver share one AXI16550 instance, while multiple harts can now emit SBI/printk traffic and take interrupts around the same transition. In 1x1, the same baud/divisor choice can appear safe because only one hart is printing and the handoff ordering is simpler. In 2x1, keep `earlycon=uart8250,mmio,0xfff0c2c000` without a baud suffix until the handoff is fully understood, preserve `console=ttyS0,115200n8`, and use `keep_bootcon loglevel=8 initcall_debug` for debug images so output loss can be separated from a real kernel stall.

The concrete correction sequence is now software/DTB first. The RTL instantiates the PLIC through `riscv_peripherals` with `NumSources=2`, and the chipset wires `irq_sources = {net_interrupt, uart_interrupt}`; PLIC source ID 1 is UART and source ID 2 is network. Therefore every newly generated Build 67 2x1 DTB must advertise `riscv,ndev = <2>`, even if the immediate Linux image only binds the UART. Linux's `drivers/irqchip/irq-sifive-plic.c` reads `riscv,ndev`, allocates an IRQ domain of `nr_irqs + 1`, and initializes source enables up to that value. Keeping `riscv,ndev = <1>` leaves the software-visible interrupt controller smaller than the hardware instance and is not an acceptable baseline for debugging the 8250 RX/TTY path.

The short-term test/fix image is `scripts/p3_make_build67_low_noise_console_image.sh`. It keeps the nonzero-hart delay from the clean-delay experiment, removes the high-volume `B67S` SBI prints, preserves the keep-divisor earlycon form, fixes the DTB PLIC source count, and adds `keep_bootcon loglevel=8 ignore_loglevel initcall_debug`. Passing this image to an interactable `/bin/sh` would mean the board is not stuck at RPC and the immediate workaround is to keep the boot console alive through 8250 handoff while validating shell input and XSBench. The long-term fix is stricter: remove `keep_bootcon` and `initcall_debug` only after the normal 8250 OF probe, PLIC source 1 interrupt delivery, `register_console()` handoff, and slow UART input all work without hidden early-console assistance.

For future multicore Linux bring-up, validate these as a set before blaming the RTL: the embedded BBL DTB must list every intended `cpu@N`, `timebase-frequency` must match the FPGA clocking, CLINT and PLIC `interrupts-extended` must cover each hart context, BBL must mask only intentionally disabled harts, the SD card must contain the matching 2-hart image rather than a stale 1-hart payload, and UART input tests must stay throttled because bulk writes can still overrun `ttyS0`. A `nosmp` image is useful to isolate Linux SMP policy, but it does not reproduce the exact 1x1 environment: it still boots through a 2x1 bitstream, a 2-hart-capable BBL, and a DTB/firmware path that has been modified to mask CPU1.

The 2026-06-11 low-noise hardware run resolved the RPC/console ambiguity and exposed the next multicore failure. With keep-divisor earlycon, `keep_bootcon`, `ignore_loglevel`, and `initcall_debug`, Linux brought up both CPUs, returned from `init_sunrpc`, completed the approximately 30-second `populate_rootfs`, registered the OF 8250 device as `ttyS0` with IRQ 1, and executed `/bin/sh`. Because the boot console and normal console both target `0xfff0c2c000`, every printk appears twice after the normal console enables; this is expected diagnostic behavior, not evidence of duplicate kernel execution. The first real failure is a repeated `rcu_sched` stall on CPU1, where the task dump shows `sh` in `sys_read -> __schedule`. A genuinely throttled UART command receives no response after that point.

This result also gives a code-path-specific timer clue. The generated Build 67 snapshot instantiates `riscv_peripherals` with `NumHarts=2`; `clint.sv` implements `mtimecmp_q[0:1]` and derives `timer_irq_o[i]` from `mtime >= mtimecmp[i]`; `chip.tmp.v` connects index 0 to tile0 and index 1 to tile1. BBL derives each `HLS()->timecmp` pointer as `CLINT_BASE + 0x4000 + hart_index * 8`, and `mcall_set_timer()` writes that pointer before enabling the machine timer interrupt. The earlier SBI trace proves both harts initially use this path, but hart1 stops logging `SBI_SET_TIMER` after sparse count `0x0c01` while hart0 continues through at least `0xec01`. The evidence therefore does not support a simple missing second-hart vector or DTB entry; it points to hart1 ceasing to receive, redirect, handle, or rearm timer events during later Linux execution.

For the next correction, instrument the dynamic timer chain rather than adding more general printk traffic: CLINT `mtimecmp_q[1]` writes, `timer_irq_o[1]`, tile1 `time_irq_i` after synchronization, CVA6 `mip.MTIP`/machine-trap entry, BBL's timer redirect to supervisor mode, and the following hart1 `SBI_SET_TIMER`. The decisive split is whether `mtimecmp[1]` expires without reaching tile1, reaches machine mode without a supervisor timer handler, or reaches Linux once and fails to request the next event. Keep the low-noise console arguments until this chain is fixed; removing `keep_bootcon` would only hide the RCU evidence again.

The timer conclusion requires two corrections after checking the exact code and trace chronology. First, RISC-V `dump_cpu_task()` prints the saved stack of the remote CPU's current task; it is not a live register capture. Therefore the repeated `__schedule+0x1b4` frame does not prove that CPU1 is spinning at that instruction. Second, the SBI trace logs only the first eight `SBI_SET_TIMER` calls and every 1024th call. Hart1 can legitimately stop producing these sparse markers while Linux has stopped its periodic tick in idle, so the last `0x0c01` marker is not by itself proof that CLINT timer delivery failed.

The stronger evidence is the RCU task flag and later SBI activity. In this kernel `_TIF_NEED_RESCHED` is bit 3, and both CPU1 task dumps show flags `0x00000008`; CPU1 has been asked to reschedule but still has not completed that transition 63 seconds later. The earlier trace also shows hart1 issuing `SBI_SEND_IPI` during `pty_init` at roughly 35.9 seconds, long after the last sparse timer marker near 3 seconds, so hart1 did not permanently stop at `SBI_SET_TIMER` count `0x0c01`. The unresolved fault is now CPU1 forward progress across interrupt delivery and scheduling, with three concrete branches: MTIP/MSIP fails to reach M-mode, BBL raises STIP/SSIP but Linux does not handle or clear it, or Linux reaches the scheduler but a shared-memory/atomic coherence operation does not complete.

The next firmware image must therefore report per-hart chain counters instead of only SBI call counts. Count machine-timer trap entries before BBL raises STIP, machine-software trap entries before BBL raises SSIP, Linux `SBI_CLEAR_IPI` calls, `SBI_SEND_IPI` source and target counts, and `SBI_SET_TIMER` rearms. Hart0 can print a low-frequency snapshot of both harts so the diagnostic still reports hart1 state after hart1 stops making SBI calls. If hart1 MTIP stops while its compare has expired, inspect CLINT-to-tile1 delivery; if MTIP advances but timer rearm does not, inspect STIP delegation and Linux timer handling; if hart0 sends MSIP and hart1 receives it without clearing SSIP, inspect the supervisor IPI handler; if all interrupt counters advance while `_TIF_NEED_RESCHED` remains set, move the primary suspect to scheduler atomics and OpenPiton cache coherence.

`scripts/p3_make_build67_irq_chain_trace_image.sh` implements that discriminator without a Vivado rebuild. Its BBL machine-trap instrumentation increments per-hart MTIP and MSIP counters before the existing redirect logic, and its SBI instrumentation counts timer rearms, `SBI_CLEAR_IPI`, and software IPI sends in each direction. Hart0 emits a `B67I irq_snapshot` only on the existing 1024-call timer sampling interval. Read the fields as a chain: `send01 -> ms1 -> clear1` is the CPU0-to-CPU1 software-interrupt path, while `mt1 -> set1` is the CPU1 timer-interrupt/rearm path. A break between adjacent counters identifies the first failing ownership boundary.

The 2026-06-11 hardware run found that break. Linux completed SMP bring-up and launched `/bin/sh`, then CPU1 repeatedly stalled with `_TIF_NEED_RESCHED`. The high-volume `event=2` records were identified from the raw kernel image rather than inferred from their timing: return PC `0xffffffe000695c5a` is immediately after the `a7=5` ecall in `flush_icache_pte()`. Linux 5.1 implements SMP `flush_icache_all()` as `sbi_remote_fence_i(NULL)`, and `flush_icache_pte()` invokes it when `PG_dcache_clean` is first set for an executable page. Thousands of these calls while the initramfs and shell executable pages are mapped are noisy but expected; they stop before the persistent RCU stall. Also note that `clear0/clear1` and `send01/send10` count only supervisor software-IPI operations, not remote fence events, so they must not be used to claim that a fence event failed to clear SSIP.

The stronger timer evidence is that hart1's `set1` counter stops at 5266 while `mt1` continues from 6144 to at least 38912. The MTIP counter is incremented only after BBL `mentry.S` decodes `mcause` as `IRQ_M_TIMER`; the next instructions clear `mie.MTIE` and raise `mip.STIP`. Without a later hart1 `SBI_SET_TIMER`, MTIE should remain disabled, so a second MTIP entry should not occur. Treat this as a precise RTL/CSR boundary, not yet as a final named bug: record incoming and post-clear `mie`, `mip`, `mcause`, `mepc`, and `mstatus`, and count MTIP entries observed with incoming `mie.MTIE=0`. If that counter advances, inspect CVA6 interrupt qualification and per-hart CSR state. If incoming MTIE remains set despite the preceding `csrc`, inspect CSR write/restore behavior. If the cause is not actually machine timer in the stored raw CSR, inspect interrupt cause encoding and tile1 interrupt routing.

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

## 12. P3 SPI SD Debug Builds 59-64

Build 59 tested the smallest protocol-level fix after Build 58: OpenCores `rwspi_wire_data` now drives MOSI/CMD high during reset and idle wait states, matching the standalone Build 56 reference-SPI probe. The hardware result confirmed the fix at the pin-observation level (`spi_mosi=1`, `spi_cs_n=1`) and kept the proven AXI16550 UART path, but `miso_low_seen` was still zero.

The Build 59 capture also showed why another ordinary current-state capture would be ambiguous: the live initializer state was `POWER_WAIT`, while sticky status still showed a previous SPI init error. Build 60 therefore adds `P3_SPI_SD_HISTORY_DEBUG` rather than changing pin maps or boot flow. The existing SD ILA bus is repacked as `{init_history, send_cmd_history}` so one capture can tell whether `init_sd_p3` ever reached `CMD0_SEND/CMD0_WAIT` after reset and whether the OpenCores `send_cmd` block actually queued command bytes. If Build 60 records command progress but no MISO low transition, the remaining gap is no longer reset, UART, NoC, Wishbone, or high-level SD init sequencing; it is the OpenCores byte-FIFO command/response timing versus the known-good Build 56 bit-banged SPI sequence.

Build 60's raw CSV showed `send_cmd` in response-wait states with `tx_count=62/63`, so the next build should not assume the command sender is idle. Build 61 adds `P3_SPI_SD_PAD_DEBUG` and repacks the SD ILA bus as `{captured_bit_count[5:0], first_56_mosi_bits[55:0], capture_active, spi_cs_n}`. The key comparison is whether the first CS#-low window contains `0xff400000000095`, which is the OpenCores pre-response idle byte followed by CMD0. This keeps the proven AXI16550 UART, NoC/Wishbone path, reference SPI pin map, and bootrom stimulus fixed while deciding whether to target the byte/FIFO wire engine or the external card-response boundary.

Build 61 hardware confirmed the OpenCores command launch at the internal pad observation point: the capture reported `cmd_bit_count=56` and `cmd_mosi56=0xff400000000095`. The card response was still absent (`miso_low_seen=0`). This closes the byte-order and first-command launch questions for CMD0. Future builds should avoid broad boot-flow changes and focus on the physical response boundary: exact MISO input sampling, CS#/SCK idle timing, and differences from the Build 56 reference-SPI probe that already saw a response on the same board/card path.

Build 62 moves the known-good Build 56 SPI command sequencer into the full OpenPiton SD wrapper under `P3_SPI_SD_REF_CMD_DEBUG`. In this mode the full shell, constraints, BD debug hub, AXI16550 UART, bootrom stimulus, and SD top-level pads remain in place, but the SD pad drivers are temporarily muxed from the reference bit-banged CMD0/CMD8 engine. A passing Build 62 means the external card path is reachable in the full shell and the next fix should target OpenCores SPI CS/SCK/MOSI/response timing. A failing Build 62 means the problem is not OpenCores byte order; it is full-shell pad, power, reset, or top-level SD control integration.

Build 62 routed successfully but failed at `write_device_image` with Versal DRC `AVAL-352` because top-level tristate assignments on `sd_cmd` and `sd_dat[3]` inferred `OBUFT` cells driving `inout` ports. Build 63 keeps the same reference-SPI boundary test and AXI16550 path, but makes the SD pad boundary explicit: `piton_spi_sd_top.v` instantiates `IOBUF` for `sd_cmd` and every `sd_dat` bit, drives internal output/enable nets, and samples the card through internal input nets. This removes the bitgen DRC as a variable before interpreting the reference-SPI full-shell result.

Build 63 hardware passed the full-shell reference-SPI boundary test. The PDI programmed with `DONE bit: HIGH`, the LTX reached the AXI debug hub at `0x3ffc0000000`, and the SD reference debug bus decoded as `tag=0x63`, `state=PASS`, `miso_seen=1`, `pass=1`, `fail=0`. That result closes the board-level SD route for the current PHC wiring: power/control, explicit `IOBUF` pads, constraints, JTAG/XVC/debug hub, and the full OpenPiton shell can all support an SD card response. Build 64 therefore stops using the reference debug mux and returns to the normal OpenCores SPI SD path, keeping the explicit `IOBUF` pad boundary and the history-debug probes. If Build 64 still fails with `miso_low_seen=0`, the next fix should target OpenCores command/response timing and MISO sampling rather than UART, SD pins, power, or the debug infrastructure.

Build 64 hardware passed that normal-path discriminator. It implemented from `D:/p3b64`, programmed with `DONE bit: HIGH`, refreshed the four-ILA LTX through AXI debug hub `0x3ffc0000000`, and decoded `PASS: Build 64 normal OpenCores SPI SD path saw command progress and card response`. The capture recorded NoC and Wishbone handshakes, `spi_clk_toggle_seen=1`, `miso_low_seen=1`, `resp_tout=0`, and `init_state_seen` through `CMD0`, `CMD8`, `CMD55`, `ACMD41`, and `INIT_DONE`. This narrows the remaining boot work past the SD physical/command-response boundary: keep the original AXI16550 UART and explicit SD `IOBUF` boundary, then debug the later SPI block-read data path and bootrom/BBL handoff rather than revisiting SD pins, power, XVC, or the first-card-response timing.

Build 65 implements that next discriminator without widening the debug footprint. It keeps the Build 64 physical and protocol baseline, but replaces the SD ILA payload with `P3_SPI_SD_BLOCK_DEBUG` signals from `axi_sd_bridge` and `sd_wishbone_transaction_manager`. The 16-bit sticky vector now tracks AXI AR acceptance, SD block request launch, transaction-manager acceptance, block transaction type/control writes, status completion, error-register read, RX byte copy, cache write, transaction DONE, bridge response, SEND_RESP, AXI R response, and nonzero data observation. The 64-bit SD bus records the current AXI SD bridge state, a 10-bit AXI state history, selected-cache validity flags, the transaction-manager state/after-state/counters, the last Wishbone data byte, success/response/ready flags, and the DONE sticky. If Build 65 reaches AXI read response with no SD read error, the remaining failures are above the SD block-read transport layer: SD image contents, GPT/BBL handoff, bootrom copy/cache behavior, or later UART logging. If it stalls earlier, the missing sticky bit identifies the specific handoff between NoC, AXI SD bridge, transaction manager, OpenCores SPI status/RX FIFO, cache fill, and NoC response.

Build 65 hardware passed this discriminator. The PDI generated from `D:/p3b65` programmed with `DONE bit: HIGH`, the LTX refreshed the debug hub at `0x3ffc0000000`, and all four ILA CSVs exported. The decoded sticky vector was `0xfeff`: AXI AR, SD request launch, transaction-manager request, block transaction type/control writes, status done, RX-byte/cache-write activity, transaction DONE, bridge response, `SEND_RESP`, AXI R response, and nonzero data were all observed, while `tm_read_error_seen` remained clear. The live SD block bus ended in `axi_state=RDY`, `after_state=R_DATA_WORD`, `sd_resp_succ=1`, and `last_rdata8=0xf0`. This means the current boot stop is no longer below the mapped SD block-read transport. The next builds should avoid revisiting UART hardware, SD pins, card power, first SPI response, or AXI response plumbing, and instead instrument what the bootrom does with the returned sectors: LBA values, GPT/header checks, BBL copy destination/counts, branch target, exceptions, and UART writes after the SD handoff.
