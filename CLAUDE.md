# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Goal

**Run Quicksilver on a 1000-core OpenPiton manycore and measure parallel speedup.**

Deployment path: validate single-core first, then incrementally scale up.

| Phase | Config | Milestone |
|-------|--------|-----------|
| P0 | 1x1 (1 core) | Linux boots, Quicksilver runs correctly on single core |
| P1 | 2x2 (4 cores) | Multi-core cache coherence validated |
| P2 | 4x4 (16 cores) | Speedup measurement baseline |
| P3 | 8x8 (64 cores) | Large-FPGA or multi-FPGA prototype |
| P4 | 32x32 (1024 cores) | Kilo-core target, final speedup measurement |

## Wiki

A project wiki is maintained at `wiki/` in the repository root. See `wiki/INDEX.md` for the full index.

```
wiki/
├── INDEX.md                    ← project homepage + quick reference + timeline
├── concepts/                   ← 11 core concept articles
│   ├── architecture-evolution.md
│   ├── timing-closure.md
│   ├── routing-congestion.md
│   ├── resource-estimation.md
│   ├── ram-mapping-tradeoff.md
│   ├── slr-layout.md
│   ├── simulation.md
│   ├── rtl-coding-rules.md
│   ├── vivado-tooling.md
│   ├── asic-extrapolation.md
│   ├── rtl-asic-port.md
│   └── p3-migration-guide.md
├── devlog/                     ← monthly dev logs, append-only, newest first
└── *.canvas                    ← Obsidian Canvas topology diagrams
```

## R1: Mandatory Wiki Sync Rule

**Every code change MUST include corresponding wiki updates. No exceptions. No "sync later".**

### R1-A: Devlog DAILY Rule (ABSOLUTE — never break this)

**CRITICAL: The devlog is a running journal, not a post-hoc report. You MUST write a devlog entry EVERY calendar day that ANY debugging, synthesis, implementation, or programming work occurs. This is NOT optional.**

1. **Before starting a new build** — check if today already has a devlog entry. If not, write one summarizing what was achieved yesterday/today before launching.
2. **After every synthesis failure or implementation error** — immediately append a devlog entry describing the error and the fix attempted. Do NOT wait for the next build to finish.
3. **After every successful programming** — note the build number, PDI path, device status (DONE bit, ILA data, serial output).
4. **Before ending a conversation session** — confirm the devlog is up to date through the current calendar day. If the conversation spans midnight, there MUST be an entry for each day.
5. **Root cause discoveries** — the moment a non-obvious root cause is identified (especially via ILA or other HW debug tools), write it to the devlog immediately. These are the most valuable entries.

**Anti-pattern that triggers this rule being strengthened**: Building 15+ FPGA images across 3 calendar days without a single devlog entry. This must never happen again.

### R1-B: Trigger Conditions (when wiki sync is REQUIRED)

1. **RTL change** -- update the relevant `concepts/` article (resource estimates, timing notes, coding rules, etc.)
2. **New board / platform port** -- update `architecture-evolution.md`, `resource-estimation.md`, and add devlog entry
3. **Build flow / tooling change** -- update `vivado-tooling.md` or `simulation.md`
4. **Scaling milestone reached** -- update `INDEX.md` timeline, add devlog entry
5. **Bug fix that revealed a non-obvious root cause** -- add to the relevant concept article's "Pitfalls" or "Lessons" section, AND add devlog entry
6. **New FPGA synthesis results** -- update `resource-estimation.md` and/or `timing-closure.md` with actual numbers
7. **Device tree / address map change** -- this is already covered by CLAUDE.md's address consistency rule, but also update wiki if it affects scaling design
8. **Any decision that affects the P0-P4 roadmap** -- update `INDEX.md` timeline

### R1-C: Anti-Patterns (NEVER do these)

- **"I'll update the wiki in a follow-up"** -- No. Wiki sync is part of the change, not a separate task.
- **"I'll write the devlog after this build finishes"** -- No. Write it NOW. The build runs in the background.
- **Wiki article with only a title and "TBD"** -- Every article must have at least a one-paragraph summary of current understanding. Stub sections within an article are OK if labeled `(TBD)`.
- **Devlog entries without dates** -- Every devlog entry must have an ISO date heading.
- **Updating code numbers without updating wiki numbers** -- If you change resource usage, clock frequencies, timing results, or core counts in code/constraints, the wiki MUST reflect the new values in the same commit.
- **Orphan wiki articles** -- Every article must be linked from `INDEX.md`.
- **Deleting wiki content without replacement** -- If information is outdated, update it; don't delete it. Mark superseded info with `~~strikethrough~~` and add the replacement.
- **Crossing a calendar day boundary without a devlog entry** -- If any FPGA work occurred that day, there MUST be a devlog entry.

