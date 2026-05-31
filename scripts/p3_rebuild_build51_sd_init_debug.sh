#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PITON_ROOT="${PITON_ROOT:-$repo_dir}"
export DV_ROOT="${DV_ROOT:-$repo_dir/piton}"
export ARIANE_ROOT="${ARIANE_ROOT:-$DV_ROOT/design/chip/tile/ariane}"
export PROTOSYN_RUNTIME_DESIGN_PATH="${PROTOSYN_RUNTIME_DESIGN_PATH:-$DV_ROOT/design/xilinx}"
export PROTOSYN_RUNTIME_BOARD="${PROTOSYN_RUNTIME_BOARD:-huaprop3}"
export PITON_ARIANE=1
export PITON_RV64_PLATFORM=1
export PITON_X_TILES=1
export PITON_Y_TILES=1
export PITON_NUM_TILES=1
export PITON_NETWORK_CONFIG="${PITON_NETWORK_CONFIG:-2dmesh_config}"
export CONFIG_SYS_FREQ="${CONFIG_SYS_FREQ:-30000000}"
export CONFIG_L15_SIZE="${CONFIG_L15_SIZE:-8192}"
export CONFIG_L15_ASSOCIATIVITY="${CONFIG_L15_ASSOCIATIVITY:-4}"
export CONFIG_L1D_SIZE="${CONFIG_L1D_SIZE:-8192}"
export CONFIG_L1D_ASSOCIATIVITY="${CONFIG_L1D_ASSOCIATIVITY:-4}"
export CONFIG_L1I_SIZE="${CONFIG_L1I_SIZE:-16384}"
export CONFIG_L1I_ASSOCIATIVITY="${CONFIG_L1I_ASSOCIATIVITY:-4}"
export CONFIG_L2_SIZE="${CONFIG_L2_SIZE:-65536}"
export CONFIG_L2_ASSOCIATIVITY="${CONFIG_L2_ASSOCIATIVITY:-4}"

export RISCV="${RISCV:-$HOME/scratch/riscv_install}"
if [[ -x "$RISCV/bin/riscv64-unknown-elf-gcc" ]]; then
    export PATH="$RISCV/bin:$PATH"
fi

bootrom_dir="$repo_dir/piton/design/chipset/rv64_platform/bootrom/linux"
cd "$bootrom_dir"

make clean
make all BOOTROM_MODE=asm_uart16550_sdprobe PITON_SIFIVE_UART=0 MAX_HARTS=1 UART_FREQ="$CONFIG_SYS_FREQ"

riscv64-unknown-elf-objdump -d bootrom_linux.elf > bootrom_linux_build51.dump
if ! grep -q '<_prog_start>' bootrom_linux_build51.dump; then
    echo "ERROR: Build 51 bootrom is missing _prog_start" >&2
    exit 1
fi
if grep -qE '\bsp,' bootrom_linux_build51.dump; then
    echo "ERROR: Build 51 no-stack SD-init bootrom unexpectedly touches sp" >&2
    exit 1
fi
if ! riscv64-unknown-elf-nm bootrom_linux.elf | grep -qE ' main$'; then
    echo "ERROR: Build 51 bootrom is missing the assembly main alias" >&2
    exit 1
fi
if riscv64-unknown-elf-nm bootrom_linux.elf | grep -qE ' init_uart$| print_uart$| gpt_find_boot_partition$| sd_copy$'; then
    echo "ERROR: Build 51 no-stack SD-init bootrom unexpectedly linked C bootrom code" >&2
    exit 1
fi
echo "Build 51 no-stack AXI16550 SD-init probe bootrom generated: $bootrom_dir/bootrom_linux.sv"
