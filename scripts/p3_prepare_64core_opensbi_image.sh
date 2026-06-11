#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pkg_archive="${P3_64CORE_ARCHIVE:-$repo_dir/riscv64-linux-64core-src-20260610.tar.gz}"
work_dir="${P3_64CORE_WORK_DIR:-$repo_dir/build/p3_64core}"
pkg_dir="$work_dir/riscv64-linux-64core-src-20260610"
out_dir="$repo_dir/build/huaprop3/opensbi64"

harts="${P3_64CORE_HARTS:-64}"
jobs="${JOBS:-$(nproc)}"
cross="${CROSS_COMPILE:-riscv64-unknown-linux-gnu-}"
opensbi_platform="${OPENSBI_PLATFORM:-generic}"
use_prebuilt="${P3_64CORE_USE_PREBUILT:-0}"

fw_addr="${P3_OPENSBI_FW_ADDR:-0x80000000}"
image_addr="${P3_LINUX_IMAGE_ADDR:-0x80200000}"
dtb_addr="${P3_OPENSBI_DTB_ADDR:-0x88000000}"
initrd_addr="${P3_INITRD_ADDR:-0x90000000}"
bootargs="${P3_64CORE_BOOTARGS:-earlycon=uart8250,mmio,0xfff0c2c000 console=ttyS0,115200n8 root=/dev/ram0 rw loglevel=8 keep_bootcon initcall_debug}"

require_file() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        echo "ERROR: missing required file: $path" >&2
        exit 1
    fi
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: missing required command: $cmd" >&2
        exit 1
    fi
}

require_file "$pkg_archive"
require_cmd dtc
require_cmd sfdisk
if [[ "$use_prebuilt" != "1" ]]; then
    require_cmd "${cross}gcc"
fi
if command -v "${cross}objcopy" >/dev/null 2>&1; then
    objcopy="${cross}objcopy"
elif command -v riscv64-unknown-elf-objcopy >/dev/null 2>&1; then
    objcopy="riscv64-unknown-elf-objcopy"
else
    echo "ERROR: missing RISC-V objcopy; tried ${cross}objcopy and riscv64-unknown-elf-objcopy" >&2
    exit 1
fi

mkdir -p "$work_dir" "$out_dir"

if [[ ! -d "$pkg_dir" ]]; then
    tar -xzf "$pkg_archive" -C "$work_dir"
fi

if [[ "$use_prebuilt" == "1" ]]; then
    echo "[1/5] Using prebuilt 64core OpenSBI/Linux artifacts"
    fw_elf="$pkg_dir/artifacts/fw_jump.batch-tested.elf"
    linux_image="$out_dir/Image_p3_${harts}hart"
    cp "$pkg_dir/artifacts/Image.window-opt-tested" "$linux_image"
else
    echo "[1/5] Building P3 OpenSBI fw_jump"
    make -C "$pkg_dir/opensbi" clean
    make -C "$pkg_dir/opensbi" \
        PLATFORM="$opensbi_platform" \
        FW_PAYLOAD=n \
        FW_JUMP=y \
        FW_JUMP_ADDR="$image_addr" \
        FW_JUMP_FDT_ADDR="$dtb_addr" \
        CROSS_COMPILE="$cross" \
        -j"$jobs"

    fw_elf="$pkg_dir/opensbi/build/platform/$opensbi_platform/firmware/fw_jump.elf"
fi
fw_bin="$out_dir/fw_jump_p3_64core.bin"
require_file "$fw_elf"
"$objcopy" -S -O binary "$fw_elf" "$fw_bin"

if [[ "$use_prebuilt" != "1" ]]; then
    echo "[2/5] Building Linux Image NR_CPUS=$harts"
    cp "$pkg_dir/configs/linux.config.64core" "$pkg_dir/linux/.config"
    "$pkg_dir/linux/scripts/config" --set-val CONFIG_NR_CPUS "$harts"
    "$pkg_dir/linux/scripts/config" --enable CONFIG_SMP
    "$pkg_dir/linux/scripts/config" --enable CONFIG_RISCV_SBI
    PATH=/usr/bin:/bin:$PATH make -C "$pkg_dir/linux" \
        ARCH=riscv \
        CROSS_COMPILE="$cross" \
        olddefconfig
    PATH=/usr/bin:/bin:$PATH make -C "$pkg_dir/linux" \
        ARCH=riscv \
        CROSS_COMPILE="$cross" \
        -j"$jobs" Image

    linux_image="$out_dir/Image_p3_${harts}hart"
    cp "$pkg_dir/linux/arch/riscv/boot/Image" "$linux_image"
else
    echo "[2/5] Rebuild skipped by P3_64CORE_USE_PREBUILT=1"
fi

echo "[3/5] Generating P3 ${harts}-hart DTB"
dts="$out_dir/p3_opensbi_${harts}hart.dts"
dtb="$out_dir/p3_opensbi_${harts}hart.dtb"
python3 "$repo_dir/scripts/p3_generate_opensbi_dts.py" \
    --harts "$harts" \
    --bootargs "$bootargs" \
    --out "$dts"
dtc -I dts -O dtb -o "$dtb" "$dts"
dtc -I dtb -O dts "$dtb" > "$out_dir/p3_opensbi_${harts}hart.roundtrip.dts"
grep -q "cpu@$((harts - 1))" "$out_dir/p3_opensbi_${harts}hart.roundtrip.dts"
grep -q "riscv,ndev = <0x02>" "$out_dir/p3_opensbi_${harts}hart.roundtrip.dts"

echo "[4/5] Selecting initramfs"
initrd="${P3_64CORE_INITRD:-$pkg_dir/artifacts/rootfs_exp_min.cpio.gz}"
require_file "$initrd"

echo "[5/5] Creating SD bundle image"
sd_img="$out_dir/p3_opensbi_linux_${harts}hart.img"
python3 "$repo_dir/scripts/p3_make_opensbi_bundle_image.py" \
    --fw "$fw_bin" \
    --image "$linux_image" \
    --dtb "$dtb" \
    --initrd "$initrd" \
    --out "$sd_img" \
    --fw-addr "$fw_addr" \
    --image-addr "$image_addr" \
    --dtb-addr "$dtb_addr" \
    --initrd-addr "$initrd_addr"

sha256sum "$fw_elf" "$fw_bin" "$linux_image" "$dtb" "$initrd" "$sd_img" \
    > "$out_dir/p3_opensbi_linux_${harts}hart.sha256"

echo "P3 64-core OpenSBI/Linux image outputs:"
echo "  fw_elf=$fw_elf"
echo "  fw_bin=$fw_bin"
echo "  linux_image=$linux_image"
echo "  dts=$dts"
echo "  dtb=$dtb"
echo "  initrd=$initrd"
echo "  sd_img=$sd_img"
echo "  sha256=$out_dir/p3_opensbi_linux_${harts}hart.sha256"
