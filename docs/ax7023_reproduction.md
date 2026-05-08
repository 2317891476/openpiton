# AX7023/AX7203 Linux Bring-Up Reproduction Notes

This repository currently uses the `a7203x` prototyping target and AX7203
board files. If the board is referred to as AX7023 in lab notes, first confirm
that the FPGA part, DDR3 wiring, SD card wiring, UART pins, and XDC constraints
match the checked-in `a7203x` target.

## Hardware Setup

- FPGA board: ALINX AX7203-compatible board for the `a7203x` target.
- UART terminal: 115200 baud, 8 data bits, no parity, 1 stop bit, no flow control.
- Boot media: SD card containing the OpenPiton/Ariane Linux image and test
  binaries.
- JTAG connection: available to Vivado Hardware Manager.

The SD card should contain the Linux boot image and a second partition visible
inside Linux as `/dev/piton_sd2`. The examples below assume that `/dev/piton_sd2`
contains `hello` and `XSBench`.

## Build The Bitstream

From the repository root:

```bash
export PITON_ROOT=/home/illya/openpiton
source $PITON_ROOT/piton/piton_settings.bash
export PITON_SKIP_ARIANE_FW_BUILD=1
cd $PITON_ROOT/build
protosyn -b a7203x -d system --core=ariane --uart-dmw ddr
```

The generated bitstream is:

```text
build/a7203x/system/a7203x_system.runs/impl_1/system.bit
```

After implementation, check that timing passed and that there are no PLIC
register-map width mismatch warnings:

```bash
rg -n "All user specified timing constraints are met|WNS|WHS" \
  build/a7203x/system/a7203x_system.runs/impl_1/system_timing_summary_routed.rpt

rg -n "plic_regs|width .*port" \
  build/a7203x/system/a7203x_system.runs/synth_1/runme.log
```

Warnings about unused high bits of `req_i[wdata]` in `plic_regs` are expected
for the 2-source PLIC register map. Width mismatch warnings on `prio_o`,
`prio_we_o`, `ie_o`, or `cc_o` are not expected.

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

Open the UART terminal before or immediately after programming the FPGA.
Use:

```text
115200 8N1, no flow control
```

Expected boot markers include:

```text
OpenPiton+Ariane Platform
sd initialized!
bbl loader
Linux version 5.1.0-rc7
plic: mapped 2 interrupts with 1 handlers for 2 contexts.
fff0c2c000.uart: ttyS0 at MMIO 0xfff0c2c000 (irq = 1, base_baud = 1875000) is a 16550
Starting logging: OK
Starting sshd: OK
Welcome to Buildroot
buildroot login:
```

Log in as `root` unless the SD image has been customized with another account.

## Run SD Card Tests

Put the SD card back into the FPGA board and boot Linux to the Buildroot login
prompt. In the serial terminal, run:

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
  configured as 115200 8N1 with flow control disabled, and that no other program
  owns the COM port.
- Boot stops around user-space random or ssh messages: check for PLIC
  `plic_regs` width mismatch warnings in Vivado synthesis logs.
- Old bitstream works but rebuilt bitstream does not: compare the `system.bit`
  SHA256 and confirm the rebuilt source includes the 2-source `plic_regmap.sv`.
- `XSBench` appears to hang: start with `-s small -l 100`; the 50 MHz single-core
  build can take a long time on larger lookup counts.
