#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${P3_BUILD66_OPENSBI_OUT_DIR:-$repo_dir/build/huaprop3/opensbi1_build66}"
work_dir="${P3_BUILD66_OPENSBI_WORK_DIR:-$repo_dir/build/p3_1hart_build66}"
linux_base_archive="${P3_64CORE_LINUX_BASE_ARCHIVE:-$repo_dir/build/p3_64core/linux-6.6.tar.xz}"

fw_addr="${P3_BUILD66_OPENSBI_FW_ADDR:-0x80000000}"
image_addr="${P3_BUILD66_LINUX_IMAGE_ADDR:-0x80200000}"
dtb_addr="${P3_BUILD66_OPENSBI_DTB_ADDR:-0x81600000}"
initrd_addr="${P3_BUILD66_INITRD_ADDR:-0x81700000}"

if [[ "${P3_64CORE_USE_PREBUILT:-0}" == "1" ]]; then
    echo "ERROR: the Build 66 board candidate must rebuild OpenSBI/Linux; prebuilt mode is smoke-test only" >&2
    exit 1
fi

export P3_64CORE_HARTS=1
export P3_64CORE_WORK_DIR="$work_dir"
export P3_64CORE_OUT_DIR="$out_dir"
export P3_64CORE_LINUX_BASE_ARCHIVE="$linux_base_archive"
export P3_OPENSBI_FW_ADDR="$fw_addr"
export P3_LINUX_IMAGE_ADDR="$image_addr"
export P3_OPENSBI_DTB_ADDR="$dtb_addr"
export P3_INITRD_ADDR="$initrd_addr"

"$repo_dir/scripts/p3_prepare_64core_opensbi_image.sh"

fw_bin="$out_dir/fw_jump_p3_64core.bin"
linux_image="$out_dir/Image_p3_1hart"
dtb="$out_dir/p3_opensbi_1hart.dtb"
initrd="${P3_64CORE_INITRD:-$out_dir/p3_rootfs_64hart.cpio.gz}"
sd_img="$out_dir/p3_opensbi_linux_1hart_build66_flat.img"

python3 "$repo_dir/scripts/p3_make_build66_opensbi_flat_image.py" \
    --fw "$fw_bin" \
    --image "$linux_image" \
    --dtb "$dtb" \
    --initrd "$initrd" \
    --out "$sd_img" \
    --device-map "${P3_DEVICE_MAP:-$repo_dir/piton/design/xilinx/huaprop3/devices_ariane.xml}" \
    --fw-addr "$fw_addr" \
    --image-addr "$image_addr" \
    --dtb-addr "$dtb_addr" \
    --initrd-addr "$initrd_addr"

sha256sum "$fw_bin" "$linux_image" "$dtb" "$initrd" "$sd_img" \
    "$sd_img.manifest" > "$out_dir/p3_opensbi_linux_1hart_build66_flat.sha256"

echo "Build 66 one-hart OpenSBI/Linux image outputs:"
echo "  fw_bin=$fw_bin"
echo "  linux_image=$linux_image"
echo "  dtb=$dtb"
echo "  initrd=$initrd"
echo "  sd_img=$sd_img"
echo "  sha256=$out_dir/p3_opensbi_linux_1hart_build66_flat.sha256"
