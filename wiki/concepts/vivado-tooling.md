# Vivado Tooling

Synthesis and implementation scripts, tips, and known issues.

## Vivado Version & Path

- **Version**: Vivado 2024.2
- **Windows path**: `D:\Xilinx\Vivado\2024.2`
- **WSL wrapper**: `/home/illya/bin/vivado` (converts paths, forwards env vars, calls `vivado.bat` via `cmd.exe`)

## Build Flow

### AX7203 (protosyn, command-line)

```bash
protosyn -b a7203x -d system --core=ariane --uart-dmw ddr
```

Vivado runs on Windows, invoked from WSL via the wrapper above.

### P3 / Versal VP1902 (Block Design + TCL scripts)

P3 uses a Vivado Block Design flow (not protosyn). Three scripts in `scripts/`:

| Script | Purpose | Vivado mode |
|--------|---------|-------------|
| `p3_build_bitstream.tcl` | Synthesis → Implementation → PDI generation | `-mode batch` |
| `p3_program.tcl` | Program P3 via remote hw_server at `100.93.77.36:3121` | `-mode batch` |
| `p3_debug.tcl` | Connect ILA, load probes, open interactive debug console | `-mode tcl` |

```bash
vivado -mode batch -source scripts/p3_build_bitstream.tcl   # build
vivado -mode batch -source scripts/p3_program.tcl            # program
vivado -mode tcl   -source scripts/p3_debug.tcl              # debug
```

Note: Versal outputs `.pdi` (not `.bit`). ILA probes use `.ltx` files.

### P3 UART Smoke Tests

Two isolated UART smoke tests compare the current OpenPiton top-level style with the reference project's BD-externalized UART style:

| Script | UART route | Expected serial text |
|--------|------------|----------------------|
| `p3_uart_direct_build.tcl` | Pure RTL top-level `uart_tx/uart_rx` outside any BD | `DIRECT` |
| `p3_uart_bd_build.tcl` | Minimal BD wrapper with external ports `uart_txd/uart_rxd` | `BDPATH` |

Both use the same physical pins (TX=CW58, RX=CW59) and the P3 100 MHz differential system clock (CE6/CF6) through a small RTL `IBUFDS` helper. The BD-path smoke test intentionally avoids Clock Wizard/proc_sys_reset IP so Vivado OOC IP synthesis cannot obscure the UART-routing result. DDR, SD, and OpenPiton are not part of either test. Program either result with:

```bash
vivado -mode batch -source scripts/p3_program_pdi.tcl -tclargs <path-to-pdi>
```

The smoke-test build scripts create the Vivado project under Windows `%TEMP%` and then copy the generated PDI back into the repository output directory. This keeps the standard `launch_runs ... -to_step write_device_image` Versal flow, but avoids running Vivado's generated `rundef.js` launcher from a WSL network-mounted `.runs` directory.

Current build status:

| Date | Route | Result | Notes |
|------|-------|--------|-------|
| 2026-05-25 | Direct `uart_tx/uart_rx` | Serial verified | `DIRECT` observed after programming `huaprop3_uart_direct/p3_uart_direct.runs/impl_1/p3_uart_direct_top.pdi`, WNS 7.242 ns, 0 routing errors |
| 2026-05-25 | BD `uart_txd/uart_rxd` | Serial verified | `BDPATH` observed after programming `huaprop3_uart_bd/p3_uart_bd.runs/impl_1/p3_uart_bd_wrapper.pdi`, WNS 7.603 ns, 0 routing errors |

### P3 Standalone AXI UART16550 Interaction Test

The standalone UART16550 interaction test isolates the exact UART IP used by the OpenPiton P3 path. It excludes OpenPiton, Ariane, DDR, SD, NoC, bootrom, and LEDs, then instantiates the native Xilinx `axi_uart16550` with the same 30 MHz AXI clock and register mapping used in `uart_top.v`.

The testbench hardware is a small AXI-Lite master FSM. It initializes the 16550 registers with the project settings (`DLL=16`, `DLM=0`, `LCR=0x03`, `FCR=0x07`, `MCR=0x00`), sends a ready banner, polls `LSR[0]` for received bytes, reads `RBR`, waits for `LSR[5]`, and writes the byte back to `THR`. A BD-owned ILA captures sticky status, the latest AXI transaction snapshot, `LSR`, and UART RX/TX levels so the serial echo result can be correlated with the IP-level AXI handshakes.

Implementation note: keep this standalone project in a very short Windows-visible work directory. The default script path is `C:/p3u16550`, and it can be overridden with `P3_UART16550_WORK_DIR`. The first run used `%TEMP%/openpiton_p3_uart16550_ila_interact`; synthesis passed, but `impl_1/opt_design` failed when Vivado generated the Versal `axi_dbg_hub` and debug AXI NoC child project because the nested path exceeded Windows' 260-byte limit.

Hardware result: the short-path build completed and published `huaprop3_uart16550_ila_interact/debug_build/p3_uart16550_ila_interact.pdi` plus `.ltx`. Programming reported `DONE bit: HIGH`; Hardware Manager reached the debug hub at `0x3ffc0000000`, armed/uploaded `u_bd/p3_uart16550_dbg_bd_i/axis_ila_0`, and exported CSV. The host sent `P3UART?\r\n` through `/dev/ttyUSB0` at 115200 and received the same bytes back. The decoder reported `PASS` with initialized 16550 state, RX read activity, TX write activity, and no AXI error. This isolates the physical UART and Xilinx `axi_uart16550` path as good, so mainline OpenPiton no-output debug should focus on integration and software sequencing rather than CW58/CW59 or FTDI hardware.

Validation harness note: `scripts/p3_uart16550_ila_interact_validate.py` does not store lab SSH credentials. It uses SSH key authentication by default, or the `P3_REMOTE_PASS` environment variable if password auth is required. `P3_REMOTE_HOST`, `P3_REMOTE_USER`, `P3_UART_DEVICE`, and `P3_UART_BAUD` can override the defaults.

### P3 Build 24 RTL Debug Flow

Build 24 adds `P3_RTL_DEBUG`, which exports deterministic RTL debug buses to the P3 top level before synthesis. This replaces the Build 23 strategy of probing internal post-synthesis net names such as `chip_rst_n`, which proved unreliable after optimization and hierarchy changes.

The script also forces the Ariane/RV64 macro set into the Vivado fileset: `PITON_ARIANE`, `PITON_RV64_PLATFORM`, `PITON_RV64_DEBUGUNIT`, `PITON_RV64_CLINT`, `PITON_RV64_PLIC`, and `WT_DCACHE`. The P3 `.xpr` may not preserve these macros even when the PyHP-generated RTL was produced with `PITON_ARIANE=1`, so the debug build must not rely on the project file alone for core selection. HUAPROP3 ties off the RISC-V debug-unit JTAG wires internally when this mode is enabled.

```bash
# First regenerate PyHP RTL with the HUAPROP3 Ariane environment.
pyhp.py piton/design/chip/rtl/chip.v.pyv > piton/design/chip/rtl/chip.tmp.v
pyhp.py piton/design/chip/tile/rtl/tile.v.pyv > piton/design/chip/tile/rtl/tile.tmp.v
pyhp.py piton/design/chipset/rtl/chipset_impl.v.pyv > piton/design/chipset/rtl/chipset_impl.tmp.v

# Then build and capture.
vivado -mode batch -source scripts/p3_build24_rtl_debug.tcl
vivado -mode batch -source scripts/p3_program_pdi.tcl -tclargs huaprop3_openpiton/debug_build/p3_top_rtl_debug.pdi
vivado -mode batch -source scripts/p3_ila_capture_rtl_debug.tcl

# If synth_1 already completed and only implementation needs rerun:
vivado -mode batch -source scripts/p3_build24_impl_resume.tcl

# Fallback if launch_runs/open_checkpoint stalls on the VP1902 checkpoint:
vivado -mode batch -source scripts/p3_build24_direct_flow.tcl

# If direct synthesis already completed and only the direct implementation
# path needs another attempt:
vivado -mode batch -source scripts/p3_build24_direct_flow.tcl -tclargs -reuse_synth
```

The expected outputs are:

| File | Purpose |
|------|---------|
| `huaprop3_openpiton/debug_build/p3_top_rtl_debug.pdi` | Program image |
| `huaprop3_openpiton/debug_build/p3_top_rtl_debug.ltx` | ILA probe map |
| `huaprop3_openpiton/debug_build/ila_capture_rtl_debug.csv` | Captured reset/fetch/bootrom/UART/DDR debug data |

The debug buses are intentionally coarse and sticky-event oriented. They answer the first-order bring-up questions: whether chip/tile/Ariane reset is released, whether Ariane emits L15 requests, whether those requests reach the chipset/bootrom path, whether bootrom responds, whether UART MMIO writes happen, and whether DDR AXI requests appear.

