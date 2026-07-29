#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

linux_version="6.12.98"
linux_archive_sha256="a62b6a2d207ff72510e5f47156b7078e1e71797357412411b8e4fff97fc8f4c7"
linux_archive="${P3_LINUX612_ARCHIVE:-$repo_dir/build/p3_linux612_sources/linux-${linux_version}.tar.xz}"
linux_url="${P3_LINUX612_URL:-https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${linux_version}.tar.xz}"
work_dir="${P3_LINUX612_WORK_DIR:-$repo_dir/build/p3_linux612_work}"
linux_dir="$work_dir/linux-${linux_version}"
out_dir="${P3_LINUX612_OUT_DIR:-$repo_dir/build/huaprop3/opensbi1_build66_linux612}"
config_fragment="${P3_LINUX612_CONFIG:-$repo_dir/scripts/p3_linux612_build66.config}"
profile="${P3_LINUX612_PROFILE:-minimal}"
jobs="${JOBS:-$(nproc)}"
export KBUILD_BUILD_TIMESTAMP="${KBUILD_BUILD_TIMESTAMP:-1970-01-01 00:00:00 +0000}"
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-p3}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-openpiton}"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"

fw="${P3_LINUX612_OPENSBI_FW:-$repo_dir/build/huaprop3/opensbi1_build66/fw_jump_p3_64core_noreloc.bin}"
fw_sha256="f6ef8f610c992edd8458c0a8b0848e48604f0f91a654381235ebacef84e11c76"
initrd="${P3_LINUX612_INITRD:-$repo_dir/build/huaprop3/opensbi64/p3_rootfs_64hart_xsbench_v2.cpio.gz}"
initrd_sha256="${P3_LINUX612_INITRD_SHA256:-60aaf85d266a77cce0c2cf59a22221bcc321c2f15fd36ce242a092e0b516f142}"
pdi="$repo_dir/huaprop3_build66_baseline/debug_build/p3_top_build66_normal_spi_sd_boot.pdi"
pdi_sha256="ee30fe4d052c763c9fc2fa72bf71cc8363173ad210ea8fb106533ac3081dd62d"
ltx="$repo_dir/huaprop3_build66_baseline/debug_build/p3_top_build66_normal_spi_sd_boot.ltx"
ltx_sha256="7b9c348e4d2695dfd90f700aabc8e4eee66288d07dd7a4c81ea636e33d2aeaaf"
piton_sd_driver="$repo_dir/scripts/p3_linux612_piton_sd.c"
piton_sd_integrator="$repo_dir/scripts/p3_integrate_linux612_piton_sd.py"

fw_addr="0x80000000"
image_addr="0x80200000"
dtb_addr="0x81600000"
initrd_addr="0x81700000"
bootargs="earlycon=uart8250,mmio,0xfff0c2c000 console=ttyS0,115200n8 rdinit=/init loglevel=8 keep_bootcon initcall_debug"

case "$profile" in
    minimal)
        profile_suffix=""
        ;;
    mpi)
        profile_suffix="_mpi"
        ;;
    *)
        echo "ERROR: unsupported P3_LINUX612_PROFILE: $profile" >&2
        exit 1
        ;;
esac

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: missing required command: $1" >&2
        exit 1
    fi
}

require_file() {
    if [[ ! -f "$1" ]]; then
        echo "ERROR: missing required file: $1" >&2
        exit 1
    fi
}

verify_sha256() {
    local path="$1"
    local expected="$2"
    local actual
    require_file "$path"
    actual="$(sha256sum "$path" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        echo "ERROR: SHA-256 mismatch: $path" >&2
        echo "  expected=$expected" >&2
        echo "  actual=$actual" >&2
        exit 1
    fi
}

for tool in awk cpio curl dtc fdtget gzip make python3 sha256sum sfdisk tar xz; do
    require_cmd "$tool"
done
require_file "$config_fragment"
if [[ "$profile" == "mpi" ]]; then
    require_file "$piton_sd_driver"
    require_file "$piton_sd_integrator"
fi
verify_sha256 "$fw" "$fw_sha256"
verify_sha256 "$initrd" "$initrd_sha256"
verify_sha256 "$pdi" "$pdi_sha256"
verify_sha256 "$ltx" "$ltx_sha256"

if [[ -n "${CROSS_COMPILE:-}" ]]; then
    cross="$CROSS_COMPILE"
elif command -v riscv64-linux-gnu-gcc >/dev/null 2>&1; then
    cross="riscv64-linux-gnu-"
