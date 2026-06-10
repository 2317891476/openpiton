#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
variant="${P3_BUILD67_VARIANT:-clean_delay}"
base_img="${P3_BUILD67_BASE_IMG:-$repo_dir/build/huaprop3/sd_images/huaprop3_linux_xsbench_ext2.img}"
out_img="${P3_BUILD67_OUT_IMG:-$repo_dir/build/huaprop3/sd_images/huaprop3_linux_xsbench_2x1_${variant}.img}"
source_bbl_dir="${P3_BUILD67_SOURCE_BBL_DIR:-$repo_dir/build/huaprop3/ariane-sdk/build-bbl-build67-keep_divisor}"
source_pk="${P3_RISCV_PK_SRC:-$repo_dir/build/a7203x/ariane-sdk/riscv-pk}"
build_dir="$repo_dir/build/huaprop3"
work_root="$build_dir/ariane-sdk"
variant_dir="$work_root/build-bbl-build67-${variant}"
bootargs="${P3_BUILD67_BOOTARGS:-earlycon=uart8250,mmio,0xfff0c2c000 console=ttyS0,115200n8 rdinit=/bin/sh init=/bin/sh}"

require_file() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        echo "ERROR: missing required file: $path" >&2
        exit 1
    fi
}

require_dir() {
    local path="$1"
    if [[ ! -d "$path" ]]; then
        echo "ERROR: missing required directory: $path" >&2
        exit 1
    fi
}

make_dts() {
    local out_dts="$1"

    awk -v bootargs="$bootargs" '
        /^[[:space:]]*chosen[[:space:]]*\{/ { in_chosen = 1 }
        in_chosen && /^[[:space:]]*bootargs[[:space:]]*=/ { next }
        in_chosen && /^[[:space:]]*\};/ {
            print "        bootargs = \"" bootargs "\";"
            in_chosen = 0
        }
        /^[[:space:]]*riscv,ndev[[:space:]]*=/ {
            print "            riscv,ndev = <2>;"
            next
        }
        { print }
    ' "$source_bbl_dir/huaprop3.dts" > "$out_dts"
}

dtb_to_header() {
    local dtb="$1"
    local header="$2"

    od -An -tx1 -v "$dtb" \
        | sed 's/^ *//; s/  */, 0x/g; s/^/  0x/; s/$/,/' \
        > "$header"
}

patch_bbl_sources() {
    cp "$source_pk/bbl/bbl.c" "$variant_dir/bbl.c"

    perl - "$variant_dir/bbl.c" <<'PERL'
use strict;
use warnings;

sub replace_once {
    my ($path, $old, $new) = @_;
    open my $in, '<', $path or die "ERROR: open $path: $!\n";
    local $/;
    my $text = <$in>;
    close $in or die "ERROR: close $path: $!\n";

    my $count = () = $text =~ /\Q$old\E/g;
    die "ERROR: expected one match in $path, found $count\n" unless $count == 1;

    $text =~ s/\Q$old\E/$new/;
    open my $out, '>', $path or die "ERROR: write $path: $!\n";
    print {$out} $text;
    close $out or die "ERROR: close $path: $!\n";
}

my ($bbl_path) = @ARGV;

replace_once($bbl_path, <<'OLD', <<'NEW');
  long hartid = read_csr(mhartid);
  if ((1 << hartid) & disabled_hart_mask) {
    while (1) {
      __asm__ volatile("wfi");
#ifdef __riscv_div
      __asm__ volatile("div x0, x0, x0");
#endif
    }
  }

#ifdef BBL_BOOT_MACHINE
OLD
  long hartid = read_csr(mhartid);
  if ((1 << hartid) & disabled_hart_mask) {
    while (1) {
      __asm__ volatile("wfi");
#ifdef __riscv_div
      __asm__ volatile("div x0, x0, x0");
#endif
    }
  }

  if (hartid != 0) {
    for (volatile uintptr_t delay = 0; delay < 2000000; delay++) {
      __asm__ volatile("nop");
    }
  }

#ifdef BBL_BOOT_MACHINE
NEW
PERL
}

require_file "$base_img"
require_file "$source_pk/bbl/bbl.c"
require_dir "$source_bbl_dir"
require_file "$source_bbl_dir/huaprop3.dts"
require_file "$source_bbl_dir/huaprop3.dtb"
require_file "$source_bbl_dir/embedded_dtb.h"

if ! dtc -I dtb "$source_bbl_dir/huaprop3.dtb" -O dts 2>/dev/null | grep -q 'cpu@1'; then
    echo "ERROR: source DTB does not contain cpu@1: $source_bbl_dir/huaprop3.dtb" >&2
    exit 1
fi

rm -rf "$variant_dir"
cp -a "$source_bbl_dir" "$variant_dir"

build_dts="$build_dir/huaprop3_2x1_${variant}.dts"
build_dtb="$build_dir/huaprop3_2x1_${variant}.dtb"
bbl_bin="$build_dir/bbl_build67_2x1_${variant}.bin"

make_dts "$build_dts"
grep -q 'riscv,ndev = <2>;' "$build_dts"
dtc -I dts "$build_dts" -O dtb -o "$build_dtb"
dtc -I dtb "$build_dtb" -O dts 2>/dev/null | grep -q 'cpu@1'
dtc -I dtb "$build_dtb" -O dts 2>/dev/null | \
    grep -q 'earlycon=uart8250,mmio,0xfff0c2c000 console=ttyS0,115200n8 rdinit=/bin/sh init=/bin/sh'

cp "$build_dts" "$variant_dir/huaprop3.dts"
cp "$build_dtb" "$variant_dir/huaprop3.dtb"
dtb_to_header "$build_dtb" "$variant_dir/embedded_dtb.h"
patch_bbl_sources

make -C "$variant_dir" clean
env CFLAGS="-fno-stack-protector -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0" make -C "$variant_dir"

riscv64-linux-gnu-objcopy \
    -S -O binary --change-addresses -0x80000000 \
    "$variant_dir/bbl" \
    "$bbl_bin"

if grep -a -q 'B67S' "$bbl_bin"; then
    echo "ERROR: $variant BBL unexpectedly contains B67S trace strings: $bbl_bin" >&2
    exit 1
fi

mkdir -p "$(dirname "$out_img")"
cp "$base_img" "$out_img"

part_info="$(sfdisk -d "$out_img" | sed -n 's/.*1 : start=[[:space:]]*\([0-9][0-9]*\), size=[[:space:]]*\([0-9][0-9]*\),.*/\1 \2/p' | head -n 1)"
if [[ -z "$part_info" ]]; then
    echo "ERROR: failed to locate partition 1 in $out_img" >&2
    exit 1
fi

read -r part_start part_size <<< "$part_info"
part_bytes=$((part_size * 512))
bbl_bytes="$(stat -c %s "$bbl_bin")"
if (( bbl_bytes > part_bytes )); then
    echo "ERROR: BBL payload ($bbl_bytes bytes) exceeds partition 1 ($part_bytes bytes)" >&2
    exit 1
fi

dd if=/dev/zero of="$out_img" bs=512 seek="$part_start" count="$part_size" conv=notrunc status=none
dd if="$bbl_bin" of="$out_img" bs=512 seek="$part_start" conv=notrunc status=progress

echo "Build 67 2x1 $variant image written: $out_img"
echo "Embedded DTB: $build_dtb"
echo "BBL binary: $bbl_bin"
sha256sum "$out_img" "$build_dtb" "$bbl_bin"
