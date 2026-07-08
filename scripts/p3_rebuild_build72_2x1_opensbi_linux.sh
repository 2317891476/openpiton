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
export PITON_X_TILES=2
export PITON_Y_TILES=1
export PITON_NUM_TILES=2
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
export P3_OPENSBI_FW_ADDR="${P3_OPENSBI_FW_ADDR:-0x80000000}"
export P3_OPENSBI_DTB_ADDR="${P3_OPENSBI_DTB_ADDR:-0x88000000}"

export RISCV="${RISCV:-$HOME/scratch/riscv_install}"
bootrom_extra_make_args=()
if [[ -x "$RISCV/bin/riscv64-unknown-elf-gcc" ]]; then
    export PATH="$RISCV/bin:$PATH"
elif [[ -f /usr/lib/picolibc/riscv64-unknown-elf/include/stdint.h ]]; then
    bootrom_extra_make_args+=("P3_BOOTROM_EXTRA_CFLAGS=-isystem /usr/lib/picolibc/riscv64-unknown-elf/include")
    echo "Using system riscv64-unknown-elf-gcc with picolibc headers."
fi

baremetal_bootrom_dir="$repo_dir/piton/design/chipset/rv64_platform/bootrom/baremetal"
cd "$baremetal_bootrom_dir"

rm -f bootrom.img bootrom.sv bootrom.bin bootrom.elf bootrom.h rv64_platform.dtb
companion_dts="$(mktemp)"
trap 'rm -f "$companion_dts"' EXIT
cat > "$companion_dts" <<'DTS'
/dts-v1/;

/ {
    #address-cells = <2>;
    #size-cells = <2>;
    compatible = "openpiton,build72-companion-bootrom";

    memory@80000000 {
        device_type = "memory";
        reg = <0x0 0x80000000 0x0 0x10000000>;
    };

    cpus {
        #address-cells = <1>;
        #size-cells = <0>;
        timebase-frequency = <234375>;

        cpu@0 {
            device_type = "cpu";
            reg = <0>;
            status = "okay";
            compatible = "openhwgroup,cva6", "riscv";
            riscv,isa = "rv64imafdc";
            mmu-type = "riscv,sv39";
        };
    };
};
DTS
dtc -I dts "$companion_dts" -O dtb -o rv64_platform.dtb
"${CROSSCOMPILE:-riscv64-unknown-elf-}gcc" -Tlinker.ld bootrom.S -nostdlib -static -Wl,--no-gc-sections -o bootrom.elf
"${CROSSCOMPILE:-riscv64-unknown-elf-}objcopy" -O binary bootrom.elf bootrom.bin
dd if=bootrom.bin of=bootrom.img bs=128
python3 ./gen_rom.py bootrom.img
rm -f bootrom.bin bootrom.elf rv64_platform.dtb
trap - EXIT
rm -f "$companion_dts"

if ! awk -v module_name="bootrom" '$1 == "module" && $2 == module_name { found = 1 } END { exit found ? 0 : 1 }' bootrom.sv; then
    echo "ERROR: Build 72 (2x1) baremetal bootrom.sv does not define module bootrom" >&2
    exit 1
fi
echo "Build 72 (2x1) companion baremetal bootrom generated: $baremetal_bootrom_dir/bootrom.sv"

bootrom_dir="$repo_dir/piton/design/chipset/rv64_platform/bootrom/linux"
cd "$bootrom_dir"

make clean
make all \
    BOOTROM_MODE=opensbi_bundle \
    PITON_SIFIVE_UART=0 \
    MAX_HARTS="$PITON_NUM_TILES" \
    UART_FREQ="$CONFIG_SYS_FREQ" \
    P3_OPENSBI_FW_ADDR="$P3_OPENSBI_FW_ADDR" \
    P3_OPENSBI_DTB_ADDR="$P3_OPENSBI_DTB_ADDR" \
    "${bootrom_extra_make_args[@]}"

riscv64-unknown-elf-objdump -d bootrom_linux.elf > bootrom_linux_build72_2x1_opensbi_linux.dump
if ! grep -q '<_prog_start>' bootrom_linux_build72_2x1_opensbi_linux.dump; then
    echo "ERROR: Build 72 (2x1) bootrom is missing _prog_start" >&2
    exit 1
fi
if ! grep -qE '\bsp,' bootrom_linux_build72_2x1_opensbi_linux.dump; then
    echo "ERROR: Build 72 (2x1) bootrom did not set the C stack pointer" >&2
    exit 1
fi
if ! riscv64-unknown-elf-nm bootrom_linux.elf | grep -qE ' main$'; then
    echo "ERROR: Build 72 (2x1) bootrom is missing main()" >&2
    exit 1
fi
for symbol in init_uart print_uart init_sd sd_copy; do
    if ! riscv64-unknown-elf-nm bootrom_linux.elf | grep -qE " ${symbol}$"; then
        echo "ERROR: Build 72 (2x1) bootrom missing expected C symbol: ${symbol}" >&2
        exit 1
    fi
done
if riscv64-unknown-elf-nm bootrom_linux.elf | grep -qE ' gpt_find_boot_partition$|startup_asm_uart|startup_asm_uart16550'; then
    echo "ERROR: Build 72 (2x1) bootrom linked an unexpected BBL or assembly UART-only path" >&2
    exit 1
fi
if ! awk -v module_name="bootrom_linux" '$1 == "module" && $2 == module_name { found = 1 } END { exit found ? 0 : 1 }' bootrom_linux.sv; then
    echo "ERROR: Build 72 (2x1) bootrom_linux.sv does not define module bootrom_linux" >&2
    exit 1
fi

echo "Build 72 (2x1) 8x8 OpenSBI bundle bootrom generated: $bootrom_dir/bootrom_linux.sv"