Implementation note: Build 24 now generates the debug-core XDC directly from the explicit top-level RTL debug buses, instead of opening the synthesized design with `open_run synth_1`. This keeps implementation in project run mode while avoiding a Vivado hang observed when the top Tcl process tried to reopen the large synthesized VP1902 checkpoint after clean synthesis. Because these probes are top-level `keep`/`mark_debug` nets (`p3_debug_bus`, `p3_debug_seen`, `p3_top_status`, `dbg_m_axi_araddr`, and `dbg_m_axi_awaddr`), the XDC can name them deterministically and implementation will fail naturally if any net disappears.

Implementation note: Ariane/CVA6 instantiates the `unread` helper from `common_cells` in frontend logic (`bht`, `btb`, and `instr_queue`). The upstream helper is intentionally an input-only empty module. In the P3 Vivado flow, adding that source is not sufficient: clean synthesis still preserves seven `unread` leaves as black boxes, and `opt_design` can later fail DRC `INBB-3`. Build 24 therefore used `piton/design/xilinx/huaprop3/unread_vivado_impl.sv`, a tiny LUT sink implementation of `unread`, instead of the empty common_cells source. Build 41 reproduced the same DRC after forcing the Ariane/RV64 macro set, so `scripts/p3_create_bd.tcl` now applies the unread shim for recreated P3 projects and `scripts/p3_build41_fetch_debug.tcl` reapplies it when resuming an existing project with `-skip_create`.

Implementation note: after changing the unread source setup, check `synth_1/runme.log` for the incremental synthesis summary. If Vivado reports 100% reuse and `Report BlackBoxes` still lists `unread`, the project is reusing a stale `utils_1/imports/synth_1/p3_top.dcp`. Build 24 and Build 41 disable `synth_1` incremental checkpoint properties and remove that imported DCP from the project before launching synthesis so the shim is actually elaborated into the output checkpoint. Use numeric `0`, not Tcl string `false`, for Vivado's `AUTO_INCREMENTAL_CHECKPOINT` run property.

Implementation note: Build 41 supports `-reuse_synth` for implementation-only retries. Use this after `synth_1` is already complete and `impl_1` fails in a non-RTL Vivado path, such as Versal DDRMC/NoC PHY child regeneration or PLM/BSP packaging. The option still refreshes the source list and verifies `synth_1` progress is 100%, but it does not reset or relaunch synthesis.

Implementation note: on 2026-05-26, both the WSL project and a `save_project_as` copy under Windows `%TEMP%` stalled inside `launch_runs impl_1 -scripts_only` before creating `impl_1/runme.*`. Direct `open_checkpoint` of the completed 99 MB `p3_top.dcp` also went idle after loading `xcvp1902-vsva6865-1MP-e-S`. `scripts/p3_build24_direct_flow.tcl` is the fallback for this case: it sources the generated `synth_1/p3_top.tcl` so synthesis remains in the same Vivado process, inserts the RTL debug ILA, reads the OOC IP DCPs into their black-box cells, and then runs `opt_design` through `write_device_image` without run manager or DCP reopen.

Implementation note: the direct fallback should locate OOC/IP cells by synthesized `REF_NAME`, not by fixed BD hierarchy. A 2026-05-26 direct run completed synthesis and connected the explicit top-level debug nets, but failed before `opt_design` because `u_bd/openpiton_top_i/axi_noc_0` was no longer a valid cell path after synthesis. The fallback script now reads `openpiton_top_axi_noc_0_0`, `openpiton_top_clk_wizard_0_0`, `openpiton_top_proc_sys_reset_0_0`, and `uart_16550` DCPs into the matching black-box cells by `REF_NAME`; it also supports `-reuse_synth` to continue from `debug_build/build24_direct/p3_top.dcp` without another full synthesis pass.

Implementation note: after the OOC/IP DCPs are stitched, Vivado may still report implementation-time black boxes for debug and Versal hard-IP wrappers such as `axi_dbg_hub`, `u_ila_0`, `axi_noc`, and `proc_sys_reset`. In 2024.2 these can appear as concrete `_CV` `REF_NAME` values, for example `axi_dbg_hub_CV`, `u_ila_0_CV`, `axi_noc_CV`, and `proc_sys_reset_CV`. These are expected at this point in the direct flow and should be logged, not treated like unresolved RTL modules. The direct script fails only if any other black-box `REF_NAME` remains.

Implementation note: the direct fallback also generates `debug_build/build24_direct/p3_top_ddr_io.xdc` and applies it before and after OOC DCP stitching. The project-mode flow normally carries DDRMC I/O standards through AXI NoC/IP constraints named on the internal `ch0_ddr4_*` interface, but the direct checkpoint flow exposes top-level `ddr4_rtl_0_*` ports and can otherwise reach `opt_design` with `IOSTANDARD=UNDEFINED` on DDR4 pins. The generated XDC maps those top-level ports to the DDRMC-required standards (`SSTL12`, `DIFF_SSTL12`, `POD12`, `DIFF_POD12`, and `LVCMOS12` for reset).

Implementation note: during `opt_design`, Vivado may synthesize inserted Versal debug/IP cores through internal `launch_runs` calls. On 2026-05-26, launching the AXI Debug Hub, AXI NoC, proc_sys_reset, and ILA OOC runs in parallel caused four child Vivado processes to stall while loading the VP1902 part. The direct script wraps `launch_runs` before `opt_design` and forces `-jobs 1`, so these generated debug/IP runs load the large device serially.

Implementation note: the RTL debug ILA clock must be resolved from the final stitched netlist, not from a bare top-level net name before OOC DCP stitching. A 2026-05-26 direct run passed DDR PHY generation and `opt_design`, then failed `place_design` DRC `NDRV-1` because `u_ila_0/inst/clk` was driverless. The Build 24 scripts now generate debug XDC that resolves exactly one driven clock net from the BD/RTL clock path (`clk_wizard_0/chipset_clk`, NoC `aclk0`, proc_sys_reset `slowest_sync_clk`, or OpenPiton `chipset_clk`) and connects both the ILA and debug hub to that net. The direct fallback also applies the debug XDC after reading the AXI NoC, Clock Wizard, proc_sys_reset, and `uart_16550` DCPs, so later `read_checkpoint -cell` calls cannot invalidate the debug clock connection.

Implementation note: a later Build 24 direct run passed `place_design` with the fixed ILA clock, but failed `route_design` on the SD data tristate enable net `sd_dat_oe_o`. The SD data host marked the scalar `DAT_oe_o` output register as `iob=true`; Vivado packed that enable into one Versal XPIOLOGIC TFF, then could not route the local TFF output to multiple `sd_dat[*]` IOBUF `T` pins. Keep shared SDIO output-enable registers in fabric (`iob=false`) on P3/Versal, while allowing per-bit data registers to remain IOB-packed.

### P3 Build 25 Minimal Debug Hub Recovery

Build 25 narrows the debug objective to the Versal runtime debug path itself. The reference `huaprop3onecore` image and `huaprop3top_wrapper.ltx` were programmed and verified on the same P3 board: Vivado reached `AXI_DEBUG_HUB_V1` at `0x3ffc0000000` through `huaprop3top_i/ps_wizard_0/PMC_AXI_NOC0`, enumerated `hw_ila_1`, triggered it immediately, uploaded samples, and wrote CSV data. Therefore the board-level XVC/JTAG/PMC debug infrastructure is good; Build 24's `Failed to communicate with debug hub address(es): 0x3ffc0000000` points at the OpenPiton design's inserted `axi_dbg_hub` runtime clock/reset/connectivity, not at hw_server, XVC, JTAG, PDI, LTX, or UUID mismatch.

The Build 25 recovery flow keeps the ILA intentionally tiny. It probes only board/top-level reset state, LEDs, SD reset, and a top-level clock heartbeat generated directly from `chipset_clk`. Ariane reset/fetch/NoC probes must not be added until this minimal ILA passes `refresh_hw_device`, `get_hw_ilas`, `run_hw_ila -trigger_now`, `upload_hw_ila_data`, and CSV export on hardware. The debug-clock strategy should be compared against the reference routed DCP and then fixed to the same stable BD clock style instead of relying on broad post-synthesis net-name discovery.

Implementation note: Build 25 uses `scripts/p3_build25_minimal_debug.tcl`, which delegates to the direct Build 24 flow with `-build25_minimal_debug` and writes separate outputs named `p3_top_build25_minimal_debug.pdi/.ltx`. The `P3_RTL_DEBUG` top level now exposes `p3_min_dbg_status[31:0]` and `p3_min_dbg_heartbeat[31:0]`; the heartbeat increments directly on `chipset_clk` and is not gated by `peripheral_aresetn`, so a capture can distinguish a dead debug/clock path from a held-reset OpenPiton core. Use `scripts/p3_ila_capture_build25_minimal.tcl` to capture and `scripts/p3_check_build25_ila_csv.py` to verify heartbeat movement.

