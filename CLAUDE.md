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

## Repository Structure

OpenPiton source lives under `piton/`. `piton/design/` contains synthesizable RTL and platform logic: `design/chip/` for tile and chip RTL, `design/chipset/` for off-chip controllers and peripherals, `design/include/` for shared defines, and `design/xilinx/` or `design/aws/` for FPGA targets. Verification assets are in `piton/verif/`, with `env/` testbenches and monitors plus `diag/assembly/` and `diag/c/` diagnostics. Tool wrappers, preprocessors, PLI/VPI libraries, and regression utilities are under `piton/tools/`. Generated simulator output and local models belong in `build/`; manuals and images are in `docs/`.

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

### R1-E: Git Commit Requirement (ABSOLUTE)

**Every wiki update MUST be committed to git and pushed to GitHub immediately. No exceptions. No queuing for later.**

- After writing ANY wiki file (devlog, concept article, INDEX.md), immediately run `git add <file>` and `git commit` with a descriptive message.
- Wiki commits should use the prefix `wiki:` (e.g., `wiki: add May 23 devlog — Build 19 reset fix verified`).
- After committing, push to the remote: `git push origin openpiton`.
- **Anti-pattern**: accumulating multiple wiki changes without committing. Each logical update gets its own commit.
- **Anti-pattern**: "I'll commit after this build finishes." No — commit the wiki changes NOW. The build proceeds independently.
- If a build or debug session spans hours, commit wiki updates incrementally — don't wait until the end of the session.
- CLAUDE.md and AGENTS.md changes follow the same rule: commit and push immediately.

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

