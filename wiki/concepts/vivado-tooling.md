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

Implementation note: Ariane/CVA6 instantiates the `unread` helper from `common_cells` in frontend logic (`bht`, `btb`, and `instr_queue`). The upstream helper is intentionally an input-only empty module. In the P3 Vivado flow, adding that source is not sufficient: clean synthesis still preserves seven `unread` leaves as black boxes, and `opt_design` can later fail DRC `INBB-3`. Build 24 therefore uses `piton/design/xilinx/huaprop3/unread_vivado_impl.sv`, a tiny LUT sink implementation of `unread`, instead of the empty common_cells source.

Implementation note: after adding `unread.sv`, check `synth_1/runme.log` for the incremental synthesis summary. If Vivado reports 100% reuse and `Report BlackBoxes` still lists `unread`, the project is reusing a stale `utils_1/imports/synth_1/p3_top.dcp`. Build 24 disables `synth_1` incremental checkpoint properties and removes that imported DCP from the project before launching synthesis so the added Ariane source is actually elaborated into the output checkpoint. Use numeric `0`, not Tcl string `false`, for Vivado's `AUTO_INCREMENTAL_CHECKPOINT` run property.

Implementation note: on 2026-05-26, both the WSL project and a `save_project_as` copy under Windows `%TEMP%` stalled inside `launch_runs impl_1 -scripts_only` before creating `impl_1/runme.*`. Direct `open_checkpoint` of the completed 99 MB `p3_top.dcp` also went idle after loading `xcvp1902-vsva6865-1MP-e-S`. `scripts/p3_build24_direct_flow.tcl` is the fallback for this case: it sources the generated `synth_1/p3_top.tcl` so synthesis remains in the same Vivado process, inserts the RTL debug ILA, reads the OOC IP DCPs into their black-box cells, and then runs `opt_design` through `write_device_image` without run manager or DCP reopen.

Implementation note: the direct fallback should locate OOC/IP cells by synthesized `REF_NAME`, not by fixed BD hierarchy. A 2026-05-26 direct run completed synthesis and connected the explicit top-level debug nets, but failed before `opt_design` because `u_bd/openpiton_top_i/axi_noc_0` was no longer a valid cell path after synthesis. The fallback script now reads `openpiton_top_axi_noc_0_0`, `openpiton_top_clk_wizard_0_0`, `openpiton_top_proc_sys_reset_0_0`, and `uart_16550` DCPs into the matching black-box cells by `REF_NAME`; it also supports `-reuse_synth` to continue from `debug_build/build24_direct/p3_top.dcp` without another full synthesis pass.

Implementation note: after the OOC/IP DCPs are stitched, Vivado may still report implementation-time black boxes for debug and Versal hard-IP wrappers such as `axi_dbg_hub`, `u_ila_0`, `axi_noc`, and `proc_sys_reset`. These are expected at this point in the direct flow and should be logged, not treated like unresolved RTL modules. The direct script fails only if any other black-box `REF_NAME` remains.

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