Implementation note: Build 25 synthesis can succeed while `opt_design` later fails in a generated child Vivado process for `xilinx.com:ip:noc_mc_ddr4_phy:1.0`. The failure mode is `cacheID` empty followed by missing synthesis output products and `HRTInvokeSpec : No Verilog or VHDL sources specified`. The direct flow now seeds the known-good DDR PHY debug IP cache entry `be79b17307062196` into the build-local `.cache/ip` directory and sets the active project's `ip_output_repo` there before `opt_design`. This keeps the large NoC DDR4 PHY child IP on the same cached path that Build 24 already verified, instead of letting the implementation step regenerate it from an incomplete temporary IP project.

Implementation note: the DDR PHY cache workaround can still leave Build 25 inside Vivado's generated Chipscope debug-IP flow. On 2026-05-26, `opt_design` generated `debug_ip_core.tcl` with `set jobs 4`, then launched four OOC child Vivado processes for `axi_dbg_hub`, debug AXI NoC, `proc_sys_reset`, and `u_ila_0`; all four stopped making progress after loading the VP1902 part. The direct flow now also forces `synth.maxThreads` and `synth.maxClusterJobsRunCount` to `1` before `opt_design`, in addition to wrapping `launch_runs -jobs 1`, so generated debug/IP synthesis is serialized at the Vivado parameter level.

Implementation note: parameter-level serialization alone did not rewrite Vivado's generated `debug_ip_core.tcl`, which still used `set jobs 4` in a later Build 25 retry. The direct flow therefore also seeds the known-good implementation child IP cache entries for the AXI debug hub (`63238c300d84dd3e`), debug AXI NoC (`26f047544d6aa94f`), and debug `proc_sys_reset` (`297bb7bb4c294321`) alongside the DDR PHY cache. Build 25 intentionally matches the cached ILA entry `3fd143ca8c7451ee` by using a 4096-depth, storage-qualification-enabled, 12-probe narrow ILA: heartbeat bits, reset, peripheral reset, SD reset/card detect, UART pins, and LEDs. The ILA cache is seed-only: direct `read_checkpoint -cell` replacement was rejected because Vivado's intermediate `u_ila_0_CV` black box still carried AXIS/stream ports while the cached net-probe `axis_ila` DCP only exposes `clk` and `probe*` ports.

Implementation note: cache seeding can still be too late for the generated debug AXI NoC path. A Build 25 retry confirmed cache hits for `axi_dbg_hub` and debug `proc_sys_reset`, but the child Vivado stalled while creating `design_axi_noc.bd` and loading the VP1902 part before reaching the debug AXI NoC cache check. Build 25 now bypasses that path by reading the cached DCPs directly into `axi_dbg_hub_CV`, `axi_noc_CV`, and `proc_sys_reset_CV` before `opt_design`; only `u_ila_0` is left for Vivado's debug-IP flow to resolve from the seeded matching ILA cache.

Implementation note: on 2026-05-27 the seed-only ILA path closed implementation successfully. The Build 25 minimal image completed through `route_design` and `write_device_image`, producing `p3_top_build25_minimal_debug.pdi` plus `p3_top_build25_minimal_debug.ltx`. The route report had 0 failed nets, 0 unrouted nets, and 0 overlaps; the estimated post-route timing was WNS about 8.965 ns and WHS about 0.009 ns. The remaining validation is runtime-only: program the board, confirm the debug hub refreshes, trigger/upload the tiny ILA, and verify that the heartbeat bits move in the exported CSV.

Implementation note: the Build 25 image programmed cleanly, but the runtime debug path still failed. The generated LTX exposed `axi_dbg_hub` at `0x44a00000` with no `available_addresses`/`ADDRESS_LIST` master path, and hardware refresh timed out. Manually patching the LTX to use the reference address `0x3ffc0000000` and `u_bd/openpiton_top_i/ps_wizard_0/PMC_AXI_NOC0` changed the failing address but still timed out. This confirms the fault is not just a probes-file address label; the fundamental root cause is that the post-synthesis debug hub/NoC insertion path (`create_debug_core` / `.xdc` insertion) does not automatically generate the required AXI interface connection or NoC address space mapping to link the PL-side Debug Hub (`axi_dbg_hub`) to the PMC Master (`PMC_AXI_NOC0`). As a result, the AXI interface of the debug hub is left floating and unconnected in the hardware design, making it unreachable through the P3 PMC debug route. The next minimal debug build should instantiate the ILA inside the Block Design so the debug infrastructure is synthesized and routed within the same IP Integrator context as the PMC and NoC.

### P3 Build 26 BD-Owned Minimal ILA

Build 26 moves the minimal heartbeat/status ILA from post-synthesis `create_debug_core` insertion into the Vivado block design. This mirrors the verified `huaprop3onecore` reference strategy: the ILA is a BD-owned `axis_ila` net-probe IP clocked by `clk_wizard_0/chipset_clk`, so Vivado should generate the Versal AXI debug hub and PMC access path as part of the BD infrastructure instead of as a late debug-core overlay.

The top-level minimal debug bus is now always present in `p3_top.v`, independent of the wider `P3_RTL_DEBUG` Ariane probe bus:

- `p3_min_dbg_heartbeat[31:0]` increments directly on `chipset_clk`.
- `p3_min_dbg_status[31:0]` packs Build ID `16'h2501`, top reset, `peripheral_aresetn`, SD reset/card detect, UART pins, and LEDs.
- `openpiton_top_wrapper` receives these buses through `p3_dbg_heartbeat_i` and `p3_dbg_status_i`, and the BD-owned `axis_ila_0` probes them as `probe0` and `probe1`.

Use the Build 26 script from the repository root:

```bash
vivado -mode batch -source scripts/p3_build26_bd_ila.tcl
```

The script first patches the existing `openpiton_top.bd` in place, generates the BD wrapper, regenerates `synth_1` scripts, explicitly launches the BD ILA OOC run `openpiton_top_axis_ila_0_0_synth_1`, then delegates to the direct Build 24 implementation path with `-build26_bd_ila`. Unlike Builds 24/25, Build 26 deliberately skips post-synthesis `create_debug_core`; the only ILA in the design should be the BD-owned `axis_ila_0`. Expected outputs are `huaprop3_openpiton/debug_build/p3_top_build26_bd_ila.pdi`, `.ltx`, and `debug_build/build26_bd_ila/p3_top_route.dcp`.

Implementation note: the direct flow should read BD IP DCPs from the generated BD IP output directory when available, not only from project run directories. A 2026-05-27 Build 26 attempt completed top-level synthesis but failed before implementation because `openpiton_top_axi_noc_0_0_synth_1` did not exist under `.runs`, while `generate_target all` had already produced `huaprop3_openpiton.gen/sources_1/bd/openpiton_top/ip/openpiton_top_axi_noc_0_0/openpiton_top_axi_noc_0_0.dcp`. The Build 26/direct stitch path now uses that generated BD IP DCP for the AXI NoC, matching the existing Clock Wizard, proc_sys_reset, and BD-owned ILA DCP lookup style.

Build 26 completed implementation on 2026-05-27. The output files are `huaprop3_openpiton/debug_build/p3_top_build26_bd_ila.pdi`, `huaprop3_openpiton/debug_build/p3_top_build26_bd_ila.ltx`, and `huaprop3_openpiton/debug_build/build26_bd_ila/p3_top_route.dcp`. The LTX now matches the reference-style debug route: `axi_dbg_hub` has offset `0x000003FFC0000000`, `available_addresses` points to `u_bd/openpiton_top_i/ps_wizard_0/PMC_AXI_NOC0`, and the ILA core is `u_bd/openpiton_top_i/axis_ila_0`.

After PDI programming, the first hardware check is not Ariane activity. It is the debug runtime path itself: `refresh_hw_device`, `get_hw_ilas`, immediate trigger/upload, and CSV export should succeed, and the generated LTX should show a BD/PMC debug path comparable to the reference `.../ps_wizard_0/PMC_AXI_NOC0` route. This check passed on 2026-05-27: Vivado reported `Successfully set up debug cores at debug hub address(es): 0x3ffc0000000`, found `hw_ila_1` at `u_bd/openpiton_top_i/axis_ila_0`, and exported `huaprop3_openpiton/debug_build/ila_capture_build26_bd_ila.csv`.

### P3 Build 27 BD-Owned RTL Debug ILA

Build 27 keeps the Build 26 debug infrastructure intact and only widens the BD-owned `axis_ila_0` probe set. It is the first post-runtime-validation Ariane bring-up probe build, intended to answer whether reset, wakeup, L15/NoC, and AXI activity are present before adding deeper fetch/PC probes.

Use the Build 27 script from the repository root:

```bash
vivado -mode batch -source scripts/p3_build27_bd_rtl_ila.tcl
```

