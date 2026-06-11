# Repository Guidelines

## Project Structure & Module Organization
OpenPiton source lives under `piton/`. `piton/design/` contains synthesizable RTL and platform logic: `design/chip/` for tile and chip RTL, `design/chipset/` for off-chip controllers and peripherals, `design/include/` for shared defines, and `design/xilinx/` or `design/aws/` for FPGA targets. Verification assets are in `piton/verif/`, with `env/` testbenches and monitors plus `diag/assembly/` and `diag/c/` diagnostics. Tool wrappers, preprocessors, PLI/VPI libraries, and regression utilities are under `piton/tools/`. Generated simulator output and local models belong in `build/`; manuals and images are in `docs/`.

## Build, Test, and Development Commands
Set `PITON_ROOT` to the repository root and run `source $PITON_ROOT/piton/piton_settings.bash` before using tools. Run simulation commands from `$PITON_ROOT/build`.

- `sims -sys=manycore -x_tiles=1 -y_tiles=1 -vcs_build`: build a 1x1 VCS simulation model.
- `sims -sys=manycore -x_tiles=1 -y_tiles=1 -vcs_run princeton-test-test.s`: run a single diagnostic after building.
- `sims -sim_type=vcs -group=tile1_mini`: build and run a regression group.
- `regreport $PWD > report.log`: summarize regression results from a run directory.
- `contint --bundle=git_push`: run the CI bundle; requires SLURM, PBS, or similar.

For Ariane/RISC-V work, also source `piton/ariane_setup.sh` and pass `-ariane` to relevant `sims` commands.

## Coding Style & Naming Conventions
Match nearby RTL and script style. Verilog/SystemVerilog uses 4-space indentation in module bodies, aligned declarations, lowercase module/file names, and explicit suffixes such as `_clk`, `_rst_n`, `_val`, `_rdy`, and `_top`. Preserve copyright headers. Treat `.pyv` files as PyHP templates; update the template source, not generated temporary files. Python and Perl tools are legacy style, so keep edits minimal and localized.

## Testing Guidelines
Add diagnostics near related tests and register reusable suites through the appropriate `.diaglist` or regression group. For narrow RTL changes, run a focused `sims ... -vcs_run <test>` first, then a relevant regression such as `tile1_mini`, `ariane_tile1_simple`, or `ariane_tile1_amo_tests_p`. Include `regreport` summaries when reporting results.

## Commit & Pull Request Guidelines
Recent history uses short imperative subjects, often scoped by subsystem, plus GitHub merge commits. Example: `Fix typo in l2 pipe1 causing wrong hazard detection`. Keep commits focused. PRs should describe the changed RTL, tools, or tests; list exact `sims` or `contint` commands run; link related issues; and note simulator/tool versions for environment-sensitive changes.

## Security & Configuration Tips
Do not commit generated build directories, local tool installs, simulator licenses, or machine-specific paths. Keep `VCS_HOME`, RISCV toolchain paths, Vivado settings, and license configuration in the local shell unless a documented default is intentionally changed.

## P3 Remote Programming & UART Capture
For HuaPro P3 / VP1902 board bring-up, use the remote Ubuntu host at `100.93.77.36` for both XVC/hw_server and FT2232 UART capture. Do not store passwords in repository files or scripts.

Known endpoints:
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

Then program the PDI through Vivado/Vivado Lab using the same `hw_server` and XVC endpoints. Prefer a real Tcl file path, not shell process substitution, because the WSL-to-Windows Vivado wrapper cannot read `/dev/fd/*` paths. Use `scripts/p3_program_pdi.tcl` with both the PDI and matching LTX when probes are available:

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

When Linux reaches an interactive shell on the AXI16550 console, do not paste several commands at once. Build 66 reached `/bin/sh` with `/dev/ttyUSB0` as `ttyS0`, but bulk writes triggered `ttyS0 input overrun(s)` and corrupted characters. Use slow, per-character writes when testing shell interaction:

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

## P3 Remote SD-Card Image Write
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

## P3 Offline Ubuntu Vivado Build Host

For P3 Pro / VP1902 scaling builds that need the dedicated offline Ubuntu Vivado machine, connect through the remote Windows host only as an SSH TCP jump. Do not run long nested commands such as `ssh windows "ssh ubuntu '...'"`; Windows must not parse build scripts, shell quoting, or Vivado Tcl.

Known endpoints:
- Windows jump host: `23178@100.70.176.125`
- Offline Ubuntu build host: `cs@202.197.4.150`
- Offline Ubuntu workspace: `/home/cs/openpiton`
- Offline Ubuntu Vivado: `/media/d1/Xilinx/Vivado/2024.2/bin/vivado` (validated as Vivado 2024.2.2)

Use `ProxyJump` / `-J` directly from the local machine:

