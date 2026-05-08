# AX7023/AX7203 Linux Bring-Up Reproduction Notes

This repository currently uses the `a7203x` prototyping target and AX7203 board
files. If lab notes refer to the board as AX7023, first confirm that the FPGA
part, DDR3 wiring, SD card wiring, UART pins, and XDC constraints match the
checked-in `a7203x` target. The flow below describes the validated
`a7203x`/AX7203 path.

## Overall Flow

A full reproduction has five stages:

1. Prepare the OpenPiton/Ariane workspace and RISC-V toolchains.
2. Generate or obtain the SD card boot image `bbl.bin`.
3. Partition the SD card with two GPT partitions, write `bbl.bin` to the first
   partition, and place test programs on the second partition.
4. Synthesize and program the FPGA bitstream.
5. Boot Linux through UART, mount the second SD partition, and run `hello` and
   `XSBench`.

The boot chain is:

```text
FPGA bootrom -> SD card GPT partition 1 raw bbl.bin -> BBL -> Linux kernel + initramfs rootfs -> Buildroot login
```

Partition 1 is not a normal filesystem. It contains a raw `bbl.bin` image.
Partition 2 is the filesystem mounted after Linux boots, and is used for
programs such as `hello` and `XSBench`.

## Hardware Setup

- FPGA board: ALINX AX7203-compatible board for the `a7203x` target.
- UART terminal: 115200 baud, 8 data bits, no parity, 1 stop bit, no flow
  control.
- JTAG: Vivado Hardware Manager can detect and program the FPGA.
- SD card: 8 GB or larger is recommended. Every write-card command below can
  destroy existing card contents, so confirm the device name before running it.

On the Linux/WSL host, check the SD card device name with:

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,RM,MOUNTPOINTS
sudo fdisk -l
```

The commands below use `/dev/sdX` for the whole SD card. Replace it with the
real device, for example `/dev/sdb`. Do not use the system disk.

## Prepare The Workspace

From the repository root:

```bash
export PITON_ROOT=/home/illya/openpiton
cd $PITON_ROOT
source piton/piton_settings.bash
source piton/ariane_setup.sh
```

For a first-time Ariane toolchain setup, run:

```bash
cd $PITON_ROOT
piton/ariane_build_tools.sh
```

That script initializes the Ariane submodule and builds RISC-V GCC, FESVR,
Spike, Verilator, and RISC-V tests. It does not directly generate the SD card
Linux image. The SD card image is produced through the ariane-sdk `bbl.bin`
flow.

## Generate The SD Card Boot Image

SD card partition 1 needs `bbl.bin`. This file is not only a bootloader. In the
usual Ariane SDK flow it contains:

- BBL/RISC-V proxy kernel startup code.
- Linux kernel `vmlinux` as the BBL payload.
- The Buildroot initramfs/rootfs, packaged as `rootfs.cpio` and built into the
  Linux kernel config.

In other words, the FPGA bootrom copies `bbl.bin` from SD partition 1 into DDR
near `0x80000000`, then BBL enters Linux. The Buildroot root filesystem is
already inside the kernel initramfs, so a normal Linux boot does not depend on
partition 2. Partition 2 is only for extra test programs and data.

### Option 1: Use A Prebuilt bbl.bin

If a known-working `bbl.bin` is available, it can be used directly. Local paths
that have been used during validation include:

```text
build/a7203x/bbl.bin
build/a7203x/working_snapshot_20260506/bbl_working.bin
```

Files under `build/` are local generated artifacts and should not be committed
to GitHub. Before writing the card, record the size and hash to avoid using the
wrong image:

```bash
sha256sum build/a7203x/bbl.bin
stat -c '%n %s bytes' build/a7203x/bbl.bin
```

Partition 1 is 32 MiB, so `bbl.bin` must be smaller than that. The validated
`bbl.bin` was roughly 15 MiB.

### Option 2: Rebuild With ariane-sdk

The original OpenPiton README flow uses ariane-sdk to generate the Linux boot
image. A typical command is:

```bash
cd /path/to/ariane-sdk
make bbl.bin
```

The dependency chain in the local `build/a7203x/ariane-sdk/Makefile` is:

```text
make bbl.bin
  -> make bbl
    -> make vmlinux
      -> make -C buildroot defconfig BR2_DEFCONFIG=../configs/buildroot_defconfig
      -> make -C buildroot
    -> riscv-pk/configure --with-payload=vmlinux --enable-logo ...
    -> make -C build
  -> riscv64-unknown-elf-objcopy ... bbl bbl.bin