The Build 27 prepare step defines both `P3_RTL_DEBUG` and `P3_BD_RTL_DEBUG_ILA`, expands `axis_ila_0` to seven net probes, regenerates the BD wrapper and `synth_1` scripts, and launches the updated `openpiton_top_axis_ila_0_0_synth_1` OOC run. The direct implementation branch is `-build27_bd_rtl_ila`, which still skips post-synthesis `create_debug_core`.

Probe mapping:

- `probe0[31:0]`: top-level `p3_min_dbg_heartbeat`
- `probe1[31:0]`: top-level `p3_min_dbg_status`
- `probe2[31:0]`: accumulated `p3_debug_seen`
- `probe3[31:0]`: `p3_top_status`
- `probe4[127:0]`: combined chipset/chip/tile `p3_debug_bus`
- `probe5[63:0]`: AXI read address `m_axi_araddr`
- `probe6[63:0]`: AXI write address `m_axi_awaddr`

Build 27 completed direct implementation and generated `huaprop3_openpiton/debug_build/p3_top_build27_bd_rtl_ila.pdi` on 2026-05-27. Route status reported 147,559 fully routed routable nets and 0 routing errors. The timing report met all user-specified constraints with WNS 17.068 ns, TNS 0, WHS 0.022 ns, and THS 0, while still reporting many no-clock and unconstrained internal endpoints inherited from the current constraint set.

Implementation note: the Build 27 flow printed `Writing debug probes: .../p3_top_build27_bd_rtl_ila.ltx` and `write_debug_probes` returned without an error, but no Build 27 LTX file was present in the output directory. Attempts to reopen both `p3_top_route.dcp` and `p3_top_post_route_phys_opt.dcp` to regenerate the LTX failed during `open_checkpoint` with ILA-internal site routing overlap errors around `u_bd/openpiton_top_i/axis_ila_0/inst/axis_ila_intf`. Do not program Build 27 for ILA capture until a valid matching LTX is produced; the next build should reduce or split the widened probes, adjust ILA settings, or otherwise avoid the DCP reopen/LTX generation failure.

### P3 Build 28 Split Compact BD-Owned RTL ILAs

Build 28 is the recovery path for the Build 27 LTX/routing issue. It keeps the validated Build 26 BD-owned debug infrastructure and avoids post-synthesis debug insertion or post-route LTX regeneration. Instead of one wide `axis_ila_0`, the BD now owns two smaller net-probe ILAs clocked by `clk_wizard_0/chipset_clk`: `axis_ila_0` captures reset/status/core activity and `axis_ila_1` captures compact AXI address/control activity. This gives Vivado two independent debug IP instances to place and route instead of concentrating the whole debug load in one ILA interface.

Use the Build 28 script from the repository root:

```bash
vivado -mode batch -source scripts/p3_build28_split_ila.tcl
```

Probe mapping:

- `axis_ila_0/probe0[0:0]`: `p3_min_dbg_heartbeat[0]`
- `axis_ila_0/probe1[15:0]`: compact `p3_top_status[15:0]`
- `axis_ila_0/probe2[14:0]`: compact sticky/activity `p3_debug_seen[14:0]`
- `axis_ila_0/probe3[31:0]`: selected core/tile/chip debug bits `{p3_debug_bus[39:32], p3_debug_bus[23:16], p3_debug_bus[15:0]}`
- `axis_ila_1/probe0[63:0]`: compact AXI `{m_axi_araddr[31:2], m_axi_awaddr[31:2], arvalid, arready, awvalid, awready}`

The total Build 28 probe payload is 128 bits, down from Build 27's 384 bits. The direct flow branch is `-build28_split_ila`; it reads both BD ILA DCPs (`openpiton_top_axis_ila_0_0` and `openpiton_top_axis_ila_1_0`) and still skips `create_debug_core`. After `write_debug_probes`, the script now explicitly checks that the matching LTX file exists and is non-empty before writing the PDI. If LTX generation silently fails again, the build stops before producing a programmable image so the hardware test cannot accidentally use a stale or missing probes file.

Build 28 completed synthesis, placement, routing, and post-route physical optimization with 0 failed or unrouted nets, but intentionally stopped before PDI generation because `write_debug_probes` did not produce `p3_top_build28_split_ila.ltx`. A read-only checkpoint diagnostic confirmed that the routed design does contain Chipscope cores for `u_bd/openpiton_top_i/axis_ila_0` and `axis_ila_1`, but reopening the post-route checkpoint fails inside the ILA implementation with site routing overlap/fixed-pin errors. This reinforces the bring-up rule: do not rely on post-route DCP reopen to recover a missing LTX on this Versal flow.

### P3 Build 29 Route-Time Split ILA LTX

Build 29 keeps the Build 28 split 128-bit probe payload and BD-owned `axis_ila_0`/`axis_ila_1` structure, but changes two flow details:

- `scripts/p3_prepare_build29_split_ila.tcl` reuses the Build 28 BD patch logic while setting `C_INPUT_PIPE_STAGES=0`, matching the conservative Build 26 ILA setting that already passed runtime debug capture.
- `scripts/p3_build24_direct_flow.tcl -build29_split_ila` writes and validates the LTX immediately after `route_design` in the same in-memory implementation session, before writing the route checkpoint or PDI. The LTX check requires a non-empty file and the expected Versal debug path `0x000003FFC0000000` through `PMC_AXI_NOC0`.

Use:

```bash
vivado -mode batch -source scripts/p3_build29_split_ila.tcl
```

Build 29 skips `post_route_phys_opt_design` so the PDI is generated from the same routed in-memory design used for LTX generation. The intent is to avoid both failure modes seen in Builds 27/28: missing main-flow LTX and fragile post-route checkpoint reopening.

Build 29 routed successfully with 0 failed or unrouted nets, but `write_debug_probes` still stopped before PDI generation with `No debug cores were found in this design`. A read-only diagnostic of the in-memory implementation checkpoint showed `axis_ila_0` and `axis_ila_1` as debug cores while the generated `axi_dbg_hub_CV` remained a black box. Reopening the checkpoint can produce an LTX, but without the expected address/path, so DCP reopen is not a valid recovery path.

### P3 Build 30 Debug Child-IP Stitching

Build 30 keeps the Build 29 BD and probe payload unchanged: two BD-owned net-probe ILAs, `C_INPUT_PIPE_STAGES=0`, data depth 1024, and 128 total probe bits. The direct-flow change is limited to debug infrastructure handling:

- `scripts/p3_build24_direct_flow.tcl -build30_split_ila` seeds the same debug child-IP cache as Build 25, then explicitly stitches the cached `axi_dbg_hub_CV`, generated debug `axi_noc_CV`, and debug `proc_sys_reset_CV` DCPs.
- The shared split-ILA prepare script now accepts an already-exported cached ILA DCP when Vivado 2024.2 does not materialize an `openpiton_top_axis_ila_*_synth_1` run object after `generate_target`.
- The stitching is attempted before implementation and again immediately after `opt_design`, because Build 29 showed that the `axi_dbg_hub_CV` black box may only become visible during optimization.
- The flow writes `p3_top_build30_split_ila_debug_summary.txt` with `get_debug_cores`, `IS_DEBUG_CORE`, black-box, and selected clock/reset/probe pin-net summaries before route-time `write_debug_probes`.
- The flow still writes the LTX in the same in-memory routed session and requires `0x000003FFC0000000` plus `PMC_AXI_NOC0` before any PDI is emitted.

Use:

```bash
vivado -mode batch -source scripts/p3_build30_split_ila.tcl
```

Build 30 completed synthesis, optimization, placement, physical optimization, and routing with 0 failed or unrouted nets, but still stopped before PDI generation because `write_debug_probes` reported no debug cores. Its debug summary showed `get_debug_cores=0` and only `ps_wizard_0` marked as `IS_DEBUG_CORE`; `axis_ila_0`, `axis_ila_1`, and `axi_dbg_hub` were not visible as Chipscope debug cores in the direct-flow netlist. The direct `read_checkpoint -cell` path can place and route the ILA logic, but it is not a reliable way to preserve BD/IP Integrator debug-core metadata for LTX generation on this Versal design.

### P3 Build 31 Run-Manager Split ILA

Build 31 keeps the Build 30 probe payload and BD structure unchanged, but stops manually stitching BD ILA DCPs in the direct implementation flow. Instead, `scripts/p3_build31_runmgr_split_ila.tcl` uses Vivado's project run manager for `synth_1` and a dedicated `impl_31_runmgr_split_ila` implementation run. This lets IP Integrator own the `axis_ila_0`/`axis_ila_1`, AXI Debug Hub, and `PMC_AXI_NOC0` address-path metadata end to end.