```bash
ssh -J 23178@100.70.176.125 cs@202.197.4.150

scp -o ProxyJump=23178@100.70.176.125 <local-file-or-archive> \
  cs@202.197.4.150:/home/cs/openpiton/

ssh -J 23178@100.70.176.125 cs@202.197.4.150 \
  'cd /home/cs/openpiton && /media/d1/Xilinx/Vivado/2024.2/bin/vivado -mode batch -source <script>.tcl'
```

Transfer source archives or project snapshots into `/home/cs/openpiton` only when a real remote build is about to start. Keep passwords out of repository files and scripts; use interactive authentication or an external credential mechanism. Build artifacts (`bit`, `pdi`, `ltx`, reports, and logs) should be generated on offline Ubuntu, copied back through the same `scp -o ProxyJump=...` path, and then archived locally as needed.

## P3 Build 68 64-Core OpenSBI/Linux Target

Build 68 is the direct 8x8 / 64-core P3 Pro target. The goal is not only synthesis; the target milestone is a VP1902 board boot that reaches Linux with 64 harts online. Use the OpenSBI boot chain instead of the old BBL payload path.

Hardware wrapper:
- Build script: `scripts/p3_build68_8x8_opensbi_linux.tcl`
- Bootrom rebuild: `scripts/p3_rebuild_build68_8x8_opensbi_linux.sh`
- Tile config: `PITON_X_TILES=8`, `PITON_Y_TILES=8`, `PITON_NUM_TILES=64`
- Vivado project: `huaprop3_build68_8x8_opensbi_linux`
- Default work directory: `p3b68_8x8/`
- Output basename: `p3_top_build68_8x8_opensbi_linux`

Software/image path:
- Package source: `riscv64-linux-64core-src-20260610.tar.gz`
- Main script: `scripts/p3_prepare_64core_opensbi_image.sh`
- DTB generator: `scripts/p3_generate_opensbi_dts.py`
- SD bundle packer: `scripts/p3_make_opensbi_bundle_image.py`
- Output directory: `build/huaprop3/opensbi64/`

The P3 OpenSBI SD image is a GPT image whose first partition starts with a 512-byte `P3OS`/`BI64` bundle header. The bootrom copies components by LBA to fixed DDR addresses, then all harts enter OpenSBI. Default addresses are:
- OpenSBI `fw_jump.bin`: `0x80000000`
- Linux `Image`: `0x80200000`
- DTB: `0x88000000`
- initramfs: `0x90000000`

Build 68 must regenerate both generated ROM sources before Vivado project creation. `riscv_peripherals.sv` instantiates `bootrom` and `bootrom_linux` unconditionally, then selects between them with `ariane_boot_sel_i`; therefore the OpenSBI/Linux path still needs `piton/design/chipset/rv64_platform/bootrom/baremetal/bootrom.sv` in addition to `piton/design/chipset/rv64_platform/bootrom/linux/bootrom_linux.sv`. Do not rely on stale untracked local generated ROM files; a remote clean archive must be able to reproduce both modules. Generate the companion baremetal ROM from an inline minimal DTS, not by invoking `riscvlib.py` or following `bootrom/baremetal/rv64_platform.dts`, because the remote source archive intentionally lacks `.git` metadata and the symlink target `bootrom/rv64_platform.dts` is an ignored generated file.

Use the prebuilt 64core package artifacts only for local image-structure smoke tests:

```bash
P3_64CORE_USE_PREBUILT=1 scripts/p3_prepare_64core_opensbi_image.sh
```

For the actual board candidate, rebuild OpenSBI/Linux on the offline Ubuntu host so `FW_JUMP_ADDR=0x80200000` and `FW_JUMP_FDT_ADDR=0x88000000` match the P3 bundle layout:

```bash
scripts/p3_remote_vivado_64core.sh
ssh -J 23178@100.70.176.125 cs@202.197.4.150 \
  'cd /home/cs/openpiton && scripts/p3_prepare_64core_opensbi_image.sh'
```

`scripts/p3_remote_vivado_64core.sh` archives the tracked repository state and the currently checked-out recursive submodule HEAD contents, transfers that archive through `ProxyJump`, and also copies `riscv64-linux-64core-src-20260610.tar.gz` into `/home/cs/openpiton/`. If local Build 68 changes are not committed, they will not be included in that archive. If a recursive submodule has staged or unstaged tracked changes, the script must fail before packing; commit and push the submodule change, then update and commit the superproject gitlink before rerunning.

Remote Ubuntu toolchain state as of 2026-06-11: the offline host has Jammy packages `gcc-riscv64-unknown-elf` 10.2.0, `binutils-riscv64-unknown-elf` 2.35.1, `device-tree-compiler` 1.6.1, and `libfdt1` installed. Build 68 failed before synthesis when these were missing, because the bootrom Makefile requires `riscv64-unknown-elf-gcc`. If the host is reverted, reinstall those packages before rerunning `scripts/p3_remote_vivado_64core.sh`.