else
    echo "ERROR: missing Linux-targeting RISC-V cross compiler" >&2
    echo "  install gcc-riscv64-linux-gnu; the bare-metal linker cannot build the Linux VDSO" >&2
    exit 1
fi
require_cmd "${cross}gcc"
require_cmd "${cross}objdump"

scan_custom_csr_701_writes() {
    local label="$1"
    shift
    if "$@" | awk '
        /csr(w|wi|s|c)[[:space:]]+0x701/ {
            print
            found = 1
        }
        END {
            exit found ? 0 : 1
        }
    '; then
        echo "ERROR: $label contains a write to custom CSR 0x701" >&2
        exit 1
    fi
}

scan_custom_csr_701_writes \
    "OpenSBI firmware" \
    "${cross}objdump" -D -b binary -m riscv:rv64 "$fw"

if [[ ! -f "$linux_archive" ]]; then
    mkdir -p "$(dirname "$linux_archive")"
    echo "Downloading Linux ${linux_version} from kernel.org"
    curl --fail --location --retry 3 \
        --output "$linux_archive.part" "$linux_url"
    mv "$linux_archive.part" "$linux_archive"
fi
verify_sha256 "$linux_archive" "$linux_archive_sha256"

mkdir -p "$work_dir" "$out_dir"
if [[ ! -f "$linux_dir/Makefile" ]]; then
    tar -xJf "$linux_archive" -C "$work_dir"
fi
actual_version="$(make -s -C "$linux_dir" kernelversion)"
if [[ "$actual_version" != "$linux_version" ]]; then
    echo "ERROR: extracted Linux version mismatch: $actual_version" >&2
    exit 1
fi

if [[ "$profile" == "mpi" ]]; then
    python3 "$piton_sd_integrator" \
        --linux-dir "$linux_dir" \
        --driver "$piton_sd_driver"
fi

echo "[1/5] Configuring upstream Linux ${linux_version} for P3 Build 66 (${profile})"
make -C "$linux_dir" ARCH=riscv CROSS_COMPILE="$cross" mrproper
make -C "$linux_dir" ARCH=riscv CROSS_COMPILE="$cross" \
    KCONFIG_ALLCONFIG="$config_fragment" allnoconfig
make -C "$linux_dir" ARCH=riscv CROSS_COMPILE="$cross" olddefconfig

required_config=(
    "CONFIG_SMP=y"
    "CONFIG_NR_CPUS=64"
    "CONFIG_NONPORTABLE=y"
    "CONFIG_EXPERT=y"
    "CONFIG_RISCV_SBI=y"
    "CONFIG_FPU=y"
    "CONFIG_BLK_DEV_INITRD=y"
    "CONFIG_RD_GZIP=y"
    "CONFIG_DEVTMPFS=y"
    "CONFIG_SERIAL_8250=y"
    "CONFIG_SERIAL_8250_CONSOLE=y"
    "CONFIG_SERIAL_OF_PLATFORM=y"
    "CONFIG_RISCV_TIMER=y"
    "CONFIG_SIFIVE_PLIC=y"
)
if [[ "$profile" == "mpi" ]]; then
    required_config+=(
        "CONFIG_BINFMT_SCRIPT=y"
        "CONFIG_SYSVIPC=y"
        "CONFIG_POSIX_MQUEUE=y"
        "CONFIG_CROSS_MEMORY_ATTACH=y"
        "CONFIG_SHMEM=y"
        "CONFIG_AIO=y"
        "CONFIG_ADVISE_SYSCALLS=y"
        "CONFIG_MEMBARRIER=y"
        "CONFIG_RSEQ=y"
        "CONFIG_NET=y"
        "CONFIG_PACKET=y"
        "CONFIG_UNIX=y"
        "CONFIG_INET=y"
        "CONFIG_BLOCK=y"
        "CONFIG_BLK_DEV=y"
        "CONFIG_OPENPITON_ARIANE_SD=y"
        "CONFIG_MSDOS_PARTITION=y"
        "CONFIG_EFI_PARTITION=y"
        "CONFIG_EXT4_FS=y"
    )
fi
for setting in "${required_config[@]}"; do
    if ! grep -Fxq "$setting" "$linux_dir/.config"; then
        echo "ERROR: required Linux config setting missing: $setting" >&2
        exit 1
    fi