Before launching the run, Build 31 removes stale post-synthesis debug XDC files (`p3_top_debug.xdc` and `p3_top_rtl_debug.xdc`) from the active project filesets so the image contains only the BD-owned split ILAs. After `write_device_image`, the script publishes `huaprop3_openpiton/debug_build/p3_top_build31_runmgr_split_ila.pdi` and `.ltx` only if the LTX exists, is non-empty, and contains the expected `0x000003FFC0000000` / `PMC_AXI_NOC0` path plus both split ILA cell names.

Implementation note: the stale-XDC removal is kept in the active Vivado session and followed by `update_compile_order`; it is not followed by `save_project`. Vivado 2024.2 treats `save_project` as a `save_project_as` form requiring a project name in this batch context, which caused the first Build 31 attempt to exit before synthesis.

Use:

```bash
vivado -mode batch -source scripts/p3_build31_runmgr_split_ila.tcl -tclargs -jobs 1
```

Build 31 completed on 2026-05-27 with the run-manager flow. The published files are `huaprop3_openpiton/debug_build/p3_top_build31_runmgr_split_ila.pdi` and `huaprop3_openpiton/debug_build/p3_top_build31_runmgr_split_ila.ltx`. The LTX contains the expected Versal debug route: `AXI_DEBUG_HUB_V1` at `0x000003FFC0000000`, accessible through `u_bd/openpiton_top_i/ps_wizard_0/PMC_AXI_NOC0`, with both `u_bd/openpiton_top_i/axis_ila_0` and `u_bd/openpiton_top_i/axis_ila_1`.

Program and capture with:

```bash
vivado -mode batch -source scripts/p3_program_pdi.tcl -tclargs huaprop3_openpiton/debug_build/p3_top_build31_runmgr_split_ila.pdi
vivado -mode batch -source scripts/p3_ila_capture_build31_split_ila.tcl
```

The capture script enumerates both ILAs, triggers each immediately, uploads samples, and writes CSV files under `huaprop3_openpiton/debug_build/`.

Hardware validation passed on 2026-05-27: programming reported `DONE bit: HIGH`, `refresh_hw_device` reported `Successfully set up debug cores at debug hub address(es): 0x3ffc0000000`, and Vivado enumerated two ILA cores. Immediate capture wrote two 1024-sample CSV files. The capture showed `p3_dbg_heartbeat_bit_i` toggling, `p3_dbg_top_status16_i = 0xff02`, `p3_dbg_seen15_i = 0x7fff`, `p3_dbg_core_bus32_i = 0x0038fe00`, and `p3_dbg_axi_bus64_i = 0x0000000000000005`. This proves the debug path is stable and the tile/L15/NoC side has sticky activity; the remaining no-UART question should move to the chipset bootrom/UART/MMIO path.

### P3 Build 32 Run-Manager Chipset ILAs

Build 32 keeps the Build 31 run-manager and BD-owned `axis_ila_0`/`axis_ila_1` infrastructure, but replaces the probe payload with chipset-focused signals. The total probe payload is 97 bits:

- `axis_ila_0/probe0[0:0]`: `p3_min_dbg_heartbeat[0]`
- `axis_ila_0/probe1[15:0]`: `p3_top_status[15:0]`
- `axis_ila_0/probe2[15:0]`: `p3_debug_seen[31:16]`, the chipset sticky activity word
- `axis_ila_1/probe0[63:0]`: `p3_debug_bus[127:64]`, the full chipset debug bus

Use:

```bash
vivado -mode batch -source scripts/p3_build32_runmgr_chipset_ila.tcl -tclargs -jobs 1
vivado -mode batch -source scripts/p3_program_pdi.tcl -tclargs huaprop3_openpiton/debug_build/p3_top_build32_runmgr_chipset_ila.pdi
vivado -mode batch -source scripts/p3_ila_capture_build32_chipset_ila.tcl
```

Implementation note: on 2026-05-28, Build 32 completed synthesis, `opt_design`, `place_design`, `phys_opt_design`, and `route_design` with 0 failed nets, 0 unrouted nets, and 0 node overlaps. Post-route timing was positive (`WNS` about 9.073 ns, `WHS` about 0.014 ns). The run then failed only in `write_device_image` while Vivado generated the Versal PLM BSP from `D:/Xilinx/Vivado/2024.2/data/embeddedsw`: HSI reported a failed copy of `standalone_v9_2/.../translation_table.S`, and XilPM compilation later missed `xstatus.h`. The source files exist in the Vivado install, so this is a Windows/WSL run-directory PLM/BSP generation issue, not an RTL, route, ILA, or timing failure. `scripts/p3_recover_build32_outputs.tcl` opens the routed DCP from the repository root, where the generated PLM BSP path is shorter than the failed run-manager work directory, and writes checked Build 32 LTX/PDI outputs without rerunning synthesis or implementation. This recovery completed successfully, publishing `huaprop3_openpiton/debug_build/p3_top_build32_runmgr_chipset_ila.pdi` and `.ltx`; the LTX contains `0x000003FFC0000000`, `PMC_AXI_NOC0`, `axis_ila_0`, and `axis_ila_1`.

The first Build 32 hardware capture succeeded at the debug-transport level but exported all-zero probe samples, including the `p3_min_dbg_heartbeat[0]` probe that toggled in Build 31. Treat an all-zero capture as a probe wiring/clock/capture validity issue until the routed DCP proves the ILA inputs are driven by the intended `p3_top` nets. `scripts/p3_inspect_build32_ila_nets.tcl` is the read-only diagnostic for this check.

Follow-up diagnostic result: the routed DCP showed the Build 32 probe nets tied to `GROUND`, including the heartbeat probe. The underlying build-flow fault was stale mirrored RTL under `Z:/tmp`: `synth_1/p3_top.tcl` read `Z:/tmp/p3_top.v`, but that temp copy predated the repository `p3_top.v` change that added the `P3_BD_CHIPSET_DEBUG_ILA` wrapper-port connections. Vivado emitted the corresponding synthesis warning that `u_bd` had 69 declared ports but only 65 connected. Future run-manager debug builds that still rely on `Z:/tmp` mirrors must refresh those mirrors before `launch_runs`, and should fail early if the synth log contains that port-count warning.

### P3 Build 33 Temp-Synced Chipset ILAs

Build 33 is the corrected rerun of the Build 32 chipset probe payload. It keeps the same two BD-owned `axis_ila` instances and the same 97-bit probe plan, but moves temp-source synchronization into the Vivado Tcl flow before synthesis:

```bash
vivado -mode batch -source scripts/p3_build33_runmgr_chipset_ila.tcl -tclargs -jobs 1
vivado -mode batch -source scripts/p3_program_pdi.tcl -tclargs huaprop3_openpiton/debug_build/p3_top_build33_runmgr_chipset_ila.pdi
vivado -mode batch -source scripts/p3_ila_capture_build33_chipset_ila.tcl
```

The prepare and run scripts copy the canonical repository files `piton/design/xilinx/huaprop3/p3_top.v`, `piton/design/xilinx/huaprop3/openpiton_wrapper.v`, `piton/design/rtl/system.v`, and `piton/design/include/piton_system.vh` into `Z:/tmp` before Vivado regenerates or launches runs. The run script also scans the synthesis log and aborts if `openpiton_top_wrapper/u_bd` still shows the under-connected-port warning that caused Build 32's ILA probes to be tied low.

Build 33 completed on 2026-05-28 with exit code 0. It published `huaprop3_openpiton/debug_build/p3_top_build33_runmgr_chipset_ila.pdi` and `p3_top_build33_runmgr_chipset_ila.ltx`; the LTX contains the expected `0x000003FFC0000000` debug hub address, `PMC_AXI_NOC0` access path, and both `axis_ila_0`/`axis_ila_1` cells. The implementation route was clean with 0 failed nets, 0 unrouted nets, 0 partially routed nets, and 0 node overlaps. Estimated timing remained positive (`WNS` about 9.120 ns, `WHS` about 0.015 ns).

The Build 33 routed probe inspection is intentionally treated as a wiring sanity check, not a functional chipset result. Unlike Build 32, the probe inputs are not all tied to `GROUND`: the heartbeat/status/chipset pins exist in the BD wrapper path, most payload bits are real `SIGNAL` nets, and only isolated fields are optimized to `GROUND` or `POWER` where the selected debug bit is statically false or true. Therefore a Build 33 hardware capture can be interpreted as chipset activity data rather than stale-wrapper fallout, assuming the debug hub refresh and CSV upload succeed.

Hardware validation passed on 2026-05-28. Programming reported `DONE bit: HIGH`; `refresh_hw_device` reached the debug hub at `0x3ffc0000000`, found two ILA cores, and immediate captures exported two 1024-sample CSV files. Repeated captures were stable: heartbeat toggled, `p3_dbg_top_status16_i = 0xff02`, `p3_dbg_chipset_seen16_i = 0x6fff`, and `p3_dbg_chipset_bus64_i = 0x00000000000290f9`. The decoded sticky bits show chipset reset released, NoC2 traffic from the core into the chipset, bootrom request/response path activity, memory/AXI request activity, UART-buffer readiness, and at least one UART core AXI write-address handshake. This moves the no-UART-output problem from reset/clock/fetch/bootrom reachability into the UART bridge/ns16550 transaction layer.

