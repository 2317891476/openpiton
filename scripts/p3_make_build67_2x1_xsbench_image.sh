#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base_img="${P3_BUILD67_BASE_IMG:-$repo_dir/build/huaprop3/sd_images/huaprop3_linux_xsbench_ext2.img}"
out_img="${P3_BUILD67_OUT_IMG:-$repo_dir/build/huaprop3/sd_images/huaprop3_linux_xsbench_2x1.img}"
bootargs='earlycon=uart8250,mmio,0xfff0c2c000,115200n8 console=ttyS0,115200n8 rdinit=/bin/sh init=/bin/sh'

export PITON_ROOT="${PITON_ROOT:-$repo_dir}"
export DV_ROOT="${DV_ROOT:-$repo_dir/piton}"
export PITON_X_TILES=2
export PITON_Y_TILES=1
export PITON_NUM_TILES=2
export PITON_SIFIVE_UART=0
export CONFIG_SYS_FREQ="${CONFIG_SYS_FREQ:-30000000}"

if [[ ! -f "$base_img" ]]; then
    echo "ERROR: missing base XSBench image: $base_img" >&2
    exit 1
fi

"$repo_dir/scripts/p3_rebuild_build67_2x1_normal_spi_sd_boot.sh"

bootrom_dts="$repo_dir/piton/design/chipset/rv64_platform/bootrom/rv64_platform.dts"
build_dir="$repo_dir/build/huaprop3"
build_dts="$build_dir/huaprop3_2x1_xsbench.dts"
build_dtb="$build_dir/huaprop3_2x1_xsbench.dtb"
bbl_dir="$repo_dir/build/huaprop3/ariane-sdk/build-bbl-debug-axi16550-force"
bbl_bin="$build_dir/bbl_build67_2x1_xsbench.bin"

if [[ ! -d "$bbl_dir" ]]; then
    echo "ERROR: missing BBL build directory: $bbl_dir" >&2
    exit 1
fi

awk -v bootargs="$bootargs" '
    /^    chosen \{/ { in_chosen = 1 }
    in_chosen && /^[[:space:]]*bootargs[[:space:]]*=/ { next }
    in_chosen && /^    \};/ {
        print "        bootargs = \"" bootargs "\";"
        in_chosen = 0
    }
    { print }
' "$bootrom_dts" > "$build_dts"

dtc -I dts "$build_dts" -O dtb -o "$build_dtb"
dtc -I dtb "$build_dtb" -O dts | grep -q 'cpu@1'
dtc -I dtb "$build_dtb" -O dts | grep -q 'rdinit=/bin/sh init=/bin/sh'

cp "$build_dts" "$bbl_dir/huaprop3.dts"
cp "$build_dtb" "$bbl_dir/huaprop3.dtb"
od -An -tx1 -v "$build_dtb" \
    | sed 's/^ *//; s/  */, 0x/g; s/^/  0x/; s/$/,/' \
    > "$bbl_dir/embedded_dtb.h"

make -C "$bbl_dir" clean
env CFLAGS="-fno-stack-protector -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0" make -C "$bbl_dir"

riscv64-linux-gnu-objcopy \
    -S -O binary --change-addresses -0x80000000 \
    "$bbl_dir/bbl" \
    "$bbl_bin"

mkdir -p "$(dirname "$out_img")"
cp "$base_img" "$out_img"

part_info="$(sfdisk -d "$out_img" | sed -n 's/.*1 : start=[[:space:]]*\([0-9][0-9]*\), size=[[:space:]]*\([0-9][0-9]*\),.*/\1 \2/p' | head -n 1)"
if [[ -z "$part_info" ]]; then
    echo "ERROR: failed to locate partition 1 in $out_img" >&2
    exit 1
fi
read -r part_start part_size <<< "$part_info"
part_bytes=$((part_size * 512))
bbl_bytes="$(stat -c %s "$bbl_bin")"
if (( bbl_bytes > part_bytes )); then
    echo "ERROR: BBL payload ($bbl_bytes bytes) exceeds partition 1 ($part_bytes bytes)" >&2
    exit 1
fi

dd if=/dev/zero of="$out_img" bs=512 seek="$part_start" count="$part_size" conv=notrunc status=none
dd if="$bbl_bin" of="$out_img" bs=512 seek="$part_start" conv=notrunc status=progress

echo "Build 67 2x1 XSBench image written: $out_img"
echo "Embedded DTB: $build_dtb"
echo "BBL binary: $bbl_bin"
