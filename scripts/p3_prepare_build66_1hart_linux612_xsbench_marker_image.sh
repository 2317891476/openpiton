#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${P3_XSBENCH_MARKER_OUT_DIR:-$repo_dir/build/huaprop3/opensbi1_build66_linux612_xsbench_marker}"

linux_image="${P3_XSBENCH_MARKER_LINUX_IMAGE:-$repo_dir/build/huaprop3/opensbi1_build66_linux612_mpi/Image_linux-6.12.98_p3_build66_mpi}"
linux_sha256="fbbf1cc1c1ec35d7e90584ed9c078045678a62282ec7c07f60c4f9d35857eb8e"
linux_config="$repo_dir/build/huaprop3/opensbi1_build66_linux612_mpi/linux-6.12.98-build66_mpi.config"
linux_config_sha256="3951348630430a2cbd0ff4f427aefdf9607bf81801405c3b295c6ba89c03af1e"
fw="$repo_dir/build/huaprop3/opensbi1_build66/fw_jump_p3_64core_noreloc.bin"
fw_sha256="f6ef8f610c992edd8458c0a8b0848e48604f0f91a654381235ebacef84e11c76"
pdi="$repo_dir/huaprop3_build66_baseline/debug_build/p3_top_build66_normal_spi_sd_boot.pdi"
pdi_sha256="ee30fe4d052c763c9fc2fa72bf71cc8363173ad210ea8fb106533ac3081dd62d"
ltx="$repo_dir/huaprop3_build66_baseline/debug_build/p3_top_build66_normal_spi_sd_boot.ltx"
ltx_sha256="7b9c348e4d2695dfd90f700aabc8e4eee66288d07dd7a4c81ea636e33d2aeaaf"
marked_xsbench="$out_dir/XSBench_marked"
marked_xsbench_sha256="cc8daa214860651e2da283185ae843ba64baaf56892859b058fbc049450fbcb6"
init_source="$repo_dir/scripts/p3_linux612_xsbench_marker_init.sh"
initrd="$out_dir/p3_linux612_xsbench_marker_rootfs.cpio.gz"

fw_addr="0x80000000"
image_addr="0x80200000"
dtb_addr="0x81600000"
initrd_addr="0x81700000"
bootargs="earlycon=uart8250,mmio,0xfff0c2c000 console=ttyS0,115200n8 rdinit=/init loglevel=8 keep_bootcon initcall_debug"

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: missing required command: $1" >&2
        exit 1
    fi
}

verify_sha256() {
    local path="$1"
    local expected="$2"
    local actual

    if [[ ! -f "$path" ]]; then
        echo "ERROR: missing pinned input: $path" >&2
        exit 1
    fi
    actual="$(sha256sum "$path" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        echo "ERROR: SHA-256 mismatch: $path" >&2
        echo "  expected=$expected" >&2
        echo "  actual=$actual" >&2
        exit 1
    fi
}

for tool in awk dtc fdtget gzip python3 sha256sum sfdisk; do
    require_cmd "$tool"
done
for path in \
    "$repo_dir/scripts/p3_build_xsbench_stage_markers.sh" \
    "$repo_dir/scripts/p3_make_linux612_mpi_initrd.sh" \
    "$repo_dir/scripts/p3_generate_opensbi_dts.py" \
    "$repo_dir/scripts/p3_validate_opensbi_dtb.py" \
    "$repo_dir/scripts/p3_make_build66_opensbi_flat_image.py" \
    "$init_source"; do
    if [[ ! -f "$path" ]]; then
        echo "ERROR: missing required build input: $path" >&2
        exit 1
    fi
done
verify_sha256 "$linux_image" "$linux_sha256"
verify_sha256 "$linux_config" "$linux_config_sha256"
verify_sha256 "$fw" "$fw_sha256"
verify_sha256 "$pdi" "$pdi_sha256"
verify_sha256 "$ltx" "$ltx_sha256"

mkdir -p "$out_dir"

echo "[1/5] Rebuilding the source-pinned XSBench stage-marker executable"
P3_XSBENCH_MARKER_OUT_DIR="$out_dir" \
    "$repo_dir/scripts/p3_build_xsbench_stage_markers.sh"
verify_sha256 "$marked_xsbench" "$marked_xsbench_sha256"