### R1-D: Devlog Rules

- File naming: `devlog/YYYY-MM.md` (one file per month)
- Entries are append-only, newest first within each file
- Each entry: `## YYYY-MM-DD -- <short title>` followed by bullet points
- Never edit past entries (append corrections as new entries)
- Entries should include build numbers, error codes, root cause analysis, and PDI file paths

## Environment Setup

```bash
export PITON_ROOT=/home/illya/openpiton
source $PITON_ROOT/piton/piton_settings.bash
```

For RISC-V (Ariane) builds, also source `piton/ariane_setup.sh` which requires a RISCV toolchain at `$HOME/scratch/riscv_install`. Run `piton/ariane_build_tools.sh` on first setup.

Synopsys VCS (primary simulator) requires `VCS_HOME` set. Also supported: Icarus Verilog, Verilator, ModelSim, Riviera-PRO, NC-Verilog. See README.md for dependency troubleshooting (32-bit glibc, libelf, Perl Bit::Vector).

## Target Platform: AX7203

The current prototyping target is **AX7203** (ALINX, Artix-7 `XC7A200T-2FBG484I`). Board-level configuration:

- **FPGA:** XC7A200T-2FBG484I (FBG484, speed grade -2, industrial)
- **DDR3:** 2x MT41J256M16HA-125, 32-bit bus, 1 GB total (Banks 34/35, 1.5V)
- **System clock:** 200 MHz differential (SYS_CLK_P=R4, SYS_CLK_N=T4)
- **Chipset clock:** 30 MHz (derived from MMCM)
- **UART:** CP2102GM USB-UART, 115200 8N1 (UART1_RXD=P20, UART1_TXD=N15)
- **SD card:** MicroSD slot (CLK=AB12, CMD=AB11, DAT0=AA13, CD=F14)
- **Reset:** Active-low pushbutton (RESET_N=T6, Bank 34, LVCMOS15)
- **LEDs:** Core-board LED1=W5 (1.5V); expansion LEDs B13/C13/D14/D15 (3.3V, active-low)
- **Pin reference:** `/home/illya/openpiton/resource.md`

### FPGA Build (WSL + Windows Vivado)

Vivado 2024.2 runs on Windows (`D:\Xilinx\Vivado\2024.2`), invoked from WSL via wrapper `/home/illya/bin/vivado`. The standard `protosyn` flow works but requires:

```bash
source $PITON_ROOT/piton/piton_settings.bash
export PITON_SKIP_ARIANE_FW_BUILD=1  # skip firmware build (done manually)
protosyn -b a7203x -d system --core=ariane --uart-dmw ddr
```

With `PITON_SKIP_ARIANE_FW_BUILD=1`, bootrom SV files must be built manually before synthesis (see Bootrom section below).

### P3 Offline Ubuntu Vivado Build Host

For P3 Pro / VP1902 scaling builds, use the offline Ubuntu machine as the real Vivado build host. The remote Windows machine is only an SSH TCP jump host; do not run long nested commands such as `ssh windows "ssh ubuntu '...'"`, because Windows should not parse build scripts, shell quoting, or Tcl.

Known endpoints and paths:
- Jump host: `23178@100.70.176.125`
- Build host: `cs@202.197.4.150`
- Remote workspace: `/home/cs/openpiton`
- Remote Vivado: `/media/d1/Xilinx/Vivado/2024.2/bin/vivado` (validated as 2024.2.2)

Standard access pattern:

```bash
ssh -J 23178@100.70.176.125 cs@202.197.4.150

scp -o ProxyJump=23178@100.70.176.125 <local-file-or-archive> \
  cs@202.197.4.150:/home/cs/openpiton/

ssh -J 23178@100.70.176.125 cs@202.197.4.150 \
  'cd /home/cs/openpiton && /media/d1/Xilinx/Vivado/2024.2/bin/vivado -mode batch -source <script>.tcl'
```

Transfer sources to `/home/cs/openpiton` only when starting a real remote build. Generate `bit` / `pdi` / `ltx` / reports / logs on offline Ubuntu, then retrieve artifacts with the same `scp -o ProxyJump=...` path. Do not store passwords in repository files or helper scripts.