For P3 hardware-manager operations, use this Windows full Vivado 2024.2.2 client with board-side `hw_server 100.93.77.36:3121` and XVC `202.197.4.99:2540`. Board-side Vivado Lab 2024.2 has failed to enumerate this chain while the Windows client immediately found `arm_dap_0 xcvp1902_1`; do not classify that Lab-only result as a board or PMC/DPC failure.

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
vivado -mode batch -source scripts/p3_build68_8x8_opensbi_linux.tcl -tclargs -jobs 32
scripts/p3_prepare_64core_opensbi_image.sh
```

The hardware wrapper sets `PITON_X_TILES=8`, `PITON_Y_TILES=8`, and `PITON_NUM_TILES=64`, keeps self-contained source snapshots, and rebuilds the bootrom with `BOOTROM_MODE=opensbi_bundle`. The SD image is generated from `riscv64-linux-64core-src-20260610.tar.gz` and contains a 512-byte `P3OS`/`BI64` bundle header followed by OpenSBI, Linux `Image`, DTB, and initramfs payloads.

Hardware wrapper:
- Build script: `scripts/p3_build68_8x8_opensbi_linux.tcl`
- Bootrom rebuild: `scripts/p3_rebuild_build68_8x8_opensbi_linux.sh`
- Vivado project: `huaprop3_build68_8x8_opensbi_linux`
- Default work directory: `p3b68_8x8/`
- Output basename: `p3_top_build68_8x8_opensbi_linux`

Software/image path:
- Main script: `scripts/p3_prepare_64core_opensbi_image.sh`
- Validated Build 66 one-hart wrapper: `scripts/p3_prepare_build66_1hart_opensbi_image.sh`
- DTB generator: `scripts/p3_generate_opensbi_dts.py`
- DTB validator: `scripts/p3_validate_opensbi_dtb.py`
- SD bundle packer: `scripts/p3_make_opensbi_bundle_image.py`
- Build 66 flat-image packer: `scripts/p3_make_build66_opensbi_flat_image.py`
- Platform-contract regression: `scripts/test_p3_opensbi_platform.py`
- Output directory: `build/huaprop3/opensbi64/`

Default DDR layout:
- OpenSBI `fw_jump.bin`: `0x80000000`
- Linux `Image`: `0x80200000`
- DTB: `0x88000000`
- initramfs: `0x90000000`

#### P3 OpenSBI DTB and bundle generation workflow

Use `scripts/p3_prepare_64core_opensbi_image.sh` as the normal entry point for
1-hart, 2-hart, and 64-hart OpenSBI/P3OS components. The script builds or selects
OpenSBI and Linux, selects the initramfs, generates DTS from the P3 device map,
compiles it with `dtc`, validates the compiled DTB, checks every bundle load
range, creates the GPT/P3OS image, and emits a SHA-256 manifest. This path is
fail-closed; do not hand-edit its generated DTS/DTB or substitute an old
`*_initrd.dtb`.

The default hardware source of truth is
`piton/design/xilinx/huaprop3/devices_ariane.xml`. Memory, UART, SD, CLINT, and
PLIC ranges come from that file. The timebase is derived from
`P3_CPU_FREQUENCY / P3_TIMEBASE_DIVISOR` (currently
`30000000 / 128 = 234375` Hz), and `linux,initrd-end` comes from the actual
initramfs size. Supplying `P3_TIMEBASE_FREQUENCY` asserts equality with the
derived value; it is not an override. The generator/validator rejects stale
addresses, wrong hart or interrupt-context counts, wrong clock/timebase data,
an inexact initrd range, overlapping components, and loads outside declared
DDR. The complete flow requires `dtc`, `fdtget`, and `sfdisk`.

The one-hart hardware control must reuse the unchanged, board-validated Build
66 PDI:

`huaprop3_build66_baseline/debug_build/p3_top_build66_normal_spi_sd_boot.pdi`
(SHA-256
`ee30fe4d052c763c9fc2fa72bf71cc8363173ad210ea8fb106533ac3081dd62d`).
That PDI's synthesized bootrom copies a fixed 32 MiB from the first GPT
partition to `0x80000000`; it does not parse `P3OS/BI64`. Do not write the
normal P3OS image for this test. Instead run:

```bash
scripts/p3_prepare_build66_1hart_opensbi_image.sh
```

On a host that has only the bare-metal RISC-V compiler, reuse of a known Linux
6.6 `Image` is allowed only with its exact SHA-256 while OpenSBI is still
rebuilt:

```bash
PATH="$HOME/scratch/riscv_install/bin:$PATH" \
CROSS_COMPILE=riscv64-unknown-elf- \
P3_BUILD66_LINUX_IMAGE="$PWD/build/huaprop3/opensbi64/Image_p3_2hart" \
P3_BUILD66_LINUX_IMAGE_SHA256=47c9daa86019503459071e38ac4a54624a40062401eae4ff64b948bf16a6441b \
scripts/p3_prepare_build66_1hart_opensbi_image.sh
```

Do not replace this with `P3_64CORE_USE_PREBUILT=1`; that would also reuse an
OpenSBI binary built for the ordinary P3OS FDT address.

The wrapper rebuilds the corrected OpenSBI/Linux stack for one hart and packs
OpenSBI at `0x80000000`, Linux at `0x80200000`, DTB at `0x81600000`, and
initramfs at `0x81700000`. The flat packer enforces the hardware DDR map, the
fixed `[0x80000000,0x82000000)` copy window, non-overlap, the exact DTB initrd
range, and byte-for-byte packed-component readback. Its final artifact is
`build/huaprop3/opensbi1_build66/p3_opensbi_linux_1hart_build66_flat.img`.
This creates only a new SD payload and leaves the validated PDI unchanged.
Board success requires a single UART log showing OpenSBI v1.8, mtimer at
234375 Hz, Linux 6.6, only CPU0, and an interactive shell.

Invocation modes:

1. Actual 64-hart board candidate on the offline Ubuntu host. Do not set
   `P3_64CORE_USE_PREBUILT`, because the board artifact must rebuild OpenSBI and
   Linux for the P3 load addresses.

   ```bash
   P3_64CORE_HARTS=64 scripts/p3_prepare_64core_opensbi_image.sh
   ```

2. A 2-hart image or image-only A/B test. Override the initramfs and bootargs
   when those are the variables under test.

   ```bash
   P3_64CORE_HARTS=2 \
   P3_64CORE_INITRD=/absolute/path/rootfs.cpio.gz \
   P3_64CORE_BOOTARGS='earlycon=uart8250,mmio,0xfff0c2c000 console=ttyS0,115200n8 root=/dev/ram0 rw' \
   scripts/p3_prepare_64core_opensbi_image.sh
   ```

3. Local image-structure smoke test. Prebuilt artifacts are valid only for this
   case; prefer disposable directories so an obsolete OpenSBI experiment in
   the default work tree cannot contaminate the result.

   ```bash
   P3_64CORE_USE_PREBUILT=1 \
   P3_64CORE_HARTS=2 \
   P3_64CORE_WORK_DIR=/tmp/p3-opensbi-smoke-work \
   P3_64CORE_OUT_DIR=/tmp/p3-opensbi-smoke-out \
   P3_64CORE_LINUX_BASE_ARCHIVE="$PWD/build/p3_64core/linux-6.6.tar.xz" \
   scripts/p3_prepare_64core_opensbi_image.sh
   ```

   The package omits several upstream Linux inputs, so a disposable work tree
   must point `P3_64CORE_LINUX_BASE_ARCHIVE` at the verified local
   `linux-6.6.tar.xz`.

4. DTB-only iteration after a device-map, clock, hart-count, bootargs, or
   initramfs change:

   ```bash
   python3 scripts/p3_generate_opensbi_dts.py \
     --harts 2 \
     --initrd /absolute/path/rootfs.cpio.gz \
     --initrd-addr 0x90000000 \
     --out /tmp/p3_2hart.dts
   dtc -I dts -O dtb -o /tmp/p3_2hart.dtb /tmp/p3_2hart.dts
   python3 scripts/p3_validate_opensbi_dtb.py \
     --dtb /tmp/p3_2hart.dtb \
     --harts 2 \
     --initrd /absolute/path/rootfs.cpio.gz \
     --initrd-addr 0x90000000
   ```

Run the focused contract regression after changing the device map,
CPU/timebase settings, load addresses, DTB/initramfs logic, or bundle packer:

```bash
python3 scripts/test_p3_opensbi_platform.py -v
```

PDI generation enforces the matching hardware aperture. The common
Build-52-derived flow in `scripts/p3_build52_sd_cd_mask.tcl` forces
`piton/design/chip/tile/rtl/tile.v.pyv` regeneration and validates both the
live `tile.tmp.v` and the self-contained `source_snapshot` with
`scripts/p3_validate_tile_aperture.py`. If it detects the stale 1 GiB CVA6
`ExecuteRegionLength`/`CachedRegionLength` against the 2 GiB P3 memory map,
create a fresh Vivado project/work directory; `-skip_create` must not reuse the
stale snapshot. This was not a DTB size error: the DTB declared 2 GiB, but the
old generated CVA6 RTL exposed only 1 GiB.

The Build 68 rebuild step must generate both ROM modules used by `riscv_peripherals.sv`: `bootrom/baremetal/bootrom.sv` for the baremetal ROM instance and `bootrom/linux/bootrom_linux.sv` for the OpenSBI bundle ROM. Even when `ariane_boot_sel_i` selects the Linux/OpenSBI path, Vivado still elaborates the baremetal `bootrom` instance. Remote clean archives must not depend on stale untracked generated ROM files left in a local workspace. Generate the companion baremetal ROM from an inline minimal DTS, not by invoking `riscvlib.py` or following `bootrom/baremetal/rv64_platform.dts`, because the remote source archive intentionally lacks `.git` metadata and the symlink target `bootrom/rv64_platform.dts` is an ignored generated file.

`P3_64CORE_USE_PREBUILT=1 scripts/p3_prepare_64core_opensbi_image.sh` is only a local image-structure smoke test. The board candidate should rebuild OpenSBI/Linux on offline Ubuntu so `FW_JUMP_ADDR=0x80200000` and `FW_JUMP_FDT_ADDR=0x88000000` are correct for P3.

Remote Ubuntu toolchain state as of 2026-06-11: `gcc-riscv64-unknown-elf` 10.2.0, `binutils-riscv64-unknown-elf` 2.35.1, `device-tree-compiler` 1.6.1, and `libfdt1` are installed on `cs@202.197.4.150`. Build 68 requires `riscv64-unknown-elf-gcc` during bootrom rebuild before Vivado project creation.

For Jammy's system-packaged `riscv64-unknown-elf-gcc`, `picolibc-riscv64-unknown-elf` supplies headers such as `stdint.h`. Build 68 passes that include path through `P3_BOOTROM_EXTRA_CFLAGS` when the OpenPiton scratch toolchain is absent, while keeping the bootrom `-nostdlib`/`-nostartfiles` link model.

`scripts/p3_create_bd.tcl` must not depend on ignored `.tmp.v` files from an
older work tree.  It removes stale PyHP outputs and explicitly generates every
missing fileset/include output with repo-local `piton/tools/bin/pyhp.py` before
calling the common helper.  On Windows full Vivado this pre-generation runs
through WSL `python3`; merely prepending the tool directory to Windows Tcl
`env(PATH)` does not make the Unix `pyhp.py` script executable.

`scripts/p3_remote_vivado_64core.sh` archives the committed top-level repository state plus committed recursive submodule HEAD contents. It intentionally does not package dirty tracked submodule changes; it now fails before packing if any recursive submodule has staged or unstaged tracked diffs. Commit and push submodule RTL fixes, then update the superproject gitlink, before launching a remote Build 68 run.

Build 68 remote runs default to `JOBS=32`; use `JOBS=<N> scripts/p3_remote_vivado_64core.sh` only when deliberately comparing runtime or stability. The 2026-06-12 active run used `-jobs 8`, and Vivado reported up to 7 synthesis processes and up to 8 CPUs for place/route. The offline Ubuntu host has 384 logical CPUs, 192 physical cores, and 1.5 TiB RAM. Do not use 64+ as the default until scaling evidence is collected and file-descriptor pressure is checked (`ulimit -n` was 1024). The shared Build 52 wrapper sets `general.maxThreads` and `synth.maxThreads` before top synthesis/place/route, then keeps the generated child-IP synthesis serialization workaround after top synthesis. During long remote Vivado runs, monitor progress at roughly 15-minute intervals unless the user asks for a different cadence.

The 64-core DTB must expose `cpu@0` through `cpu@63`, CLINT timer/software interrupt contexts for every hart, PLIC M/S contexts for every hart, UART source 1, and `riscv,ndev = <2>`. Do not claim a 64-core Linux boot until UART logs show OpenSBI entry, Linux banner, `SMP: Total of 64 processors activated`, `/bin/sh`, and `/proc/cpuinfo` or `nproc` reporting 64 CPUs.

Current 64-core evidence status as of 2026-07-02:
- L1 invalidation/coherence is not the confirmed blocker: `coh_2core.c` and
  `coh_64core.c` pass, and the old `wt_l15_adapter.sv:121` diagnosis was
  retired.
- The stale DTB `linux,initrd-end` truncation was a real blocker and is fixed in
  dbg26. The previous `No working init` panic should not be re-debugged unless a
  new log reproduces it with a current DTB.
- Older `coh_ipi64.c` logs are only a stale lead. A 2026-07-01 progress-only
  8x8 sweep passed three consecutive runs and crossed the old `~40M` suspected
  fail window without a monitor failure.
- Current board evidence verifies progress through OpenSBI and Linux 64-CPU SMP
  bring-up, but does not validate an interactive 64-core shell, `nproc=64`, or
  XSBench completion. Treat stop-machine/IPI/timer/coherence explanations as
  hypotheses until the failing hart and exact software/RTL edge are observed.
- Prefer board-level layer evidence over blind 8x8 Verilator sweeps when the
  suspected simulation failure no longer reproduces.

Build 69 is the 8x8 / 64-core diagnostic PDI path for the same OpenSBI target. It keeps the Build 68 hardware and bundle addresses, but rebuilds the bootrom with `BOOTROM_MODE=opensbi_bundle_diag`. The diagnostic order is `B69 ASM` from no-stack startup, C banner, DDR probe at `0x84001000`, SD init, GPT and `P3OS`/`BI64` header reads, per-component DDR copies, then hart release and OpenSBI jump. Use:

```bash
P3_REMOTE_SCRIPT=scripts/p3_build69_8x8_opensbi_diag.tcl scripts/p3_remote_vivado_64core.sh
```

Capture and decode with `scripts/p3_ila_capture_build69_8x8_opensbi_diag.tcl` and `scripts/p3_decode_build69_ila_csv.py`. Do not classify UART 0 bytes as a bootrom failure until the programming run reports `DONE bit: HIGH`; a Vivado stall inside `program_hw_devices` is a programming/XVC gate.

If a completed Build 69 programming run reports `DONE bit: HIGH` and UART still prints nothing, immediately move to a new remote diagnostic PDI instead of repeating the same artifact. The next PDI must isolate the path in order: no-stack UART marker and UART16550 AXI/TX activity, DDR probe, SPI-SD/GPT/`P3OS` bundle reads, and only then core release/OpenSBI/Linux. Capture Build 69 ILAs first when the LTX/debug hub are usable, so the new PDI is based on observed layer failure rather than speculation.

Build 70 is the automatic successor selected by that rule. Build 69 ILAs proved clocks/resets, core/NOC activity, and DDR reads, then retained an SPI-SD transaction-manager read error, but did not expose the AXI16550 write path. Build 70 reuses the Build 69 bootrom and 8x8 hardware while retaining core-side UART writes, UART-IP-side writes/responses, TX transitions, and compact SD progress/error flags. Build and inspect it with:

```bash
P3_REMOTE_SCRIPT=scripts/p3_build70_8x8_uart_sd_diag.tcl scripts/p3_remote_vivado_64core.sh
vivado -mode batch -source scripts/p3_ila_capture_build70_8x8_uart_sd_diag.tcl
python3 scripts/p3_decode_build70_ila_csv.py huaprop3_build70_8x8_uart_sd_diag/debug_build
```

Build 70 defaults to 32 jobs. A failed implementation or `DONE bit: HIGH` board test must be documented and followed automatically by a new build targeting the first unproven layer; never repeat an unchanged failed PDI.

Build 70 failed main synthesis because `piton_spi_sd_top` was instantiated but
the untracked local source was omitted by `git archive HEAD`. Build 71 keeps the
same UART/SD diagnostic hardware and closes that reproducibility gap:

```bash
P3_REMOTE_SCRIPT=scripts/p3_build71_8x8_uart_sd_source_closure.tcl scripts/p3_remote_vivado_64core.sh
vivado -mode batch -source scripts/p3_ila_capture_build71_8x8_uart_sd_source_closure.tcl
python3 scripts/p3_decode_build70_ila_csv.py huaprop3_build71_8x8_uart_sd_source_closure/debug_build
```

The Build 71 wrapper and remote packer require the committed
`piton_spi_sd_top.v` and `init_sd_p3.v` sources plus their RTL setup entries.
An untracked source is not a valid remote build input.

### P3 Build 66 Baseline & Build 67 Scaling

Build 66 is the current validated HuaPro P3 OpenPiton+Ariane baseline. Use `huaprop3_build66_baseline/debug_build/p3_top_build66_normal_spi_sd_boot.pdi` and the matching `.ltx` for board programming unless a newer validated build supersedes it.

The build wrapper is `scripts/p3_build66_normal_spi_sd_boot.tcl`. Future clean rebuilds should target the repository-root `p3b66/` work directory by default; override with `P3_BUILD66_WORK_DIR` only when debugging a path-specific Vivado issue. The repository-root `p3b66_validated_snapshot/` is a full copy of the previously validated `/mnt/d/p3b66` workspace and is only a recovery/cache source.

Build 66 and all scaling successors such as Build 67 must be self-contained Vivado projects. The wrappers force `P3_SELF_CONTAINED_SOURCES=1`, causing `scripts/p3_create_bd.tcl` to copy RTL, headers, constraints, top files, and shims into `<workdir>/source_snapshot/` and add files from that snapshot. Include directories must be copied recursively while preserving subdirectory names; Ariane/CVA6 includes such as `register_interface/assign.svh` and `register_interface/typedef.svh` are resolved by relative `include` paths during synthesis. Do not accept `.xpr` files that reference live repository sources under `piton/`, stale mirrors under `Z:/tmp`, or old `D:/p3b*` workspaces; rerun project creation if the self-contained validation fails. Generated BD wrappers and IP products remain under the Vivado project `.gen/.srcs/.cache` directories.

For multicore P3 builds, the PyHP-generated tile configuration must be regenerated as one consistent set before Vivado project creation: `piton/design/include/define.tmp.h`, `piton/design/chip/rtl/chip.tmp.v`, `piton/design/chipset/rtl/chipset_impl.tmp.v`, `piton/design/chip/tile/common/rtl/flat_id_to_xy.tmp.v`, and `piton/design/chip/tile/common/rtl/xy_to_flat_id.tmp.v`. The generated `define.tmp.h` inside both the live repo and `<workdir>/source_snapshot/` must match `PITON_X_TILES`, `PITON_Y_TILES`, and `PITON_NUM_TILES`; otherwise synthesis can instantiate multiple tiles while sizing interrupt/debug vectors for one tile.

The baseline keeps the original AXI16550 UART path, SPI-mode SD path, DDR address translation, and four compact BD-owned ILAs. Latest self-contained validation: the 2026-06-05 fresh `p3b66/source_snapshot/` rebuild programmed with `DONE bit: HIGH`, refreshed debug hub `0x3ffc0000000`, enumerated four ILAs, booted through BBL into Linux 5.1.0-rc7, reached `/bin/sh` on `/dev/ttyUSB0` at `115200 8N1`, and accepted slow UART input (`P3_B66_SELF_OK`, `uname -a`). Previous runtime validation also mounted `/dev/piton_sd2` as ext2 read-only and launched `/mnt/XSBench -s small -p 1 -l 1`.

Build 67 is the first 2x1 scaling candidate and must follow the same self-contained source-snapshot rule. Its wrapper is `scripts/p3_build67_2x1_normal_spi_sd_boot.tcl`; the default work directory is `p3b67_2x1/`, and published artifacts are `huaprop3_build67_2x1_baseline/debug_build/p3_top_build67_2x1_normal_spi_sd_boot.pdi` plus `.ltx`. Before project creation, regenerate the tile-dependent PyHP outputs as a consistent set and validate both live and snapshot `define.tmp.h` against `PITON_X_TILES=2`, `PITON_Y_TILES=1`, and `PITON_NUM_TILES=2`. The 2026-06-05 implementation candidate routed successfully with 258,405 fully routed nets, 0 routing errors, `WNS=16.312 ns`, and PDI SHA256 `f979264a5e43e5f1e90061590da79ed0d54c080e7aac384762219f993c978ed0`. The 2026-06-08/09 hardware retests programmed successfully, refreshed debug hub `0x3ffc0000000`, enumerated four ILAs, booted through SPI-SD init, copied all 65,536 payload blocks to DDR, matched DDR/SD payload words, and entered BBL with a 2-hart DTB. Complete logs prove Linux 5.1.0-rc7 can print after BBL `mret` and reach `Run /bin/sh as init process`; the active Build 67 gate is now reproducible normal-image shell interaction and `/dev/piton_sd2`/XSBench validation. If the SD card currently contains a `B67M` marker image, rewrite `build/huaprop3/sd_images/huaprop3_linux_xsbench_2x1.img` before drawing conclusions from post-`mret` UART behavior.

Build 75 is the single-hart causal diagnostic for the OpenSBI/Linux 6.6
store-valid-without-L1.5-ack stop.  Build it only from fresh synthesis with
`scripts/p3_build75_1hart_l15_pc_diag.tcl`; the old Build 66 DCP does not retain
the individual tag/index/MSHR/NoC1 blockers.  The conditional RTL trigger
requires an ordinary store to remain unacknowledged for 256 cycles, and the
post-synthesis hook must resolve every exact L1.5/CVA6 probe before inserting
`u_ila_build75`.  Capture with
`scripts/p3_ila_capture_build75_1hart_l15_pc_diag.tcl` and decode with
`scripts/p3_decode_build75_ila_csv.py`, optionally passing the Linux `vmlinux`
for PC symbols.  The Build 66 bootrom wrapper used by this clean build must
generate both `baremetal/bootrom.sv` and `linux/bootrom_linux.sv`, because
`riscv_peripherals.sv` instantiates both unconditionally; the self-contained
snapshot validator rejects either missing module.  Do not claim an exact
stuck instruction unless the decoder confirms the `0x75` tag, counter, store
request, STORE commit head, and a
concrete blocker.  No Build 75 PDI or board evidence exists yet.  Reuse the
current one-hart OpenSBI/Linux 6.6 SD image without rewriting it; do not build
the excluded Linux 5.1 control or repeat the unchanged failing baseline.

Old P3 debug projects are archived outside the repository root. Repo-local historical build folders are under `/home/illya/p3_cleanup_archive/2026-06-04-build66-baseline/repo_dirs/`; old Vivado workspaces are under `/mnt/d/p3_cleanup_archive/2026-06-04-build66-baseline/workspaces/`. Keep `huaprop3onecore/` as the board-level reference project. Do not commit `p3b66/`, `p3b66_validated_snapshot/`, PDI/LTX/CSV files, or SD-card images.

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

### Ariane simulation with Verilator 5.046 (VCS not required) — VERIFIED WORKING 2026-06-27

VCS is not installed on this machine, and Ariane's bundled Verilator 4.014 will not build (bison 3.8.2 incompatibility). The manycore Ariane design **does build and run on the system Verilator 5.046** (at `/usr/local/bin/verilator`) with three small, no-design-RTL fixes. This is the working local simulation path.

Environment (the `unset VERILATOR_ROOT` is essential — otherwise ariane_setup points at the broken 4.014):
```bash
source $PITON_ROOT/piton/piton_settings.bash
source $PITON_ROOT/piton/ariane_setup.sh
export RISCV=$HOME/scratch/riscv_install          # newlib toolchain (has stdint.h); system 10.2.0 lacks it
export PATH=$RISCV/bin:$PITON_ROOT/piton/tools/bin:$PATH
export C_INCLUDE_PATH=$RISCV/include:${C_INCLUDE_PATH:-}
unset VERILATOR_ROOT                               # use system verilator 5.046
```

Build + run (2-tile example; the `-vlt_build_args` flags are required on v5):
```bash
sims -sys=manycore -x_tiles=2 -y_tiles=1 -ariane -vlt_build \
  -vlt_build_args=--no-timing \                    # v5 needs this for #delay stmts in monitors
  -vlt_build_args=-Wno-WIDTHEXPAND -vlt_build_args=-Wno-WIDTHTRUNC \
  -vlt_build_args=-Wno-WIDTH -vlt_build_args=-Wno-SELRANGE \
  -vlt_build_args=-Wno-ASCRANGE -vlt_build_args=-Wno-WIDTHCONCAT