```

Important configuration files include:

```text
configs/buildroot_defconfig
configs/linux_defconfig
configs/busybox.config
configs/0099-Piton-SD-Driver.patch
rootfs/
```

`buildroot_defconfig` configures Buildroot to:

- Use the external RISC-V Linux toolchain.
- Fetch the kernel from the `ariane-v0.7` branch of `pulp-platform/linux`.
- Apply `0099-Piton-SD-Driver.patch`.
- Use `rootfs/` as the Buildroot overlay.
- Enable packages such as OpenSSH, NFS, e2fsprogs, ncurses, zlib, and lynx.
- Generate an initramfs with `BR2_TARGET_ROOTFS_INITRAMFS=y`.

`linux_defconfig` configures Linux to:

- Enable the initramfs with
  `CONFIG_INITRAMFS_SOURCE="${BR_BINARIES_DIR}/rootfs.cpio"`.
- Enable the 8250 UART console.
- Enable the SiFive PLIC.
- Enable OpenPiton/Ariane ramdisk-related settings.
- Enable the SD/MMC/SPI/EXT3/NFS kernel support needed by `piton_sd`.

If only RTL is being changed or the bitstream is being rebuilt, `bbl.bin`
usually does not need to be regenerated. Regenerate it and rewrite SD partition
1 when changing Linux, Buildroot, the rootfs overlay, BBL, the SD driver patch,
or boot arguments.

## Prepare The SD Card

### 1. Unmount Old Partitions

Confirm the device name first, then unmount any partitions that were
automatically mounted:

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,RM,MOUNTPOINTS
sudo umount /dev/sdX1 2>/dev/null || true
sudo umount /dev/sdX2 2>/dev/null || true
```

### 2. Create The GPT Partition Table

The repository README uses this layout:

```bash
sudo sgdisk --clear \
  --new=1:2048:67583 \
  --new=2 \
  --typecode=1:3000 \
  --typecode=2:8300 \
  /dev/sdX
```

Meaning:

- Partition 1: LBA 2048 through 67583, 65536 sectors of 512 bytes each, or
  32 MiB. The raw `bbl.bin` image is written here.
- Partition 2: all remaining space, Linux filesystem, visible on the board as
  `/dev/piton_sd2`.
- `typecode=1:3000` is the ONIE boot type. The bootrom needs the first GPT
  partition start location; it does not need a filesystem inside it.
- `typecode=2:8300` is a normal Linux filesystem partition type.

Ask the host to reread the partition table:

```bash
sudo partprobe /dev/sdX
lsblk /dev/sdX
```

### 3. Write bbl.bin To Partition 1

For the local generated image:

```bash
sudo dd if=build/a7203x/bbl.bin of=/dev/sdX1 bs=1M status=progress oflag=sync
sync
```

For another image path:

```bash
sudo dd if=/path/to/bbl.bin of=/dev/sdX1 bs=1M status=progress oflag=sync
sync
```

Write to the partition `/dev/sdX1`, not the whole disk `/dev/sdX`. Writing to
the whole disk would overwrite the GPT partition table.

### 4. Format Partition 2 And Copy Tests

The kernel config explicitly enables EXT3, so format partition 2 as ext3:

```bash
sudo mkfs.ext3 -F -L PITON_TEST /dev/sdX2
sudo mkdir -p /mnt/piton-sd
sudo mount /dev/sdX2 /mnt/piton-sd
```

Copy the test programs to partition 2:

```bash
sudo cp /path/to/hello /mnt/piton-sd/hello
sudo cp /path/to/XSBench /mnt/piton-sd/XSBench
sudo chmod +x /mnt/piton-sd/hello /mnt/piton-sd/XSBench
sync
sudo umount /mnt/piton-sd
```

If the host already has a cross-compiled XSBench, the local path used during
validation was:

```text
build/a7203x/XSBench/openmp-threading/XSBench
```

`hello` can be any RISC-V Linux userspace executable. Minimal example:

```c
#include <stdio.h>

int main(void) {
    puts("hello from OpenPiton/Ariane");
    return 0;
}
```

Cross-compile it with:

```bash
riscv64-unknown-linux-gnu-gcc -static -O2 hello.c -o hello
```

Build XSBench with:

```bash
git clone https://github.com/ANL-CESAR/XSBench.git
cd XSBench/openmp-threading
make clean
make CC=riscv64-unknown-linux-gnu-gcc OPENMP=no
```

If OpenMP is enabled, confirm that the Buildroot/rootfs image contains a
matching OpenMP runtime. For the first board sanity check, build a single-thread
binary with `OPENMP=no`.

## Build The Bitstream

From the repository root:

```bash
export PITON_ROOT=/home/illya/openpiton
source $PITON_ROOT/piton/piton_settings.bash
cd $PITON_ROOT/build
protosyn -b a7203x -d system --core=ariane --uart-dmw ddr
```

For a first full reproduction, do not set `PITON_SKIP_ARIANE_FW_BUILD=1`. During
the setup stage, `protosyn` regenerates:

- Baremetal bootrom.
- Linux bootrom.
- Ariane PLIC register map.

The Ariane PLIC generation logic in `setup.tcl` is:

```text
NUM_TARGETS = 2 * PITON_NUM_TILES
NUM_SOURCES = 2
gen_plic_addrmap.py -t NUM_TARGETS -s NUM_SOURCES > plic_regmap.sv
```