### P3 Build 68 64-Core OpenSBI/Linux

The current P3 Pro direction is direct 8x8 / 64-core Linux boot on VP1902. Build 68 switches the 64-core path from BBL to an OpenSBI `fw_jump` bundle:

```bash
vivado -mode batch -source scripts/p3_build68_8x8_opensbi_linux.tcl -tclargs -jobs 16
scripts/p3_prepare_64core_opensbi_image.sh
```

The hardware wrapper sets `PITON_X_TILES=8`, `PITON_Y_TILES=8`, and `PITON_NUM_TILES=64`, keeps self-contained source snapshots, and rebuilds the bootrom with `BOOTROM_MODE=opensbi_bundle`. The SD image is generated from `riscv64-linux-64core-src-20260610.tar.gz` and contains a 512-byte `P3OS`/`BI64` bundle header followed by OpenSBI, Linux `Image`, DTB, and initramfs payloads.

Default DDR layout:
- OpenSBI `fw_jump.bin`: `0x80000000`
- Linux `Image`: `0x80200000`
- DTB: `0x88000000`
- initramfs: `0x90000000`

The Build 68 rebuild step must generate both ROM modules used by `riscv_peripherals.sv`: `bootrom/baremetal/bootrom.sv` for the baremetal ROM instance and `bootrom/linux/bootrom_linux.sv` for the OpenSBI bundle ROM. Even when `ariane_boot_sel_i` selects the Linux/OpenSBI path, Vivado still elaborates the baremetal `bootrom` instance. Remote clean archives must not depend on stale untracked generated ROM files left in a local workspace. Generate the companion baremetal ROM from an inline minimal DTS, not by invoking `riscvlib.py` or following `bootrom/baremetal/rv64_platform.dts`, because the remote source archive intentionally lacks `.git` metadata and the symlink target `bootrom/rv64_platform.dts` is an ignored generated file.

`P3_64CORE_USE_PREBUILT=1 scripts/p3_prepare_64core_opensbi_image.sh` is only a local image-structure smoke test. The board candidate should rebuild OpenSBI/Linux on offline Ubuntu so `FW_JUMP_ADDR=0x80200000` and `FW_JUMP_FDT_ADDR=0x88000000` are correct for P3.

Remote Ubuntu toolchain state as of 2026-06-11: `gcc-riscv64-unknown-elf` 10.2.0, `binutils-riscv64-unknown-elf` 2.35.1, `device-tree-compiler` 1.6.1, and `libfdt1` are installed on `cs@202.197.4.150`. Build 68 requires `riscv64-unknown-elf-gcc` during bootrom rebuild before Vivado project creation.

For Jammy's system-packaged `riscv64-unknown-elf-gcc`, `picolibc-riscv64-unknown-elf` supplies headers such as `stdint.h`. Build 68 passes that include path through `P3_BOOTROM_EXTRA_CFLAGS` when the OpenPiton scratch toolchain is absent, while keeping the bootrom `-nostdlib`/`-nostartfiles` link model.

`scripts/p3_create_bd.tcl` prepends `${repo}/piton/tools/bin` to Vivado Tcl `env(PATH)` so the common PyHP preprocessing helper can execute `pyhp.py` by name on the offline Ubuntu host.

`scripts/p3_remote_vivado_64core.sh` archives the committed top-level repository state plus committed recursive submodule HEAD contents. It intentionally does not package dirty tracked submodule changes; it now fails before packing if any recursive submodule has staged or unstaged tracked diffs. Commit and push submodule RTL fixes, then update the superproject gitlink, before launching a remote Build 68 run.

Build 68 remote runs default to `JOBS=16`; use `JOBS=<N> scripts/p3_remote_vivado_64core.sh` only when deliberately comparing runtime or stability. The 2026-06-12 active run used `-jobs 8`, and Vivado reported up to 7 synthesis processes and up to 8 CPUs for place/route. The offline Ubuntu host has 384 logical CPUs, 192 physical cores, and 1.5 TiB RAM. `JOBS=32` is the current practical upper bound for the next controlled experiment; do not use 64+ as the default until a 16/32 comparison is collected and file-descriptor pressure is checked (`ulimit -n` was 1024). The shared Build 52 wrapper sets `general.maxThreads` and `synth.maxThreads` before top synthesis/place/route, then keeps the generated child-IP synthesis serialization workaround after top synthesis.

### Key Board Files