# Model: build/manycore/rel-0.1/obj_dir/Vcmp_top
sims -sys=manycore -x_tiles=2 -y_tiles=1 -ariane -vlt_run <diag>.c -finish_mask=0x3 -rtl_timeout=1000000
```

Fixes already applied to the tree (committed):
- `piton/tools/src/sims/sims,2.0:1534` — `-CFLAGS -lstdc++` → `-LDFLAGS -lstdc++` (`-lstdc++` is a linker flag; as a CFLAG it leaked into v5's precompiled-header g++ command and failed with `undefined reference to main`. g++ links libstdc++ by default).

Caveat discovered while testing 2-core coherency diags: the C runtime's `printbuf` (`piton/verif/diag/assembly/include/riscv/ariane/syscalls.c`) polls UART LSR bit 5 (`while(!((*(uartAddr+5)) & 0x20))`) before every character. The Verilator testbench does not model the UART, so **any diag that calls `printf` hangs the core forever** (the poll never sees THRE). For coherency/functional tests in Verilator, use **printf-free** diagnostics and signal pass/fail only via `pass()`/`fail()` (or `return 0`) — do not rely on UART output, which is not piped to the sim log anyway. Pass/fail is read from good/bad traps in `build/manycore/rel-0.1/status.log` and the `Info: spc(N) thread(T) Hit Good/Bad trap` lines.

## Testing Guidelines

Add diagnostics near related tests and register reusable suites through the appropriate `.diaglist` or regression group. For narrow RTL changes, run a focused `sims ... -vcs_run <test>` first, then a relevant regression such as `tile1_mini`, `ariane_tile1_simple`, or `ariane_tile1_amo_tests_p`. Include `regreport` summaries when reporting results. For Ariane/RISC-V work, also source `piton/ariane_setup.sh` and pass `-ariane` to relevant `sims` commands.

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

## Coding Style & Naming Conventions

Match nearby RTL and script style. Verilog/SystemVerilog uses 4-space indentation in module bodies, aligned declarations, lowercase module/file names, and explicit suffixes such as `_clk`, `_rst_n`, `_val`, `_rdy`, and `_top`. Preserve copyright headers. Treat `.pyv` files as PyHP templates; update the template source, not generated temporary files (`.tmp.v`/`.tmp.h`). Python and Perl tools are legacy style, so keep edits minimal and localized.

## Engineering Discipline — Rules for LLM-Assisted Code (Karpathy)

> **Field Notes on Getting a Language Model to Write Code You Will Not Rewrite** — *A Short List of Rules, Earned by Watching the Same Mistakes Twice*. Andrej Karpathy.
>
> This file exists because language models make predictable mistakes when they write code. Not random mistakes, just the same ones, over and over, often enough that it was worth writing them down. What follows is not a set of suggestions but a set of rules. The throughline is the same in every section: the model is fast at generating plausible code and slow to notice that plausible is not the same as correct, so the discipline has to come from the process around it.

These rules override "just produce something that looks right." Apply them to every change:

**I. Read Before You Write.** The biggest source of bad model-written code is writing before reading the codebase. Read the files you are about to touch; read, not skim. Copy the patterns that already exist, and check the imports to see what the project actually depends on, so you do not reach for `axios` where everything is `fetch`. When you cannot find a pattern, ask instead of guessing. *(This project: e.g. do not conclude a coherence path is "broken" from a single `assign = '0` line without tracing the full response path.)*