echo "[2/5] Building the marker initramfs"
P3_LINUX612_INIT_SOURCE="$init_source" \
P3_LINUX612_XSBENCH_BINARY="$marked_xsbench" \
P3_LINUX612_XSBENCH_SHA256="$marked_xsbench_sha256" \
    "$repo_dir/scripts/p3_make_linux612_mpi_initrd.sh" "$initrd"
initrd_sha256="$(sha256sum "$initrd" | awk '{print $1}')"

echo "[3/5] Generating and validating the one-hart DTB"
dts="$out_dir/p3_opensbi_1hart_linux-6.12.98_xsbench_marker.dts"
dtb="$out_dir/p3_opensbi_1hart_linux-6.12.98_xsbench_marker.dtb"
python3 "$repo_dir/scripts/p3_generate_opensbi_dts.py" \
    --harts 1 \
    --bootargs "$bootargs" \
    --initrd "$initrd" \
    --initrd-addr "$initrd_addr" \
    --out "$dts"
dtc -I dts -O dtb -o "$dtb" "$dts"
python3 "$repo_dir/scripts/p3_validate_opensbi_dtb.py" \
    --dtb "$dtb" \
    --harts 1 \
    --bootargs "$bootargs" \
    --initrd "$initrd" \
    --initrd-addr "$initrd_addr"

echo "[4/5] Packing and readback-checking the fixed Build 66 copy window"
sd_img="$out_dir/p3_opensbi_linux_1hart_build66_linux-6.12.98_xsbench_marker_flat.img"
python3 "$repo_dir/scripts/p3_make_build66_opensbi_flat_image.py" \
    --fw "$fw" \
    --image "$linux_image" \
    --dtb "$dtb" \
    --initrd "$initrd" \
    --out "$sd_img" \
    --fw-addr "$fw_addr" \
    --image-addr "$image_addr" \
    --dtb-addr "$dtb_addr" \
    --initrd-addr "$initrd_addr"

{
    echo "purpose=single_hart_xsbench_direct_write_stage_localization"
    echo "linux_version=6.12.98"
    echo "linux_profile=mpi_reused_board_validated"
    echo "linux_image_sha256=$linux_sha256"
    echo "linux_config_sha256=$linux_config_sha256"
    echo "opensbi_mode=standard_hsm_fixed_fdt_noreloc"
    echo "opensbi_sha256=$fw_sha256"
    echo "build66_pdi_sha256=$pdi_sha256"
    echo "build66_ltx_sha256=$ltx_sha256"
    echo "xsbench_source_commit=ba08e5221af6106252b866e50ea123c69d31a4e2"
    echo "xsbench_reference_sha256=1e896862da3294129c02bcbd8dfbd89fe70e093ef4c03f430882b6fede110930"
    echo "xsbench_marked_sha256=$marked_xsbench_sha256"
    echo "xsbench_command=/root/XSBench_marked -t 1 -s small -p 1000 -l 1"
    echo "initramfs_sha256=$initrd_sha256"
} >> "$sd_img.manifest"

echo "[5/5] Creating deterministic compressed transport artifact"
gzip -9n -c "$sd_img" > "$sd_img.gz"
gzip -t "$sd_img.gz"
raw_sha256="$(sha256sum "$sd_img" | awk '{print $1}')"
compressed_sha256="$(sha256sum "$sd_img.gz" | awk '{print $1}')"
decompressed_sha256="$(gzip -dc "$sd_img.gz" | sha256sum | awk '{print $1}')"
if [[ "$decompressed_sha256" != "$raw_sha256" ]]; then
    echo "ERROR: compressed image decompression hash mismatch" >&2
    exit 1
fi

sha_file="$out_dir/p3_opensbi_linux_1hart_build66_linux-6.12.98_xsbench_marker.sha256"
sha256sum \
    "$linux_image" \
    "$linux_config" \
    "$fw" \
    "$marked_xsbench" \
    "$init_source" \
    "$initrd" \
    "$dtb" \
    "$sd_img" \
    "$sd_img.gz" \
    "$sd_img.manifest" > "$sha_file"

echo "Build 66 one-hart XSBench stage-marker image passed:"
echo "  marked_xsbench=$marked_xsbench"
echo "  initrd=$initrd"
echo "  dtb=$dtb"
echo "  sd_img=$sd_img"
echo "  raw_sha256=$raw_sha256"
echo "  compressed=$sd_img.gz"
echo "  compressed_sha256=$compressed_sha256"
echo "  sha256=$sha_file"