The next debug image should not widen the general chipset bus. It should replace the payload with UART-local observability: NOC-to-UART request/response valid/ready, `noc_axilite_bridge` core AXI-lite AW/W/B/AR/R valid/ready, `uart_mux` selected AXI-lite signals, ns16550 TX low/toggle state, and low UART address/data/status fields.

### P3 Build 34 UART-Local ILAs

Build 34 keeps the Build 33 run-manager flow and two BD-owned ILAs, but introduces `P3_BD_UART_DEBUG_ILA` as a payload-selection macro. The total debug width stays 97 bits:

- `axis_ila_0/probe0[0:0]`: `p3_min_dbg_heartbeat[0]`
- `axis_ila_0/probe1[15:0]`: `p3_top_status[15:0]`
- `axis_ila_0/probe2[15:0]`: UART-local sticky bits through `p3_debug_seen[31:16]`
- `axis_ila_1/probe0[63:0]`: UART-local live bus through `p3_debug_bus[127:64]`

The low UART sticky/bus bits preserve the Build 33 meaning for comparison. The added bits expose AXI-lite ready/response channels, NOC valid/ready around `uart_top`, ns16550 TX and interrupt state, write strobes, and `s_axi_wdata[7:0]`. This should distinguish a missing NOC request, a stuck `noc_axilite_bridge`, an AXI-lite backpressure problem, and a UART16550 register/TX problem without perturbing the proven debug hub route.

Build 34 completed on 2026-05-28 with exit code 0. It published `huaprop3_openpiton/debug_build/p3_top_build34_runmgr_uart_ila.pdi` and `p3_top_build34_runmgr_uart_ila.ltx`. The LTX contains the expected `0x000003FFC0000000` debug hub address, `PMC_AXI_NOC0` access path, both `axis_ila_0`/`axis_ila_1` cells, and the UART-local probes `p3_dbg_uart_seen16_i` plus `p3_dbg_uart_bus64_i`. Route status was clean: 148,064 routable nets were fully routed, with 0 routing errors, 0 failed nets, 0 unrouted nets, 0 partially routed nets, and 0 node overlaps. Post-route timing met all user constraints with `WNS` 9.125 ns, `TNS` 0, `WHS` 0.011 ns, and `THS` 0.

Hardware validation passed on 2026-05-28. Programming reported `DONE bit: HIGH`, the debug hub refreshed at `0x3ffc0000000`, and both ILAs triggered/uploaded CSVs. The decoded capture had heartbeat activity, `p3_dbg_top_status16_i = 0xff03`, `p3_dbg_uart_seen16_i = 0x73f3`, and `p3_dbg_uart_bus64_i = 0x11000180840000f9`. The sticky decode shows that core-to-UART NoC traffic, core AXI-lite AW/W plus B response, and UART-side AXI-lite AW/W plus B response all occurred. The TX-low sticky bit remained clear, so the write path reached the UART-side AXI-lite interface but did not produce observed UART serial activity.

One instrumentation caveat matters for the live bus decode: `chipset.v` wraps the chipset implementation bus as `{p3_chipset_impl_debug_bus[55:0], chipset_status[7:0]}` before it reaches `p3_debug_bus[127:64]`. In Build 34 this means `p3_dbg_uart_bus64_i` does not expose raw `uart_top.p3_uart_debug_bus[63:0]`; the original UART `s_axi_wdata[7:0]` field is dropped, and the CSV low byte is reset/clock/status (`0xf9` in the first capture). The next probe should preserve the compact ILA shape but either bypass this wrapper for UART-local payloads or add sticky last-write registers for the accepted UART-side write address/data/strobe, so the bring-up can separate wrong register offset/strobe from UART16550 TX enable/configuration behavior.

### P3 Build 35 UART Last-Write ILAs

Build 35 is the narrow successor to Build 34. It keeps the proven run-manager flow, BD-owned `axis_ila_0`/`axis_ila_1`, and 97-bit probe budget, but changes the UART payload from mostly live signals to sticky last-accepted write fields. The build defines both `P3_BD_UART_DEBUG_ILA` and `P3_BD_UART_WR_DEBUG_ILA`: the first keeps the existing top-level and BD probe ports, while the second selects the last-write payload and bypasses the generic `chipset.v` status-byte wrapper.

Probe mapping remains:

- `axis_ila_0/probe0[0:0]`: `p3_min_dbg_heartbeat[0]`
- `axis_ila_0/probe1[15:0]`: `p3_top_status[15:0]`
- `axis_ila_0/probe2[15:0]`: UART sticky handshakes through `p3_debug_seen[31:16]`
- `axis_ila_1/probe0[63:0]`: raw UART last-write payload through `p3_debug_bus[127:64]`

The 64-bit payload records the last UART-side accepted write data byte, write strobe, write address, last core-side write data byte, core strobe, core write address, UART/core B responses, sticky AW/W/B acceptance bits, and UART TX low/toggle state. This targets the next branch in the bring-up: wrong ns16550 register offset/strobe/data versus a correctly accepted transmit write that still produces no serial TX activity.

Build 35 completed on 2026-05-28 with exit code 0. It published `huaprop3_openpiton/debug_build/p3_top_build35_runmgr_uart_write_ila.pdi` and `p3_top_build35_runmgr_uart_write_ila.ltx`. The LTX contains the expected `0x000003FFC0000000` debug hub address, `PMC_AXI_NOC0` access path, both `axis_ila_0`/`axis_ila_1` cells, and the UART probes `p3_dbg_uart_seen16_i` plus `p3_dbg_uart_bus64_i`. Route status was clean: 148,099 routable nets were fully routed with 0 routing errors. Post-route timing met all user constraints with `WNS` 8.871 ns, `TNS` 0, `WHS` 0.014 ns, and `THS` 0.

Hardware validation showed a narrower runtime failure than the earlier Build 24/25 debug-hub issue. After restarting the remote Vivado Lab 2024.2 `hw_server`, Build 34 could still program, refresh, trigger, upload, and export CSVs. Build 35 programmed and `refresh_hw_device` reached debug hub `0x3ffc0000000`, but AxisILA core access timed out during trigger. Reprogramming Build 34 immediately afterward passed again, so the failure is specific to the Build 35 ILA payload/wrapper interaction rather than the board-level XVC, JTAG, hw_server, LTX, or `PMC_AXI_NOC0` path.

### P3 Build 36 Narrow UART Last-Write ILAs

Build 36 keeps the Build 34/35 BD-owned two-ILA topology but avoids Build 35's raw 64-bit chipset wrapper bypass. It adds `P3_BD_UART_WR_NARROW_DEBUG_ILA`, keeps the normal `chipset.v` status-byte wrapper, and packs the UART write payload into `p3_chipset_impl_debug_bus[55:0]`, which the wrapper preserves as `p3_dbg_uart_bus64_i[63:8]`.

The UART payload is double-registered in `uart_top.v` before it reaches the BD ILA. The preserved 56-bit field contains last UART-side write data/strobe/address low byte, last core-side write data/strobe/address low byte, UART/core B responses, sticky AW/W/B acceptance bits, live/sticky UART TX state, `test_start`, and NoC request/response sticky flags. The low byte of the exported 64-bit ILA probe remains the stable chipset reset/clock/status byte, matching the Build 34 transport behavior.

Use:

```bash
vivado -mode batch -source scripts/p3_build36_runmgr_uart_write_narrow_ila.tcl -tclargs -jobs 1
vivado -mode batch -source scripts/p3_program_pdi.tcl -tclargs huaprop3_openpiton/debug_build/p3_top_build36_runmgr_uart_write_narrow_ila.pdi
vivado -mode batch -source scripts/p3_ila_capture_build36_uart_write_narrow_ila.tcl
```

Build 36 completed on 2026-05-28 with exit code 0. It published `huaprop3_openpiton/debug_build/p3_top_build36_runmgr_uart_write_narrow_ila.pdi` and `p3_top_build36_runmgr_uart_write_narrow_ila.ltx`. The LTX contains the expected `0x000003FFC0000000` debug hub address, `PMC_AXI_NOC0` access path, both `axis_ila_0`/`axis_ila_1` cells, and the UART probes `p3_dbg_uart_seen16_i` plus `p3_dbg_uart_bus64_i`.

Route status was clean: 148,222 routable nets were fully routed with 0 routing errors. Post-route timing met all user constraints with `WNS` 9.015 ns, `TNS` 0, `WHS` 0.022 ns, and `THS` 0. Post-place utilization was 86,831 CLB LUTs, 59,685 CLB registers, 83.5 block RAM tiles, 2 URAMs, and 19 DSP slices.

