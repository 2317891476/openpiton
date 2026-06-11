#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export P3_BUILD67_TRACE_VARIANT="${P3_BUILD67_TRACE_VARIANT:-irq_chain_trace}"
export P3_BUILD67_OUT_IMG="${P3_BUILD67_OUT_IMG:-$repo_dir/build/huaprop3/sd_images/huaprop3_linux_xsbench_2x1_irq_chain_trace.img}"

exec bash "$repo_dir/scripts/p3_make_build67_sbi_trace_image.sh"
