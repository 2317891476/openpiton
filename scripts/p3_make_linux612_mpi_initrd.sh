#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base_initrd="${P3_LINUX612_BASE_INITRD:-$repo_dir/build/huaprop3/opensbi64/p3_rootfs_64hart_xsbench_v2.cpio.gz}"
base_sha256="60aaf85d266a77cce0c2cf59a22221bcc321c2f15fd36ce242a092e0b516f142"
out="${1:-$repo_dir/build/huaprop3/opensbi1_build66_linux612_mpi/p3_linux612_mpi_rootfs.cpio.gz}"
out_dir="$(dirname "$out")"
root="$out_dir/initramfs-root"
cross="${CROSS_COMPILE:-riscv64-linux-gnu-}"
smoke_source="$repo_dir/scripts/p3_linux612_mpi_system_smoke.c"
init_source="${P3_LINUX612_INIT_SOURCE:-$repo_dir/scripts/p3_linux612_mpi_init.sh}"
smoke_binary="$out_dir/p3_mpi_system_smoke"
xsbench_binary="${P3_LINUX612_XSBENCH_BINARY:-}"
xsbench_sha256="${P3_LINUX612_XSBENCH_SHA256:-}"

for tool in awk cpio find gzip install sha256sum sort "${cross}gcc"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: missing required command: $tool" >&2
        exit 1
    fi
done
for path in "$base_initrd" "$smoke_source" "$init_source"; do
    if [[ ! -f "$path" ]]; then
        echo "ERROR: missing required file: $path" >&2
        exit 1
    fi
done
if [[ -n "$xsbench_binary" ]]; then
    if [[ -z "$xsbench_sha256" ]]; then
        echo "ERROR: P3_LINUX612_XSBENCH_SHA256 is required with P3_LINUX612_XSBENCH_BINARY" >&2
        exit 1
    fi
    if [[ ! -f "$xsbench_binary" ]]; then
        echo "ERROR: missing marked XSBench binary: $xsbench_binary" >&2
        exit 1
    fi
    actual_xsbench_sha256="$(sha256sum "$xsbench_binary" | awk '{print $1}')"
    if [[ "$actual_xsbench_sha256" != "$xsbench_sha256" ]]; then
        echo "ERROR: marked XSBench SHA-256 mismatch" >&2
        echo "  expected=$xsbench_sha256" >&2
        echo "  actual=$actual_xsbench_sha256" >&2
        exit 1
    fi
elif [[ -n "$xsbench_sha256" ]]; then
    echo "ERROR: P3_LINUX612_XSBENCH_BINARY is required with P3_LINUX612_XSBENCH_SHA256" >&2
    exit 1
fi
actual_base_sha256="$(sha256sum "$base_initrd" | awk '{print $1}')"
if [[ "$actual_base_sha256" != "$base_sha256" ]]; then
    echo "ERROR: base initramfs SHA-256 mismatch" >&2
    exit 1
fi

mkdir -p "$out_dir" "$root"
find "$root" -mindepth 1 -delete
(
    cd "$root"
    gzip -dc "$base_initrd" | cpio -idm --quiet
)

"${cross}gcc" -O2 -static -pthread \
    -Wall -Wextra -Werror \
    -o "$smoke_binary" "$smoke_source"
install -m 0755 "$smoke_binary" "$root/usr/bin/p3_mpi_system_smoke"
install -m 0755 "$init_source" "$root/init"
if [[ -n "$xsbench_binary" ]]; then
    install -m 0755 "$xsbench_binary" "$root/root/XSBench_marked"
fi
find "$root" -exec touch -h -d "@0" {} +

(
    cd "$root"
    find . -print0 |
        LC_ALL=C sort -z |
        cpio --null -o --format=newc --owner=0:0 --reproducible --quiet |
        gzip -9n
) > "$out"

gzip -t "$out"
sha256sum "$out"