For the Jammy system-packaged toolchain, `picolibc-riscv64-unknown-elf` is also required for headers such as `stdint.h`. `scripts/p3_rebuild_build68_8x8_opensbi_linux.sh` passes the picolibc include directory through `P3_BOOTROM_EXTRA_CFLAGS` only when the OpenPiton scratch toolchain is absent. Keep the bootrom on its `-nostdlib`/`-nostartfiles` link path; do not switch it to `picolibc.specs`.

P3 Vivado create scripts must make repo-local PyHP visible. `scripts/p3_create_bd.tcl` prepends `${repo}/piton/tools/bin` to Tcl `env(PATH)` because the common PyHP preprocessing helper executes `pyhp.py` by name. If a remote run reports `couldn't execute "pyhp.py"`, check that this PATH setup reached the remote copy before changing generated `.tmp` files.

The 64-core DTB must expose `cpu@0` through `cpu@63`, CLINT timer/software interrupt contexts for every hart, PLIC M/S contexts for every hart, UART source 1, and `riscv,ndev = <2>`. Do not claim a 64-core Linux boot until UART logs show OpenSBI entry, Linux banner, `SMP: Total of 64 processors activated`, `/bin/sh`, and `/proc/cpuinfo` or `nproc` reporting 64 CPUs.

## P3 Build 66 Baseline

Build 66 is the current validated HuaPro P3 OpenPiton+Ariane baseline. Use `huaprop3_build66_baseline/debug_build/p3_top_build66_normal_spi_sd_boot.pdi` and the matching `.ltx` for board programming unless a newer validated build supersedes it.

The build wrapper is `scripts/p3_build66_normal_spi_sd_boot.tcl`. Future clean rebuilds should target the repository-root `p3b66/` work directory by default; override with `P3_BUILD66_WORK_DIR` only when debugging a path-specific Vivado issue. The repository-root `p3b66_validated_snapshot/` is a full copy of the previously validated `/mnt/d/p3b66` workspace and is only a recovery/cache source.

Build 66 and all scaling successors such as Build 67 must be self-contained Vivado projects. The wrappers force `P3_SELF_CONTAINED_SOURCES=1`, causing `scripts/p3_create_bd.tcl` to copy RTL, headers, constraints, top files, and shims into `<workdir>/source_snapshot/` and add files from that snapshot. Include directories must be copied recursively while preserving subdirectory names; Ariane/CVA6 includes such as `register_interface/assign.svh` and `register_interface/typedef.svh` are resolved by relative `include` paths during synthesis. Do not accept `.xpr` files that reference live repository sources under `piton/`, stale mirrors under `Z:/tmp`, or old `D:/p3b*` workspaces; rerun project creation if the self-contained validation fails. Generated BD wrappers and IP products remain under the Vivado project `.gen/.srcs/.cache` directories.

For multicore P3 builds, the PyHP-generated tile configuration must be regenerated as one consistent set before Vivado project creation: `piton/design/include/define.tmp.h`, `piton/design/chip/rtl/chip.tmp.v`, `piton/design/chipset/rtl/chipset_impl.tmp.v`, `piton/design/chip/tile/common/rtl/flat_id_to_xy.tmp.v`, and `piton/design/chip/tile/common/rtl/xy_to_flat_id.tmp.v`. The generated `define.tmp.h` inside both the live repo and `<workdir>/source_snapshot/` must match `PITON_X_TILES`, `PITON_Y_TILES`, and `PITON_NUM_TILES`; otherwise synthesis can instantiate multiple tiles while sizing interrupt/debug vectors for one tile.

The baseline keeps the original AXI16550 UART path, SPI-mode SD path, DDR address translation, and four compact BD-owned ILAs. Latest self-contained validation: the 2026-06-05 fresh `p3b66/source_snapshot/` rebuild programmed with `DONE bit: HIGH`, refreshed debug hub `0x3ffc0000000`, enumerated four ILAs, booted through BBL into Linux 5.1.0-rc7, reached `/bin/sh` on `/dev/ttyUSB0` at `115200 8N1`, and accepted slow UART input (`P3_B66_SELF_OK`, `uname -a`). Previous runtime validation also mounted `/dev/piton_sd2` as ext2 read-only and launched `/mnt/XSBench -s small -p 1 -l 1`.