**II. Think Before You Code.** Figure out what you are doing before you type. State your assumptions ("add authentication" is five different things, so name the one you picked) and name the tradeoffs. If something is genuinely confusing, stop and ask rather than filling the gap with plausible-looking code; that is exactly the code that passes a casual review and fails when it matters.

**III. Simplicity.** Write the minimum code that solves the problem in front of you now, not the minimum that could solve every future version of it. Resist premature abstraction, skip error handling for errors that cannot occur, and hardcode values until there is a real reason to configure them. The test: if the only reason something is abstracted is "in case we need it to," you have over-built it.

**IV. Surgical Changes.** Your diff should be as small as the task allows. Do not touch what you were not asked to touch, match the existing style, and do not reformat; a formatter pass buries the three lines that matter inside three hundred that do not. The test is whether you can justify every changed line by the task. If a line is there because "while I was in there," revert it.

**V. Verification.** The gap between code that works and code you think works is testing. When fixing a bug, write the failing test first, watch it fail, then fix it; that is the only proof you fixed the cause and not the symptom. Test behavior that can actually break, not that a constructor sets a field. If something is hard to test, that is information about the design, not permission to skip it. *(This project: prefer a targeted `sims` regression / VCS waveform over guess-and-synth on hardware.)*

**VI. Goal-Driven Execution.** Every task needs a success criterion before code is written. "Add validation" becomes "reject a missing or malformed email, return 400 with a clear message, and test both cases." For anything multi-step, state the plan first so the user can catch a wrong approach before you spend an hour building it.

