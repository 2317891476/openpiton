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
pack_dir="$repo_dir/build/p3_64core/archive_root"
mkdir -p "$(dirname "$archive")"

rm -rf "$pack_dir"
mkdir -p "$pack_dir"
git -C "$repo_dir" archive --format=tar HEAD | tar -x -C "$pack_dir"

while read -r submodule_path; do
    if [[ -d "$repo_dir/$submodule_path/.git" || -f "$repo_dir/$submodule_path/.git" ]]; then
        mkdir -p "$pack_dir/$submodule_path"
        git -C "$repo_dir/$submodule_path" archive --format=tar HEAD | tar -x -C "$pack_dir/$submodule_path"
    fi
done < <(git -C "$repo_dir" config --file .gitmodules --get-regexp path | awk '{print $2}')

tar -czf "$archive" -C "$pack_dir" .

if [[ ! -f "$core_archive" ]]; then
    echo "ERROR: missing 64core software archive: $core_archive" >&2
    exit 1
fi

ssh -J "$jump_host" "$build_host" "mkdir -p '$remote_root'"
scp -o ProxyJump="$jump_host" "$archive" "$build_host:$remote_archive"
scp -o ProxyJump="$jump_host" "$core_archive" "$build_host:$remote_root/riscv64-linux-64core-src-20260610.tar.gz"

ssh -J "$jump_host" "$build_host" \
    "set -e; mkdir -p '$remote_root'; tar -xzf '$remote_archive' -C '$remote_root'; cd '$remote_root'; '$vivado_bin' -mode batch -source '$remote_script' -tclargs -jobs '$jobs'"
