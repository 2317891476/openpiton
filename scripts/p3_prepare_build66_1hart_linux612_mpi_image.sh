#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${P3_LINUX612_MPI_OUT_DIR:-$repo_dir/build/huaprop3/opensbi1_build66_linux612_mpi}"
initrd="$out_dir/p3_linux612_mpi_rootfs.cpio.gz"

mkdir -p "$out_dir"
"$repo_dir/scripts/p3_make_linux612_mpi_initrd.sh" "$initrd"
initrd_sha256="$(sha256sum "$initrd" | awk '{print $1}')"

P3_LINUX612_PROFILE=mpi \
P3_LINUX612_CONFIG="$repo_dir/scripts/p3_linux612_build66_mpi.config" \
P3_LINUX612_OUT_DIR="$out_dir" \
P3_LINUX612_INITRD="$initrd" \
P3_LINUX612_INITRD_SHA256="$initrd_sha256" \
exec "$repo_dir/scripts/p3_prepare_build66_1hart_linux612_image.sh"