**VII. Debugging.** When something breaks, investigate; do not guess. Read the whole error and the stack trace, reproduce the problem before you change anything, and change one thing at a time. Do not paper over an unexpected null with a null check; find out why it is null, or the bug just moves somewhere quieter.

**VIII. Dependencies.** Every dependency is permanent code you do not control. Before adding one, ask whether the project or the standard library can already do it. When you do add one, say why, so the choice is visible rather than smuggled into the manifest.

**IX. Communication.** Say what you did and why, not just a block of code. Flag concerns even when you did exactly what was asked, and be precise about uncertainty: "I am not sure this library supports streaming" tells the user what to verify; "I think this should work" does not.

**X. Common Failure Modes.** A few patterns recur often enough to name: the **Kitchen Sink** — restructuring half the codebase while you are at it; the **Wrong Abstraction** — copy-paste twice before you abstract; the **Optimistic Path** — the happy path handled and the 500 ignored; and the **Runaway Refactor** — a fix that cascades across files. Catch yourself in any of these and the right move is to stop, not to push through.

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

### P3 Remote Programming & UART Capture (detailed SSH)

For HuaPro P3 / VP1902 board bring-up, use the remote Ubuntu host at `100.93.77.36` for both XVC/hw_server and FT2232 UART capture. Known endpoints:
- `hw_server`: `100.93.77.36:3121`
- XVC target: `202.197.4.99:2540`
- Remote UART host/user: `illya@100.93.77.36`
- FT2232 UART devices: `/dev/ttyUSB0` and `/dev/ttyUSB1`; current board UART output has been observed on `/dev/ttyUSB0`.