Build 67 is the first 2x1 scaling candidate and must follow the same self-contained source-snapshot rule. Its wrapper is `scripts/p3_build67_2x1_normal_spi_sd_boot.tcl`; the default work directory is `p3b67_2x1/`, and published artifacts are `huaprop3_build67_2x1_baseline/debug_build/p3_top_build67_2x1_normal_spi_sd_boot.pdi` plus `.ltx`. Before project creation, regenerate the tile-dependent PyHP outputs as a consistent set and validate both live and snapshot `define.tmp.h` against `PITON_X_TILES=2`, `PITON_Y_TILES=1`, and `PITON_NUM_TILES=2`. The 2026-06-05 implementation candidate routed successfully with 258,405 fully routed nets, 0 routing errors, `WNS=16.312 ns`, and PDI SHA256 `f979264a5e43e5f1e90061590da79ed0d54c080e7aac384762219f993c978ed0`. The 2026-06-08/09 hardware retests programmed successfully, refreshed debug hub `0x3ffc0000000`, enumerated four ILAs, booted through SPI-SD init, copied all 65,536 payload blocks to DDR, matched DDR/SD payload words, and entered BBL with a 2-hart DTB. Complete logs prove Linux 5.1.0-rc7 can print after BBL `mret` and reach `Run /bin/sh as init process`; the active Build 67 gate is now reproducible normal-image shell interaction and `/dev/piton_sd2`/XSBench validation. If the SD card currently contains a `B67M` marker image, rewrite `build/huaprop3/sd_images/huaprop3_linux_xsbench_2x1.img` before drawing conclusions from post-`mret` UART behavior.

Old P3 debug projects are archived outside the repository root. Repo-local historical build folders are under `/home/illya/p3_cleanup_archive/2026-06-04-build66-baseline/repo_dirs/`; old Vivado workspaces are under `/mnt/d/p3_cleanup_archive/2026-06-04-build66-baseline/workspaces/`. Keep `huaprop3onecore/` as the board-level reference project. Do not commit `p3b66/`, `p3b66_validated_snapshot/`, PDI/LTX/CSV files, or SD-card images.

## R1: Mandatory Wiki Sync Rule

**Every code change MUST include corresponding wiki updates. No exceptions. No "sync later".**

The project wiki lives at `wiki/` in the repository root. See `wiki/INDEX.md` for the full structure.

### Trigger Conditions (when wiki sync is REQUIRED)

1. **RTL change** -- update the relevant `wiki/concepts/` article (resource estimates, timing notes, coding rules, etc.)
2. **New board / platform port** -- update `architecture-evolution.md`, `resource-estimation.md`, and add devlog entry
3. **Build flow / tooling change** -- update `vivado-tooling.md` or `simulation.md`
4. **Scaling milestone reached** -- update `wiki/INDEX.md` timeline, add devlog entry
5. **Bug fix that revealed a non-obvious root cause** -- add to the relevant concept article's "Pitfalls" or "Lessons" section
6. **New FPGA synthesis results** -- update `resource-estimation.md` and/or `timing-closure.md` with actual numbers
7. **Device tree / address map change** -- update wiki if it affects scaling design
8. **Any decision that affects the P0-P4 roadmap** -- update `wiki/INDEX.md` timeline

### Anti-Patterns (NEVER do these)

- **"I'll update the wiki in a follow-up"** -- No. Wiki sync is part of the change, not a separate task.
- **Wiki article with only a title and "TBD"** -- Every article must have at least a one-paragraph summary. Stub sections within an article are OK if labeled `(TBD)`.
- **Devlog entries without dates** -- Every devlog entry must have an ISO date heading (`## YYYY-MM-DD -- <title>`).
- **Updating code numbers without updating wiki numbers** -- If you change resource usage, clock frequencies, timing results, or core counts in code/constraints, the wiki MUST reflect the new values in the same commit.
- **Orphan wiki articles** -- Every article must be linked from `wiki/INDEX.md`.
- **Deleting wiki content without replacement** -- If information is outdated, update it; don't delete it.

### Devlog Rules

- File naming: `wiki/devlog/YYYY-MM.md` (one file per month)
- Entries are append-only, newest first within each file
- Each entry: `## YYYY-MM-DD -- <short title>` followed by bullet points
- Never edit past entries (append corrections as new entries)

### Git Commit Requirement (ABSOLUTE)

**Every wiki update MUST be committed to git and pushed to GitHub immediately. No exceptions. No queuing for later.**

- After writing ANY wiki file (devlog, concept article, INDEX.md), immediately run `git add <file>` and `git commit` with a descriptive message.
- Wiki commits should use the prefix `wiki:` (e.g., `wiki: add May 23 devlog — Build 19 reset fix verified`).
- After committing, push to the remote: `git push origin openpiton`.
- **Anti-pattern**: accumulating multiple wiki changes without committing. Each logical update gets its own commit.
- **Anti-pattern**: "I'll commit after this build finishes." No — commit the wiki changes NOW. The build proceeds independently.
- If a build or debug session spans hours, commit wiki updates incrementally — don't wait until the end of the session.
- CLAUDE.md and AGENTS.md changes follow the same rule: commit and push immediately.