The next hardware step is to program Build 36 and capture both ILAs. Decode `p3_dbg_uart_bus64_i[63:8]` as the 56-bit narrow UART last-write payload and `p3_dbg_uart_bus64_i[7:0]` as the chipset reset/clock/status byte. A correct UART-side transmit-register write with no TX-low/transition sticky bit would point to ns16550 clock/reset/configuration or baud behavior; an incorrect address, strobe, or byte points back to bootrom/ns16550 register mapping.

Hardware validation did not pass on the first Build 36 attempt. Programming succeeded and `refresh_hw_device` reached debug hub `0x3ffc0000000`, but AxisILA access timed out when triggering `u_bd/openpiton_top_i/axis_ila_0`. Reprogramming Build 34 immediately afterward, without restarting `hw_server`, still refreshed and captured both ILAs successfully. Treat Build 36 as a design-specific ILA runtime failure, not as a board, XVC, JTAG, hw_server, PDI, LTX, or `PMC_AXI_NOC0` infrastructure failure. The next check is to compare routed DCP properties for Build 34 and Build 36 debug hubs, ILA clocks/resets, and probe nets.

### P3 Build 37 Live-Narrow UART ILAs

Build 37 is the isolation step after Build 35 and Build 36 both timed out during AxisILA runtime access. It keeps the Build 34 BD-owned two-ILA topology and does not define `P3_BD_UART_WR_DEBUG_ILA`. Instead, it adds a live payload selector that packs the current UART-side and core-side write address/data/strobe/response fields plus existing sticky handshake bits into `p3_chipset_impl_debug_bus[55:0]`, so the normal `chipset.v` status-byte wrapper remains in place.

This build deliberately avoids the registered last-write debug bus. If it captures like Build 34, then the failure is tied to the registered last-write payload path used by Build 35/36. If it times out like Build 35/36, then the failure is tied to payload remapping or ILA payload content more generally.

Build 37 completed synthesis through `route_design` on 2026-05-29, but the run-manager flow failed in `write_device_image`. Route status was clean: 148,083 routable nets were fully routed with 0 routing errors. Post-route timing met all user constraints with `WNS` 8.964 ns, `TNS` 0, `WHS` 0.020 ns, and `THS` 0. Post-place utilization was 86,919 CLB LUTs, 59,540 CLB registers, 83.5 block RAM tiles, 2 URAMs, and 19 DSP slices.

The failure was the same PLM/BSP path class as Build 32, not an implementation failure: after route, HSI failed copying `standalone_v9_2/.../translation_table.S` into the run-directory BSP, then XilPM compilation missed `xstatus.h`. The source file exists under `D:/Xilinx/Vivado/2024.2/data/embeddedsw`, so `scripts/p3_recover_build37_outputs.tcl` recovers PDI/LTX from `impl_37_uartlivenarrowila/p3_top_routed.dcp` using the short working directory `Z:/tmp/p3_b37_recover`. The script validates that the generated LTX still contains `0x000003FFC0000000`, `PMC_AXI_NOC0`, `axis_ila_0`, `axis_ila_1`, `p3_dbg_uart_seen16_i`, and `p3_dbg_uart_bus64_i` before publishing outputs. The first recovery run completed successfully and published `huaprop3_openpiton/debug_build/p3_top_build37_runmgr_uart_live_narrow_ila.pdi` plus `.ltx`.

Hardware validation passed after recovery. Build 37 programmed with `DONE bit: HIGH`, refreshed the debug hub at `0x3ffc0000000`, enumerated both BD-owned ILAs, and exported CSVs for both immediate triggers. The capture showed `p3_dbg_top_status16_i = 0xff03`, `p3_dbg_uart_seen16_i = 0x73f3`, and `p3_dbg_uart_bus64_i = 0x20110201100fe7f9`. Decoding the live-narrow payload gives UART-side and core-side `wdata=0x20`, `wstrb=1`, `awaddr_low=0x10`, OKAY B responses, `uart_tx=1`, and no TX-low sticky event. This isolates the Build 35/36 hardware timeout to the registered last-write payload path while keeping the no-UART-output debug focused on ns16550 register mapping/configuration/initialization.

### P3 Build 43 AXI16550 No-DDR BootROM

Build 43 is the original-UART no-stack bootrom test. It keeps `PITON_UART16550`, explicitly rejects the SiFive/TLUART macros, and compiles only `startup_asm_uart16550.S` through `BOOTROM_MODE=asm_uart16550`. The bootrom initializes the ns16550 registers through CPU-visible byte offsets at `0xfff0c2c000`, polls `LSR[5]`, prints `B43 AXI16550\r\n`, then repeatedly transmits `A`.

Build and validate with:

```bash
vivado -mode batch -source scripts/p3_build43_asm_uart16550.tcl -tclargs -jobs 1
vivado -mode batch -source scripts/p3_program_pdi.tcl -tclargs huaprop3_build43_asm_uart16550/debug_build/p3_top_build43_asm_uart16550.pdi
vivado -mode batch -source scripts/p3_ila_capture_build43_asm_uart16550.tcl
python3 scripts/p3_decode_build43_ila_csv.py huaprop3_build43_asm_uart16550/debug_build
```

The expected decision point is simple: visible serial output proves the complete Ariane bootrom to original AXI16550 physical TX path. If serial remains silent, decode the Build 43 live-narrow UART ILA to separate missing core-side writes, missing UART-side writes, bad response/strobe/address, and a configured UART IP that still never toggles `uart_tx`.

### P3 Build 39 SiFive UART Project Variant

Build 39 creates a separate `huaprop3_sifive_uart` Vivado project instead of modifying the known Build 38 `huaprop3_openpiton` project in place. The project is generated with `scripts/p3_create_bd_sifive_uart.tcl`, which delegates to the normal P3 BD creator while setting `P3_ENABLE_SIFIVE_UART=1`.

The SiFive variant does not create the Xilinx `axi_uart16550` IP and does not define `PITON_UART16550`. It adds the reference `TLUART` RTL and defines `P3_SIFIVE_UART`, causing `uart_top.v` to instantiate the RTL wrapper and bypass the old `<< 2 | 13'h1000` ns16550 address transform. The bridge maps 32-bit AXI4-Lite accesses to the generated 64-bit TileLink-UL register beats, preserving the SiFive offsets `0x00/0x04/0x08/0x0c/0x10/0x14/0x18`.

The expected build sequence is:

```bash
scripts/p3_rebuild_sifive_bootrom.sh
vivado -mode batch -source scripts/p3_build39_sifive_uart.tcl -tclargs -jobs 1
```

For software payload validation, rebuild BBL with `scripts/p3_rebuild_sifive_bbl.sh` after the DTS and riscv-pk SiFive UART changes are in place. The first hardware success criterion is still bootrom text on `/dev/ttyUSB0` at 115200; BBL/Linux console output is the second gate.

Build 39 completed on 2026-05-29 with exit code 0. It published `huaprop3_sifive_uart/debug_build/p3_top_build39_sifive_uart.pdi` and `p3_top_build39_sifive_uart.ltx`. Final route status was clean with 0 failed, unrouted, partially routed, or overlapping nets. Post-route timing met all user constraints with `WNS` 9.084 ns, `TNS` 0, `WHS` 0.019 ns, `THS` 0, `WPWS` 0.063 ns, and `TPWS` 0.

Hardware validation did not produce serial output. Programming the Build 39 PDI through remote `hw_server 100.93.77.36:3121` and XVC `202.197.4.99:2540` succeeded with `DONE bit: HIGH`, but a 300-second `/dev/ttyUSB0` capture at 115200, started before programming, returned no characters. Treat this as evidence that the remaining failure is upstream of, or inside, the new SiFive UART transaction path: reset/clock/fetch/bootrom progress and AXI4-Lite/TL bridge handshakes need ILA visibility before changing the physical UART assumptions again.

The minimal Build 39 ILA still validates the runtime debug path. Hardware Manager reached `0x3ffc0000000`, enumerated `u_bd/openpiton_top_i/axis_ila_0`, and exported `ila_capture_build39_sifive_uart_axis_ila_0.csv`. The heartbeat increments, and `p3_dbg_status_i=0x25017f00` decodes as Build ID `0x2501`, top reset deasserted, `peripheral_aresetn=1`, `sd_resetn=1`, UART TX/RX idle high, `sd_cd=1`, and `leds=3`. The next Build 40-style payload should preserve this small BD-owned ILA shape but replace the two minimal probes with Ariane reset/fetch/bootrom and SiFive UART bridge valid/ready/status signals.

### P3 Build 40 SiFive UART Narrow Debug ILAs

Build 40 uses the separate `huaprop3_sifive_uart_debug` project. It keeps the Build 39 SiFive TLUART replacement and adds only a small BD-owned debug payload:

