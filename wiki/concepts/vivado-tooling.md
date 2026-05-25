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
| `p3_uart_direct_build.tcl` | Top-level `uart_tx/uart_rx` outside the BD | `DIRECT` |
| `p3_uart_bd_build.tcl` | BD external ports `uart_txd/uart_rxd` | `BDPATH` |

Both use the same physical pins (TX=CW58, RX=CW59) and a small 30 MHz clock/reset BD so DDR, SD, and OpenPiton are not part of the test. Program either result with:

```bash
vivado -mode batch -source scripts/p3_program_pdi.tcl -tclargs <path-to-pdi>
```

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
