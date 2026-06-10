#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export P3_BUILD67_VARIANT="${P3_BUILD67_VARIANT:-low_noise_console}"
export P3_BUILD67_BOOTARGS="${P3_BUILD67_BOOTARGS:-earlycon=uart8250,mmio,0xfff0c2c000 console=ttyS0,115200n8 rdinit=/bin/sh init=/bin/sh keep_bootcon loglevel=8 ignore_loglevel initcall_debug}"

exec "$repo_dir/scripts/p3_make_build67_clean_delay_image.sh"