If `PITON_SKIP_ARIANE_FW_BUILD=1` is set, this step is skipped too. Use it only
when the bootroms and `plic_regmap.sv` are already known-good and only the RTL
implementation is being repeated:

```bash
export PITON_SKIP_ARIANE_FW_BUILD=1
cd $PITON_ROOT/build
protosyn -b a7203x -d system --core=ariane --uart-dmw ddr
```

The generated bitstream is:

```text
build/a7203x/system/a7203x_system.runs/impl_1/system.bit
```

After implementation, check timing:

```bash
rg -n "All user specified timing constraints are met|WNS|WHS" \
  build/a7203x/system/a7203x_system.runs/impl_1/system_timing_summary_routed.rpt
```

Check PLIC width warnings:

```bash
rg -n "plic_regs|width .*port" \
  build/a7203x/system/a7203x_system.runs/synth_1/runme.log
```

For the 2-source PLIC register map, unused high bits of `req_i[wdata]` in
`plic_regs` are expected. Width mismatch warnings on `prio_o`, `prio_we_o`,
`ie_o`, or `cc_o` are not expected.

## Program The FPGA

Use Vivado Hardware Manager, or a Tcl script equivalent to:

```tcl
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
set_property PROGRAM.FILE {Z:/home/illya/openpiton/build/a7203x/system/a7203x_system.runs/impl_1/system.bit} [current_hw_device]
program_hw_devices [current_hw_device]
close_hw_manager
```

A successful program operation should report:

```text
End of startup status: HIGH
```

## Boot Linux

Put the SD card back into the FPGA board. Open the UART terminal before or
immediately after programming the FPGA. Use:

```text
115200 8N1, no flow control
```

Expected boot markers include:

```text
OpenPiton+Ariane Platform
sd initialized!
gpt partition table header:
copying boot image
done!
bbl loader
Linux version 5.1.0-rc7
plic: mapped 2 interrupts with 1 handlers for 2 contexts.
fff0c2c000.uart: ttyS0 at MMIO 0xfff0c2c000 (irq = 1, base_baud = 1875000) is a 16550
Starting logging: OK
Starting sshd: OK
NFS preparation skipped, OK
Welcome to Buildroot
buildroot login:
```

Log in as `root` unless the SD image has been customized with another account.

## Run SD Card Tests

After logging in through the serial terminal, run:

```sh
mount /dev/piton_sd2 /mnt
/mnt/hello
/mnt/XSBench -s small -l 100
```

Use `-s small` to reduce the XSBench problem size. Use `-l 100` for the first
sanity check because the single-core 50 MHz system is slow. After the quick run
works, a longer run can be used:

```sh
/mnt/XSBench -s small -l 1000
```

If `/mnt/hello` does not execute, check that the file exists and is executable:

```sh
ls -l /mnt
chmod +x /mnt/hello /mnt/XSBench
```

If mounting fails, confirm the kernel found the SD controller and exposed the
partitions:

```sh
dmesg | grep -i piton_sd
ls -l /dev/piton_sd*
```

If `/dev/piton_sd2` exists but `mount` fails, first confirm that partition 2 was
formatted with a filesystem supported by the kernel. EXT3 is recommended for
this flow.

## Known Good Validation Point

The currently validated flow reached:

```text
Starting logging: OK
Starting sshd: OK
NFS preparation skipped, OK
Welcome to Buildroot
buildroot login:
```

The validated PLIC configuration is a 2-source register map in:

```text
piton/design/chip/tile/ariane/corev_apu/rv_plic/rtl/plic_regmap.sv
```

If Linux reaches `/init` but no longer prints `Starting logging: OK` or
`Welcome to Buildroot`, re-check that the synthesized PLIC register map matches
the `NumSources=2` OpenPiton/Ariane instance.

## Troubleshooting

- No UART output: verify the terminal is connected to the board USB-UART port,
  configured as 115200 8N1 with flow control disabled, and that no other
  program owns the COM port.
- Bootrom prints but SD initialization fails: check that the SD card is inserted,
  the partition table is GPT, and the SD card pin constraints match the board.
- GPT is printed but BBL/Linux does not start: confirm that `bbl.bin` was written
  to `/dev/sdX1`, not `/dev/sdX`, and that `bbl.bin` is smaller than 32 MiB.
- Boot stops around user-space random or ssh messages: check for PLIC
  `plic_regs` width mismatch warnings in Vivado synthesis logs.
- Old bitstream works but rebuilt bitstream does not: compare the `system.bit`
  SHA256 and confirm the rebuilt source includes the 2-source `plic_regmap.sv`.
- `XSBench` appears to hang: start with `-s small -l 100`; the 50 MHz single-core
  build can take a long time on larger lookup counts.
- `XSBench` reports missing shared libraries: rebuild it statically with
  `riscv64-unknown-linux-gnu-gcc -static`, disable OpenMP, or add the required
  runtime libraries to Buildroot/rootfs.
