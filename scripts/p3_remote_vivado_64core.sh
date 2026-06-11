#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

jump_host="${P3_OFFLINE_JUMP:-23178@100.70.176.125}"
build_host="${P3_OFFLINE_UBUNTU:-cs@202.197.4.150}"
remote_root="${P3_OFFLINE_ROOT:-/home/cs/openpiton}"
vivado_bin="${P3_OFFLINE_VIVADO:-/media/d1/Xilinx/Vivado/2024.2/bin/vivado}"
remote_archive="${P3_REMOTE_ARCHIVE:-/tmp/openpiton-p3-64core-src.tar.gz}"
remote_script="${P3_REMOTE_SCRIPT:-scripts/p3_build68_8x8_opensbi_linux.tcl}"
core_archive="${P3_64CORE_ARCHIVE:-$repo_dir/riscv64-linux-64core-src-20260610.tar.gz}"
jobs="${JOBS:-8}"

archive="$repo_dir/build/p3_64core/openpiton-p3-64core-src.tar.gz"
mkdir -p "$(dirname "$archive")"

git -C "$repo_dir" archive --format=tar.gz --output="$archive" HEAD

if [[ ! -f "$core_archive" ]]; then
    echo "ERROR: missing 64core software archive: $core_archive" >&2
    exit 1
fi

ssh -J "$jump_host" "$build_host" "mkdir -p '$remote_root'"
scp -o ProxyJump="$jump_host" "$archive" "$build_host:$remote_archive"
scp -o ProxyJump="$jump_host" "$core_archive" "$build_host:$remote_root/riscv64-linux-64core-src-20260610.tar.gz"

ssh -J "$jump_host" "$build_host" \
    "set -e; mkdir -p '$remote_root'; tar -xzf '$remote_archive' -C '$remote_root'; cd '$remote_root'; '$vivado_bin' -mode batch -source '$remote_script' -tclargs -jobs '$jobs'"