Before programming a PDI, start UART capture on the remote host so bootrom/BBL output is not missed:

```bash
ssh -tt illya@100.93.77.36 '
  mkdir -p ~/p3_uart_logs
  sudo stty -F /dev/ttyUSB0 115200 cs8 -cstopb -parenb -ixon -ixoff -crtscts raw -echo
  sudo stty -F /dev/ttyUSB1 115200 cs8 -cstopb -parenb -ixon -ixoff -crtscts raw -echo
  ts=$(date +%Y%m%d_%H%M%S)
  echo LOG_TS=$ts
  timeout 240s sh -c "cat /dev/ttyUSB0 > ~/p3_uart_logs/ttyUSB0_${ts}.log" &
  timeout 240s sh -c "cat /dev/ttyUSB1 > ~/p3_uart_logs/ttyUSB1_${ts}.log" &
  wait
  ls -l ~/p3_uart_logs/ttyUSB*_${ts}.log
  wc -c ~/p3_uart_logs/ttyUSB*_${ts}.log
'
```

Then program the PDI with the Windows full Vivado 2024.2.2 client using the same `hw_server` and XVC endpoints. Board-side Vivado Lab 2024.2 can return `No devices detected` for this VP1902 XVC chain even when Windows full Vivado enumerates `arm_dap_0 xcvp1902_1`; use the board Ubuntu host for `hw_server` and UART capture, not as the preferred hardware-manager client. Prefer a real Tcl file path, not shell process substitution, because the WSL-to-Windows Vivado wrapper cannot read `/dev/fd/*` paths. Use `scripts/p3_program_pdi.tcl` with both the PDI and matching LTX when probes are available:

```bash
vivado -mode batch -source scripts/p3_program_pdi.tcl -tclargs \
  huaprop3_build66_baseline/debug_build/p3_top_build66_normal_spi_sd_boot.pdi \
  huaprop3_build66_baseline/debug_build/p3_top_build66_normal_spi_sd_boot.ltx
```

The script sets `PROGRAM.FILE`, sets `PROBES.FILE` when an LTX is supplied, runs `program_hw_devices`, prints the DONE bit, refreshes the hardware device, and lists discovered ILAs. A successful debug-capable programming run should confirm `DONE bit: HIGH` plus debug hub setup at `0x3ffc0000000`.

After programming, inspect remote UART logs:

```bash
ssh -tt illya@100.93.77.36 '
  cat -v ~/p3_uart_logs/<log-file>
  xxd -g1 ~/p3_uart_logs/<log-file>
'
```

If `/dev/ttyUSB0` only prints repeated `A` bytes, the physical UART path is healthy but the programmed design is likely using a no-stack assembly UART probe bootrom rather than the normal GPT/BBL/Linux bootrom. Check the build script's bootrom rebuild mode before debugging SD-card image contents.

When Linux reaches an interactive shell on the AXI16550 console, do not paste several commands at once — bulk writes trigger `ttyS0 input overrun(s)` and corrupt characters. Use slow, per-character writes when testing shell interaction:

```bash
ssh illya@100.93.77.36 '
  stty -F /dev/ttyUSB0 115200 cs8 -cstopb -parenb -ixon -ixoff -crtscts raw -echo
  python3 - <<'"'"'PY'"'"'
import os, time
fd = os.open("/dev/ttyUSB0", os.O_WRONLY | os.O_NOCTTY)
for ch in "echo P3_SHELL_OK\r":
    os.write(fd, ch.encode("ascii"))
    time.sleep(0.20)
os.close(fd)
PY
'
```

Confirm the result from the active UART log under `~/p3_uart_logs/`; a successful Build 66 shell test printed `P3_SHELL_OK` and accepted `uname -a`.

### P3 Remote SD-Card Image Write

When an SD-card image is generated locally but the card is inserted in the remote Ubuntu host, first identify the removable disk on the remote side. Do not assume a stale `/dev/sdX`; the Kingston multi-reader exposes several empty 0B slots.

```bash
ssh illya@100.93.77.36 \
  'lsblk -b -o NAME,SIZE,TYPE,MODEL,TRAN,RM,MOUNTPOINTS; ls -l /dev/disk/by-id'
```

Only write a disk that has a real nonzero size, `TYPE=disk`, `TRAN=usb`, `RM=1`, and the expected model/size. In the current setup the SD card has appeared as `/dev/sdc` with model `Multi-Reader -1` and size `31914983424`, while `/dev/sdb`, `/dev/sdd`, and `/dev/sde` may be empty 0B reader slots.

Copy a local image to the remote host, verify the hash, then write the whole disk device and read back the written span:

```bash
img=build/huaprop3/sd_images/huaprop3_linux_shell.img
sha256sum "$img"
scp "$img" illya@100.93.77.36:/tmp/huaprop3_linux_shell.img

ssh illya@100.93.77.36 '
  sha256sum /tmp/huaprop3_linux_shell.img
  lsblk -b -o NAME,SIZE,TYPE,MODEL,TRAN,RM,MOUNTPOINTS /dev/sdc
  sudo sh -c "
    umount /dev/sdc1 2>/dev/null || true
    dd if=/tmp/huaprop3_linux_shell.img of=/dev/sdc bs=4M conv=fsync status=progress
    sync
    blockdev --rereadpt /dev/sdc 2>/dev/null || true
    sha256sum /tmp/huaprop3_linux_shell.img
    dd if=/dev/sdc bs=4M count=32 status=none | sha256sum
    lsblk -b -o NAME,SIZE,TYPE,MODEL,TRAN,RM,MOUNTPOINTS /dev/sdc
  "
'
```

The readback hash must match the local image hash for the written size. For a 128 MiB image, `count=32` with `bs=4M` reads back the full image. Never write to `/dev/sda` or `/dev/nvme*` on the remote host.

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
| DTS | `build/<board>/<board>.dts` | Legacy BBL/basic protosyn ports may maintain this DTS manually. Current P3 OpenSBI/P3OS images must use `scripts/p3_generate_opensbi_dts.py` plus `scripts/p3_validate_opensbi_dtb.py`; do not hand-edit generated P3 DTS/DTB files. |
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

- `riscvlib.py` requires many env vars (`PITON_NETWORK_CONFIG`, `CONFIG_L1I_SIZE`, etc.) that are not set in the legacy BBL/basic protosyn flow; those legacy ports may maintain DTS manually. The current P3 OpenSBI/P3OS path instead uses `p3_generate_opensbi_dts.py` and its validator.
- BBL build requires `-fno-stack-protector -U_FORTIFY_SOURCE` to avoid undefined symbols.
- `PITON_SKIP_ARIANE_FW_BUILD=1` skips bootrom build in protosyn; must manually build `bootrom_linux.sv` and `bootrom.sv` (baremetal) before synthesis.
- DDR3 MIG `init_calib_complete` gates the entire chipset reset — if DDR3 calibration fails, no peripherals (including UART) will function.
- The AX7203 reset pin (T6) is in Bank 34 (1.5V LVCMOS15), not 3.3V.

## Commit & Pull Request Guidelines

Recent history uses short imperative subjects, often scoped by subsystem, plus GitHub merge commits. Example: `Fix typo in l2 pipe1 causing wrong hazard detection`. Keep commits focused. PRs should describe the changed RTL, tools, or tests; list exact `sims` or `contint` commands run; link related issues; and note simulator/tool versions for environment-sensitive changes.

## Security & Configuration Tips

Do not commit generated build directories, local tool installs, simulator licenses, or machine-specific paths. Keep `VCS_HOME`, RISCV toolchain paths, Vivado settings, and license configuration in the local shell unless a documented default is intentionally changed. Do not store passwords in repository files or scripts; use interactive authentication or an external credential mechanism.