| File | Purpose |
|------|---------|
| `piton/design/xilinx/a7203x/constraints.xdc` | Pin constraints & timing |
| `piton/design/xilinx/a7203x/devices.xml` | SPARC device map |
| `piton/design/xilinx/a7203x/devices_ariane.xml` | Ariane device map |
| `resource.md` (repo root) | AX7203 board pin reference |

## Ariane/CVA6 Boot Chain (SD Card)

The boot sequence for Linux on AX7203:

1. **Bootrom (ZSBL)** — `piton/design/chipset/rv64_platform/bootrom/linux/`
   - Inits UART, prints banner, reads SD via SPI, loads BBL to DDR `0x80000000`
   - Passes DTB address via `a1` register
   - Built with `riscv64-unknown-elf-gcc` 7.2.0 from `$HOME/scratch/riscv_install/bin/`
   - Build flags: `-DMAX_HARTS=1 -DUART_FREQ=30000000 -Os -march=rv64imac -mabi=lp64 -mcmodel=medany -mexplicit-relocs`
   - Output: `bootrom_linux.sv` (Verilog ROM init file)

2. **BBL (riscv-pk)** — on SD card at sector 2048 (GPT partition)
   - Contains embedded Linux kernel payload
   - Reads DTB from `a1` (passed by bootrom, NOT its own compiled-in DTB)
   - Source: `build/a7203x/ariane-sdk/riscv-pk/`
   - Build with `-fno-stack-protector -U_FORTIFY_SOURCE`

3. **Linux kernel** — embedded in BBL as payload section

### SD Card Layout

```
Sector 0-2047: GPT header
Sector 2048+:  bbl.bin (BBL + Linux payload, ~15 MB)
```

Write with: `sudo dd if=bbl_new.bin of=/dev/sdX bs=512 seek=2048 conv=fsync`

### Device Tree

Custom DTS for AX7203: `build/a7203x/a7203x.dts`
- 1 Ariane core, 30 MHz clock, timebase 234375 Hz (30M/128)
- 1 GB memory at 0x00000000
- PLIC at 0xff_d1100000
- UART (ns16550) at 0xff_f0c2c000, clock-frequency 30 MHz

Compile: `dtc -I dts -O dtb -o a7203x.dtb a7203x.dts`

The DTB is embedded in the bootrom (`rv64_platform.dtb` → compiled into `bootrom_linux.sv`).

## Build & Simulation

All commands run from `$PITON_ROOT/build`.

```bash
# Build a 1x1 tile simulation model
sims -sys=manycore -x_tiles=1 -y_tiles=1 -vcs_build

# Build with minimal monitor output
sims -sys=manycore -x_tiles=1 -y_tiles=1 -vcs_build -config_rtl=MINIMAL_MONITORING

# Run a single assembly test (model must be built first)
sims -sys=manycore -x_tiles=1 -y_tiles=1 -vcs_run princeton-test-test.s

# Build and run a regression group
sims -sim_type=vcs -group=tile1_mini

# Process regression results
cd <date>_<id> && regreport $PWD > report.log

# Run continuous integration bundle (requires job queue like SLURM/PBS)
contint --bundle=git_push
```

## Architecture

OpenPiton is a tiled manycore processor with a distributed directory-based cache coherence protocol over a 2D mesh NoC. It supports both SPARC v9 (OpenSPARC T1-derived) and RISC-V (Ariane/CVA6) cores.

### Tile Organization (`piton/design/chip/tile/`)

Each tile is the fundamental unit replicated across the mesh:

- **sparc/** — SPARC v9 core. Subunits: `ifu/` (instruction fetch), `exu/` (execution), `lsu/` (load-store), `tlu/` (trap logic), `ffu/` (FPU), `spu/` (stream processing), `mul/` (multiplier)
- **ariane/** — RISC-V 64-bit core (CVA6). Key files in `core/`: `ariane.sv`, `cva6.sv`, pipeline stages (`id_stage.sv`, `issue_stage.sv`, `ex_stage.sv`, `commit_stage.sv`), `csr_regfile.sv`, `frontend/`, `cache_subsystem/`, `mmu_sv39/`, `fpu/`
- **l15/** — Per-tile L1.5 cache. Bridges the core to the NoC. Key files: `l15.v`, `l15_pipeline.v.pyv`, `l15_wrap.v`
- **l2/** — Distributed L2 cache slice (directory-based coherence). Key files: `l2.v`, `l2_pipe1.v`/`l2_pipe2.v` (pipeline stages), `l2_dir.v` (directory), `l2_tag.v`, `l2_data.v`, `l2_mshr.v.pyv` (miss status handling registers)
- **dynamic_node/** — NoC router for the 2D mesh. Key files: `dynamic_node_top.v`, `dynamic_node_top_wrap.v`
- **common/** — Tile-level shared Verilog (e.g., SRAM wrappers)
- **fpu/** — Shared FPU (used by SPARC)
- **pico/** — Pico (alternative lightweight core)
- **dmbr/** — Distributed memory barrier module
- **rtap/** — Router test access port

### Chip-Level (`piton/design/chip/`)

- **rtl/chip.v.pyv** — Top-level chip module instantiating the tile array and interconnects
- **chip_bridge/** — Die-to-die communication bridges for chiplet scaling

### Chipset (`piton/design/chipset/`)

Off-chip interfaces and peripherals: memory controller (`mc/`), IO crossbar (`io_xbar/`), UART, SPI, AXI bridges, NoC-to-off-chip bridges.

### Adding a New Board

Each board requires its own `devices_ariane.xml` (for Ariane) or `devices.xml` (for SPARC) under `piton/design/xilinx/<board>/`. This file defines the IO crossbar address map — **every peripheral must have an entry or its address space will be unreachable** (reads return zero, writes are dropped silently).

Required ports depend on the board's peripherals:

| Port | When needed |
|------|-------------|
| `chip` | Always (NoC connection) |
| `mem` | Always (DDR) |
| `iob` | Always (IO bridge) |
| `sd` (`0xf000000000`) | Board has SD card slot |
| `uart` (`0xfff0c2c000`) | Board has UART |
| `net` (`0xfff0d00000`) | Board has Ethernet |
| `ariane_debug/bootrom/clint/plic` | Using Ariane core |

Other required board files: `constraints.xdc` (pin constraints), `clk_mmcm` IP (clock config), and entries in `piton/tools/src/proto/board.list` + `block.list`. Board-specific IP cores go under `<module>/xilinx/<board>/ip_cores/`; missing IPs fall back to genesys2 for 7-series parts.

### Preprocessor System (PyHP)

`.pyv` files contain Python/PHP-like embedded code (e.g. `<% ... %>`) processed by `pyhp.py`. Configuration parameters like `PITON_NUM_TILES`, `PITON_X_TILES`, `PITON_Y_TILES` are defined in `define.h.pyv` using `pyhplib`.

The build flow: `.pyv` files → `pyhp.py` → `.tmp.v`/`.tmp.h` files → simulator.

`.core` files use the FuseSoC format to declare module dependencies, file sets, and generate steps.

### Verification (`piton/verif/`)

- **env/manycore/** — Main manycore testbench (`manycore_top.v.pyv` → `cmp_top`, plus monitors, PLI/VPI glue)
- **diag/assembly/** — Assembly tests organized by unit (IFU, TLU, etc.) and source (princeton, riscv, random)
- **diag/c/** — C-based tests
- **diag/princeton/** — Princeton test suite

### Configuration

Tile count configured at build time via `-x_tiles`/`-y_tiles` (passed through to the pyhp preprocessor). Core selection via `-core=ariane` or default SPARC. Key defines in `piton/design/include/define.h.pyv`.

## Key Tools

| Tool | Purpose |
|------|---------|
| `sims` | Build simulation models and run tests (Perl, src at `tools/src/sims/sims,2.0`) |
| `contint` | Run CI bundle across multiple simulation models |
| `regreport` | Aggregate regression results into a report |
| `mktools` | Rebuild all tools (run after initial checkout) |
| `mkplilib` | Rebuild PLI/VPI libraries for a specific simulator |
| `goldfinger` | SPARC assembler/linker |
| `rv64_as`/`rv64_cc`/`rv64_img` | RISC-V assembler/compiler/image builder (wrappers around riscv-gnu-toolchain) |
| `procvlog` | Verilog preprocessor |
| `check_log` | Check simulation log for errors |
| `protocheck`/`protosyn`/`protocontint` | Higher-level proto wrappers for check/synth/CI |

## RISC-V Toolchains

Two toolchains are available:

| Toolchain | Path | Use |
|-----------|------|-----|
| `riscv64-unknown-elf-gcc` 7.2.0 | `$HOME/scratch/riscv_install/bin/` | Bootrom, bare-metal (required for bootrom build) |
| `riscv64-linux-gnu-gcc` 11.4.0 | `/usr/bin/` (apt) | Linux userspace, BBL |

The bootrom **must** be built with `riscv64-unknown-elf-gcc` (the original OpenPiton toolchain). Using the Linux toolchain produces broken bootrom binaries that fail silently.

## UART Debugging (WSL → Windows COM port)

Serial capture via PowerShell from WSL:
```bash
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w /tmp/read_uart.ps1)"
```

The PowerShell script at `/tmp/read_uart.ps1` reads COM5 at 115200 8N1 for 180 seconds.

## FPGA Programming (from WSL)

### AX7203 (local, localhost:3121)

```bash
vivado -mode batch -source /tmp/program_fpga.tcl
```

Where the TCL script opens hw_manager, connects to localhost:3121, programs the device with `system.bit`.

### P3 / Versal VP1902 (remote hw_server)

The P3 board is connected to a remote machine (100.93.77.36). hw_server runs at **100.93.77.36:3121**, XVC debug bridge at **202.197.4.99:2540**.

Build scripts under `scripts/`:

```bash
# Build + ILA + PDI (synthesis → ILA insertion → implementation → device image)
vivado -mode batch -source scripts/p3_build19_rst_fix2.tcl

# Program FPGA (upload PDI to P3 via remote hw_server + XVC)
vivado -mode batch -source scripts/p3_program.tcl

# Debug session (connect ILA, program debug PDI, load probes, interactive capture)
vivado -mode tcl -source scripts/p3_debug.tcl

# ILA immediate capture (non-interactive: connect → capture → CSV → exit)
vivado -mode batch -source scripts/p3_ila_capture.tcl
```

PDI output: `huaprop3_openpiton/huaprop3_openpiton.runs/impl_1/p3_top.pdi`
Debug PDI: `huaprop3_openpiton/debug_build/p3_top_debug.pdi`
ILA probes: `huaprop3_openpiton/debug_build/p3_top_debug.ltx`

### P3 Serial Debug (remote via SSH)

The P3 UART is connected to the remote machine (100.93.77.36) via FTDI dual RS232:
- **ttyUSB0**: P3 UART (115200 8N1)
- **ttyUSB1**: XVC JTAG debug bridge (for hw_server)

```bash
# Capture UART output for 15 seconds
python3 scripts/p3_serial.py --capture 15

# Interactive serial console (Ctrl-A Ctrl-Q to exit)
python3 scripts/p3_serial.py
```

Requires: `python3` with `pexpect` (`pip install pexpect`). SSH password auth to remote machine (illya@100.93.77.36).

## Porting OpenPiton+Ariane to a New FPGA Board

Porting to a new board goes far beyond pin constraints and clock configuration. Below is a complete checklist based on the AX7203 bring-up experience, organized from hardware-level to software-level.

### Layer 1: FPGA Hardware (what most people expect)

| Item | Files | Notes |
|------|-------|-------|
| Pin constraints (XDC) | `piton/design/xilinx/<board>/constraints.xdc` | FPGA pin assignments, I/O standards (LVCMOS, SSTL), timing constraints. Check IOSTANDARD matches the bank voltage (e.g., Bank 34 = 1.5V → LVCMOS15, not LVCMOS33). |
| Clock MMCM | `<board>/ip_cores/clk_mmcm/` and chipset-level `clk_mmcm_chip/` | Input clock frequency, output clocks for core/chipset/DDR. AX7203 uses 200 MHz input → 50 MHz core, 30 MHz chipset. |
| DDR3 MIG | `<board>/ip_cores/mig_7series_0/` | Pin mapping, timing parameters, bank assignments. `init_calib_complete` gates the entire chipset reset — if DDR calibration fails, nothing works (no UART, no boot). |
| UART pins | In `constraints.xdc` | TX/RX pin assignments. Baud rate set in chipset defines and DTS. |
| SD card pins | In `constraints.xdc` | SPI-mode: CLK, CMD (MOSI), DAT0 (MISO), CD (card detect). |
| Reset pin | In `constraints.xdc` | Check polarity (active-low vs active-high) and bank voltage. AX7203 reset is active-low in Bank 34 (LVCMOS15). |

### Layer 2: NoC / IO Crossbar Device Map (the silent killer)

| Item | Files | Notes |
|------|-------|-------|
| **`devices_ariane.xml`** | `piton/design/xilinx/<board>/devices_ariane.xml` | Defines the IO crossbar address routing. **Every peripheral must have an entry** — missing entries cause reads to return zero and writes to be silently dropped. This was the root cause of SD card failures on AX7203. |
| SD port entry | `<base>0xf000000000</base>` | Without this, the SD controller's MMIO address space is unreachable from the NoC. Bootrom's `init_sd()` succeeds but all data reads return zeros. |
| UART port entry | `<base>0xfff0c2c000</base>` | Address must match both hardware and DTS. |
| Ariane-specific ports | `ariane_debug`, `ariane_bootrom`, `ariane_clint`, `ariane_plic` | Each needs correct base address and length matching the hardware instantiation. |

**Key insight**: `devices_ariane.xml` is the **single source of truth** for IO routing. If an address isn't listed here, it doesn't exist from the CPU's perspective. The NoC will not forward the transaction, and the CPU may hang or read garbage.

Reference addresses for AX7203 (must match across all layers):

| Peripheral | Address | Length |
|------------|---------|--------|
| DDR (mem) | `0x80000000` | `0x40000000` (1 GB) |
| SD | `0xf000000000` | `0xff0300000` |
| UART | `0xfff0c2c000` | `0xd4000` |
| Debug | `0xfff1000000` | `0x1000` |
| Bootrom | `0xfff1010000` | `0x10000` |
| CLINT | `0xfff1020000` | `0xc0000` |
| PLIC | `0xfff1100000` | `0x4000000` |

### Layer 3: Chipset RTL Configuration

| Item | Files | Notes |
|------|-------|-------|
| `uart_boot_en` | `piton/design/chipset/rtl/chipset.v` | Controls UART mux mode. Must be `1'b0` for autonomous SD boot. On Genesys2 this is a DIP switch; boards without switches need it hardcoded. With `uart_boot_en=1`: UART mux stuck in READER_SEL (CPU writes never reach UART), packet_filter blocks SD routing, all chipset traffic blocked. |
| `PITON_FPGA_SD_BOOT` | Chipset defines | Enables SD boot path. Set via `--uart-dmw ddr` in protosyn. |
| Board registration | `piton/tools/src/proto/board.list`, `block.list` | New board must be registered or protosyn won't recognize it. |

### Layer 4: Bootrom (ZSBL)

| Item | Files | Notes |
|------|-------|-------|
| DTB embedding | `bootrom/linux/startup.S` → `.incbin "rv64_platform.dtb"` | The bootrom embeds the DTB and passes its address to BBL via register `a1`. |
| **PC-relative addressing** | `startup.S` | **Critical**: Bootrom is linked at `0x10000` but runs at `0xFFF1010000`. Must use `auipc`/`addi` with `%pcrel_hi`/`%pcrel_lo` (not `la` which may use GOT). GOT entries contain link-time addresses, causing `a1` to point to wrong DTB address. |
| UART frequency | `Makefile` `-DUART_FREQ=` | Must match chipset clock (30 MHz on AX7203). |
| Toolchain | `riscv64-unknown-elf-gcc` 7.2.0 | **Must** use bare-metal toolchain. Linux toolchain produces broken bootrom binaries that fail silently. |

### Layer 5: Device Tree (DTS/DTB)

| Item | Files | Notes |
|------|-------|-------|
| DTS | `build/<board>/<board>.dts` | Must be manually written; `riscvlib.py` auto-generator requires many env vars not set in basic flow. |
| **All peripheral addresses** | DTS `reg` fields | Must match `devices_ariane.xml` exactly. A single nibble error (e.g., PLIC `0xffd1100000` vs correct `0xfff1100000`) causes CPU to hang when accessing that peripheral — bus transaction has no responder. |
| Clock frequency | `clock-frequency` in CPU and UART nodes | Must match actual hardware. Affects timer, baud rate calculation. |
| Timebase | `timebase-frequency` in `/cpus` | Derived from chipset clock: 30 MHz / 128 = 234375 Hz on AX7203. |
| `bootargs` | `/chosen` node | `earlycon=uart8250,mmio,<UART_ADDR>,115200n8 console=ttyS0,115200n8` — UART address must match hardware. |
| DTB compilation | `dtc -I dts -O dtb -o <board>.dtb <board>.dts` | DTB goes into both bootrom (`.incbin`) and optionally BBL (embedded fallback). |

**Address consistency rule**: The following must all agree on the same addresses:
- `devices_ariane.xml` (hardware routing)
- RTL instantiation (hardware implementation)
- DTS `reg` fields (software description)
- Bootrom hardcoded addresses (if any)
- BBL hardcoded UART address (early debug)

### Layer 6: BBL (Berkeley Boot Loader)

| Item | Files | Notes |
|------|-------|-------|
| Embedded DTB fallback | `riscv-pk/machine/minit.c` | Recommended safety net: if bootrom passes invalid DTB (magic != `0xedfe0dd0`), fall back to compiled-in copy. |
| `embedded_dtb.h` | `build/<board>/ariane-sdk/build-bbl/embedded_dtb.h` | Raw byte array from `xxd -i <board>.dtb`, stripped of variable declaration. Must be regenerated when DTS changes. |
| Build flags | `-fno-stack-protector -U_FORTIFY_SOURCE` | Required to avoid undefined symbols during linking. |
| Toolchain | `riscv64-linux-gnu-gcc` | Uses Linux toolchain (not bare-metal). |

### Layer 7: Linux Kernel & Rootfs

| Item | Notes |
|------|-------|
| Kernel `bootargs` | Must match DTS `/chosen` node. UART address in earlycon must be correct or no early console output. |
| SD card driver | `piton_sd` driver detects partitions as `/dev/piton_sd1`, `/dev/piton_sd2`. |
| Root filesystem | Buildroot initramfs (in-memory). For persistent storage, format SD partition 2 as ext2 and mount manually. |
| Test programs | Cross-compile with `riscv64-linux-gnu-gcc -static`. Must be static-linked since Buildroot dynamic libs may not match. |

### Common Pitfalls (from AX7203 bring-up)

1. **SD reads return all zeros**: Missing `sd` port in `devices_ariane.xml`. The SD controller initializes fine, but data reads go nowhere because the IO crossbar has no route for the SD address space.
2. **BBL hangs after `bbl loader`**: Wrong peripheral address in DTS. CPU attempts MMIO write to unmapped address, bus transaction never completes, core hangs. On AX7203 this was a PLIC address typo (`0xffd...` vs `0xfff...`).
3. **Bootrom passes wrong DTB address**: `la` (GOT-based) addressing in `startup.S` doesn't work when link address ≠ run address. Fix: use `auipc`/`addi` with `%pcrel_hi`/`%pcrel_lo`.
4. **No UART output at all**: `uart_boot_en=1` blocks CPU UART writes. Or DDR3 calibration failed (gates entire chipset reset).
5. **UART works but SD doesn't**: `uart_boot_en` also gates SD routing via `packet_filter`. Both UART output and SD access require `uart_boot_en=0` for SD boot mode.
6. **Bootrom compiles but doesn't work**: Used wrong toolchain (`riscv64-linux-gnu-gcc` instead of `riscv64-unknown-elf-gcc`). Binary looks valid but behaves incorrectly at runtime.

### Porting Checklist (quick reference)

```
[ ] constraints.xdc — pins, I/O standards, timing
[ ] clk_mmcm IP — input/output clock frequencies
[ ] DDR3 MIG IP — pin mapping, timing, capacity
[ ] devices_ariane.xml — all peripheral address routes (SD, UART, PLIC, CLINT, etc.)
[ ] chipset.v — uart_boot_en = 0 for SD boot (if no DIP switch)
[ ] board.list / block.list — register new board in protosyn
[ ] DTS — all addresses match devices_ariane.xml, correct clocks/timebase
[ ] DTB → bootrom — rebuild bootrom_linux.sv with new DTB
[ ] startup.S — PC-relative DTB address passing (auipc, not la)
[ ] BBL embedded_dtb.h — regenerate from new DTB
[ ] BBL build — verify with correct toolchain and flags
[ ] SD card — write bbl.bin to sector 2048
[ ] Verify address consistency across all 7 layers
```

## Known Issues & Pitfalls

- `riscvlib.py` (DTS generator) requires many env vars (`PITON_NETWORK_CONFIG`, `CONFIG_L1I_SIZE`, etc.) that aren't set in basic protosyn flow — generate DTS manually instead.
- BBL build requires `-fno-stack-protector -U_FORTIFY_SOURCE` to avoid undefined symbols.
- `PITON_SKIP_ARIANE_FW_BUILD=1` skips bootrom build in protosyn; must manually build `bootrom_linux.sv` and `bootrom.sv` (baremetal) before synthesis.
- DDR3 MIG `init_calib_complete` gates the entire chipset reset — if DDR3 calibration fails, no peripherals (including UART) will function.
- The AX7203 reset pin (T6) is in Bank 34 (1.5V LVCMOS15), not 3.3V.