done
forbidden_config=(
    CONFIG_RISCV_SBI_V01 CONFIG_RISCV_BOOT_SPINWAIT CONFIG_COMPAT CONFIG_CPU_IDLE \
    CONFIG_RISCV_SBI_CPUIDLE CONFIG_SUSPEND CONFIG_PM CONFIG_EFI_STUB \
    CONFIG_EFI CONFIG_ACPI CONFIG_BLK_DEV_LOOP CONFIG_MTD \
    CONFIG_MEDIA_SUPPORT CONFIG_VIRTIO_MENU \
    CONFIG_RISCV_ISA_SVNAPOT CONFIG_RISCV_ISA_SVPBMT CONFIG_RISCV_ISA_ZAWRS \
    CONFIG_RISCV_ISA_ZBA CONFIG_RISCV_ISA_ZBB CONFIG_RISCV_ISA_ZBC \
    CONFIG_RISCV_ISA_ZICBOM CONFIG_RISCV_ISA_ZICBOZ CONFIG_RISCV_ISA_V \
    CONFIG_RISCV_ISA_VENDOR_EXT CONFIG_RISCV_ISA_VENDOR_EXT_ANDES
)
if [[ "$profile" == "minimal" ]]; then
    forbidden_config+=(CONFIG_BLOCK CONFIG_NET CONFIG_SYSVIPC)
fi
for forbidden in "${forbidden_config[@]}"; do
    if grep -Eq "^${forbidden}=" "$linux_dir/.config"; then
        echo "ERROR: forbidden Linux config setting is enabled: $forbidden" >&2
        exit 1
    fi
done
config_out="$out_dir/linux-${linux_version}-build66${profile_suffix}.config"
cp "$linux_dir/.config" "$config_out"

echo "[2/5] Building Linux Image"
make -C "$linux_dir" ARCH=riscv CROSS_COMPILE="$cross" -j"$jobs" Image
linux_image="$out_dir/Image_linux-${linux_version}_p3_build66${profile_suffix}"
cp "$linux_dir/arch/riscv/boot/Image" "$linux_image"
require_file "$linux_image"

scan_custom_csr_701_writes \
    "Linux vmlinux" \
    "${cross}objdump" -d "$linux_dir/vmlinux"

echo "[3/5] Generating and validating the one-hart P3 DTB"
dts="$out_dir/p3_opensbi_1hart_linux-${linux_version}${profile_suffix}.dts"
dtb="$out_dir/p3_opensbi_1hart_linux-${linux_version}${profile_suffix}.dtb"
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

echo "[4/5] Packing the Build 66 fixed-copy-window image"
sd_img="$out_dir/p3_opensbi_linux_1hart_build66_linux-${linux_version}${profile_suffix}_flat.img"
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

config_sha256="$(sha256sum "$config_out" | awk '{print $1}')"
{
    echo "linux_version=$linux_version"
    echo "linux_profile=$profile"
    echo "linux_source_sha256=$linux_archive_sha256"
    echo "linux_config_sha256=$config_sha256"
    echo "opensbi_mode=standard_hsm_fixed_fdt_noreloc"
    echo "build66_pdi_sha256=$pdi_sha256"
    echo "build66_ltx_sha256=$ltx_sha256"
    if [[ "$profile" == "mpi" ]]; then
        echo "system_smoke=/usr/bin/p3_mpi_system_smoke"
        echo "piton_sd_driver_sha256=$(sha256sum "$piton_sd_driver" | awk '{print $1}')"
        echo "piton_sd_sdk_origin_patch_sha256=24578b764d09ae36af6312caa8ddb7bf2fdd2264b9f6fed9d01b4010e8ceb3aa"
    fi
    echo "xsbench_command=/root/XSBench -t 1 -s small -p 1000 -l 1"
} >> "$sd_img.manifest"

echo "[5/5] Creating deterministic compressed transport artifact"
gzip -9n -c "$sd_img" > "$sd_img.gz"
sha_file="$out_dir/p3_opensbi_linux_1hart_build66_linux-${linux_version}${profile_suffix}.sha256"
sha256sum \
    "$linux_archive" \
    "$fw" \
    "$linux_image" \
    "$config_out" \
    "$dtb" \
    "$initrd" \
    "$sd_img" \
    "$sd_img.gz" \
    "$sd_img.manifest" > "$sha_file"
if [[ "$profile" == "mpi" ]]; then
    sha256sum \
        "$piton_sd_driver" \
        "$piton_sd_integrator" \
        "$repo_dir/scripts/p3_linux612_mpi_system_smoke.c" \
        "$repo_dir/scripts/p3_linux612_mpi_init.sh" >> "$sha_file"
fi

echo "Build 66 one-hart OpenSBI/Linux ${linux_version} outputs:"
echo "  linux_image=$linux_image"
echo "  dtb=$dtb"
echo "  initrd=$initrd"
echo "  sd_img=$sd_img"
echo "  compressed=$sd_img.gz"
echo "  sha256=$sha_file"