- `axis_ila_0/probe0[0]`: heartbeat bit from `p3_min_dbg_heartbeat[0]`
- `axis_ila_0/probe1[15:0]`: `p3_top_status[15:0]`, covering top reset, chip/chipset reset, UART pins, top-level NoC/AXI activity, and selected UART sticky bits
- `axis_ila_0/probe2[15:0]`: UART sticky seen bits from `uart_top`
- `axis_ila_0/probe3[15:0]`: chip/tile sticky seen bits from `p3_debug_seen[15:0]`
- `axis_ila_1/probe0[63:0]`: SiFive UART AXI4-Lite/TL bridge payload

The Build 40 bridge payload decodes as: `[63:56] last AXI address low byte`, `[55:48] last write data byte`, `[47:40] last read data byte`, `[39:36] last write strobe`, `[35] AW pending`, `[34] W pending`, `[33] AR pending`, `[32] B valid`, `[31] R valid`, `[30] TL A valid`, `[29] TL A ready`, `[28] TL D valid`, `[27] UART TX`, `[26] TX low sticky`, `[25] TX transition sticky`, `[24] UART interrupt`, and `[23:0]` reserved zero.

The Build 40 UART sticky seen bits decode as: `[15] interrupt`, `[14] DIV write`, `[13] TXCTRL write`, `[12] TXDATA write`, `[11] TX transition`, `[10] TX low`, `[9] AXI R fire`, `[8] AXI B fire`, `[7] TL read fire`, `[6] TL write fire`, `[5] TL D valid`, `[4] TL A ready`, `[3] TL A valid`, `[2] AXI AR fire`, `[1] AXI W fire`, and `[0] AXI AW fire`.

### P3 Build 41 Fetch/Bootrom Debug ILAs

Build 41 uses `huaprop3_build41_debug` and keeps the BD-owned debug path while splitting the payload into three small ILAs. Program and capture with:

```bash
vivado -mode batch -source scripts/p3_program_pdi.tcl -tclargs huaprop3_build41_debug/debug_build/p3_top_build41_fetch_debug.pdi
vivado -mode batch -source scripts/p3_ila_capture_build41_fetch_debug.tcl
python3 scripts/p3_decode_build41_ila_csv.py huaprop3_build41_debug/debug_build
```

Hardware validation passed at the debug-transport level on 2026-05-30. Programming reported `DONE bit: HIGH`; `refresh_hw_device` reached debug hub `0x3ffc0000000`; Vivado enumerated `axis_ila_0`, `axis_ila_1`, and `axis_ila_2`; and immediate trigger/upload exported all three 1024-sample CSV files.

The decoded capture was stable except for the heartbeat bit: `p3_dbg_top_status16_i=0xff03`, chipset sticky seen `0x7fff`, chip/tile sticky seen `0x7fff`, core payload `0xfff101017083f407`, and chipset payload `0x00000006ecfff5f9`. The core payload records a last L1.5 address of `0xfff1010170`, request type `0x10`, request size `0x3`, released Ariane reset flags, and live L1.5 reset/clock flags.

Decode the chipset payload through the outer `chipset.v` wrapper: `{p3_chipset_impl_debug_bus[55:0], status[7:0]}`. For the Build 41 capture, this gives wrapper status `0xf9`, inner payload `0x00000006ecfff5`, last retained chip-to-chipset data byte `0x00`, bootrom request low16 `0x0000`, bootrom response low16 `0x06ec`, and sticky flags `0xfff5`. The corrected flags show UART path activity, memory AXI request activity, bootrom NoC activity, chipset reset released, `cpu_mem_traffic=1`, and `invalid_access=0`.

Serial validation still failed: two `/dev/ttyUSB0` captures at 115200, including a 480-second capture opened before reprogramming, produced no output. Treat this as evidence against reset-held, dead-clock, and missing-bootrom-fetch explanations. The next probe should expose the exact SiFive UART write/read address, write data, write strobe, and TX low/transition state again, now correlated with the proven bootrom fetch/response path.

### P3 Build 42-A No-Stack ASM UART

Build 42-A is a no-stack SiFive UART smoke image for the full OpenPiton/Ariane path. Rebuild the bootrom, build the PDI, program, capture serial, and decode ILAs with:

```bash
scripts/p3_rebuild_build42a_asm_uart.sh
vivado -mode batch -source scripts/p3_build42a_asm_uart.tcl -tclargs -jobs 1
vivado -mode batch -source scripts/p3_program_pdi.tcl -tclargs huaprop3_build42a_asm_uart/debug_build/p3_top_build42a_asm_uart.pdi
vivado -mode batch -source scripts/p3_ila_capture_build42a_asm_uart.tcl
python3 scripts/p3_decode_build42a_ila_csv.py huaprop3_build42a_asm_uart/debug_build
```

The bootrom mode `BOOTROM_MODE=asm_uart` only compiles `startup_asm_uart.S`. The image does not set `sp`, does not call C, and does not touch DDR or the SMP barrier. It initializes the SiFive UART with `DIV=259`, enables TX/RX, polls `TXDATA[31]`, and repeatedly writes ASCII `A`.

The Build 42-A Vivado flow defines `P3_BD_UART_RAW_DEBUG_ILA`, so `axis_ila_1` captures the raw SiFive UART debug payload instead of the normal chipset status-byte wrapper. Decode fields are last AXI address byte, last write byte, last read byte, write strobe, pending/valid flags, UART TX, TX-low sticky, TX-transition sticky, and interrupt.

When this flow is launched through the local Windows Vivado wrapper from WSL, Tcl may see project paths as `Z:/home/...`. Any subprocess call back into WSL bash must translate that path form back to `/home/...`; `scripts/p3_build42a_asm_uart.tcl` does this before invoking `p3_rebuild_build42a_asm_uart.sh`.

The same subprocess also redirects stderr into stdout. Tcl `exec` treats any unredirected stderr output as an error even when the child exits successfully, which is too strict for the bootrom rebuild because WSL path notices and `dtc` warnings can appear on stderr during an otherwise valid image generation.

Build 42-A completed on hardware on 2026-05-30. The image routed cleanly, produced `p3_top_build42a_asm_uart.pdi/.ltx`, programmed with `DONE bit: HIGH`, and refreshed both ILAs through debug hub `0x3ffc0000000`. The 480-second `/dev/ttyUSB0` capture still produced no output.

Decoded ILAs showed heartbeat activity, `top_status=0xff03`, UART sticky seen `0xffff`, chip/tile sticky seen `0x7fff`, and raw UART live bus `0x000000f008000000`. In the current decoder this means the sampled live raw bus is idle (`uart_tx=1`, no TX-low or TX-transition, no live AXI/TL pending/valid) even though the sticky UART seen vector latched activity. Do not treat Build 42-A as proof of a DDR stack failure: the no-stack assembly image does not touch DDR and still cannot print. The next build should improve the raw UART bridge probes or fix the AXI4-Lite to TileLink address/data retention path before attempting the BRAM-stack Build 42-B branch as a DDR isolation test.

### P3 Build 42-B BRAM Stack Control

Build 42-B is a control experiment for the normal C bootrom with a P3-only on-chip stack window. Rebuild, build, program, capture, and decode with:

```bash
scripts/p3_rebuild_build42b_bram_stack.sh
vivado -mode batch -source scripts/p3_build42b_bram_stack.tcl -tclargs -jobs 1
vivado -mode batch -source scripts/p3_program_pdi.tcl -tclargs huaprop3_build42b_bram_stack/debug_build/p3_top_build42b_bram_stack.pdi
vivado -mode batch -source scripts/p3_ila_capture_build42b_bram_stack.tcl
python3 scripts/p3_decode_build42b_ila_csv.py huaprop3_build42b_bram_stack/debug_build
```

The hardware path is intentionally not a BD address-map rewrite. `P3_BUILD42B_BRAM_STACK` inserts `p3_axi_stack_bram` between `openpiton_wrapper` and the BD AXI NoC. The interposer responds only to AXI `0x03ff0000..0x04000000`, which corresponds to CPU `0x83ff0000..0x84000000` after OpenPiton subtracts `0x80000000` from DDR addresses. CPU `0x80000000` remains routed to DDR so the existing SD/BBL load buffer is not hidden by the stack experiment.

## Key Reports

- `report_utilization` -- resource usage per hierarchy
- `report_timing_summary` -- WNS/TNS
- `report_route_status` -- congestion level
- `report_power` -- estimated power consumption

## Tips

- `PITON_SKIP_ARIANE_FW_BUILD=1` to skip firmware in protosyn
- Use OOC (out-of-context) synthesis for tile module to speed up iteration
- Incremental implementation can save hours on large designs

## Scaling Considerations

- Build time grows super-linearly with core count
- 16-core builds may take 12+ hours
- Consider batch submission for overnight runs
