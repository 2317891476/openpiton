#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base_img="${P3_BUILD67_BASE_IMG:-$repo_dir/build/huaprop3/sd_images/huaprop3_linux_xsbench_ext2.img}"
source_bbl_dir="$repo_dir/build/huaprop3/ariane-sdk/build-bbl-debug-axi16550-force"
source_bbl_c="$repo_dir/build/a7203x/ariane-sdk/riscv-pk/bbl/bbl.c"
bootrom_dts="$repo_dir/piton/design/chipset/rv64_platform/bootrom/rv64_platform.dts"
build_dir="$repo_dir/build/huaprop3"
work_root="$build_dir/ariane-sdk"

nosmp_bootargs='earlycon=uart8250,mmio,0xfff0c2c000 console=ttyS0,115200n8 rdinit=/bin/sh init=/bin/sh maxcpus=1 nosmp'
marker_bootargs='earlycon=uart8250,mmio,0xfff0c2c000 console=ttyS0,115200n8 rdinit=/bin/sh init=/bin/sh'

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
    local bootargs="$2"
    local disable_cpu1="$3"

    awk -v bootargs="$bootargs" -v disable_cpu1="$disable_cpu1" '
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
        /^[[:space:]]*(CPU1:[[:space:]]*)?cpu@1[[:space:]]*\{/ {
            in_cpu1 = 1
            cpu1_depth = 0
        }
        {
            if (in_cpu1) {
                line = $0
                opens = gsub(/\{/, "{", line)
                line = $0
                closes = gsub(/\}/, "}", line)
                cpu1_depth += opens - closes
                if (disable_cpu1 == "1" && /^[[:space:]]*status[[:space:]]*=/) {
                    print "            status = \"disabled\";"
                    next
                }
                if (cpu1_depth == 0 && /\};/) {
                    in_cpu1 = 0
                }
            }
            print
        }
    ' "$bootrom_dts" > "$out_dts"
}

dtb_to_header() {
    local dtb="$1"
    local header="$2"
    od -An -tx1 -v "$dtb" \
        | sed 's/^ *//; s/  */, 0x/g; s/^/  0x/; s/$/,/' \
        > "$header"
}

prepare_bbl_dir() {
    local variant="$1"
    local variant_dir="$work_root/build-bbl-build67-${variant}"

    rm -rf "$variant_dir"
    cp -a "$source_bbl_dir" "$variant_dir"
    echo "$variant_dir"
}

patch_marker_sources() {
    local variant_dir="$1"

    cp "$source_bbl_c" "$variant_dir/bbl_marker.c"
    sed -i 's/^  bbl.c \\/  bbl_marker.c \\/' "$variant_dir/bbl.mk"
    perl -0pi -e 's/^#define PK_PRINT_DEVICE_TREE .*$/\/\* #undef PK_PRINT_DEVICE_TREE \*\//m' "$variant_dir/config.h"

    perl -0pi -e 's/(\n#ifdef BBL_BOOT_MACHINE\n)/\n  printm("B67M boot_hart=%ld entry=%p dtb=%p disabled=0x%lx\\r\\n", hartid, entry, (void*)dtb_output(), disabled_hart_mask);\n$1/' "$variant_dir/bbl_marker.c"
    perl -0pi -e 's/(\n#ifdef PK_PRINT_DEVICE_TREE\n  fdt_print\(dtb_output\(\)\);\n#endif\n  mb\(\);\n  \/\* Use optional FDT preloaded external payload if present \*\/\n  entry_point = kernel_start \? kernel_start : &_payload_start;\n)/\n  printm("B67M boot_loader dtb_in=%p dtb_out=%p disabled=0x%lx\\r\\n", (void*)dtb, (void*)dtb_output(), disabled_hart_mask);\n$1  printm("B67M entry=%p kernel_start=%p payload_start=%p payload_end=%p\\r\\n", entry_point, kernel_start, &_payload_start, &_payload_end);\n/' "$variant_dir/bbl_marker.c"
    perl -0pi -e 's/(  write_csr\(mepc, fn\);\n)/$1\n  printm("B67M mret hart_arg=%p entry=%p dtb=%p\\r\\n", (void*)arg0, fn, (void*)arg1);\n/' "$variant_dir/minit.c"

    if ! grep -q 'bbl_marker.c' "$variant_dir/bbl.mk"; then
        echo "ERROR: failed to redirect bbl.mk to local marker source" >&2
        exit 1
    fi
    if ! grep -q 'B67M boot_loader' "$variant_dir/bbl_marker.c"; then
        echo "ERROR: failed to patch marker boot_loader print" >&2
        exit 1
    fi
    if ! grep -q 'B67M mret' "$variant_dir/minit.c"; then
        echo "ERROR: failed to patch marker mret print" >&2
        exit 1
    fi
}

build_variant() {
    local variant="$1"
    local bootargs="$2"
    local disable_cpu1="$3"
    local add_markers="$4"

    local variant_dir
    variant_dir="$(prepare_bbl_dir "$variant")"

    local dts="$build_dir/huaprop3_2x1_${variant}.dts"
    local dtb="$build_dir/huaprop3_2x1_${variant}.dtb"
    local bbl_bin="$build_dir/bbl_build67_2x1_${variant}.bin"
    local out_img="$build_dir/sd_images/huaprop3_linux_xsbench_2x1_${variant}.img"

    make_dts "$dts" "$bootargs" "$disable_cpu1"
    grep -q 'riscv,ndev = <2>;' "$dts"
    dtc -I dts "$dts" -O dtb -o "$dtb"

    if [[ "$disable_cpu1" == "1" ]]; then
        dtc -I dtb "$dtb" -O dts 2>/dev/null | grep -q 'status = "disabled"'
        dtc -I dtb "$dtb" -O dts 2>/dev/null | grep -q 'maxcpus=1 nosmp'
    else
        dtc -I dtb "$dtb" -O dts 2>/dev/null | grep -q 'cpu@1'
    fi

    cp "$dts" "$variant_dir/huaprop3.dts"
    cp "$dtb" "$variant_dir/huaprop3.dtb"
    dtb_to_header "$dtb" "$variant_dir/embedded_dtb.h"

    if [[ "$add_markers" == "1" ]]; then
        patch_marker_sources "$variant_dir"
    fi

    make -C "$variant_dir" clean
    env CFLAGS="-fno-stack-protector -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0" make -C "$variant_dir"

    local bbl_elf="$variant_dir/bbl"
    if [[ "$add_markers" == "1" ]]; then
        bbl_elf="$variant_dir/bbl_marker"
    fi

    riscv64-linux-gnu-objcopy \
        -S -O binary --change-addresses -0x80000000 \
        "$bbl_elf" \
        "$bbl_bin"

    if [[ "$add_markers" == "1" ]]; then
        if ! grep -a -q 'B67M' "$bbl_bin"; then
            echo "ERROR: marker BBL binary does not contain B67M strings: $bbl_bin" >&2
            exit 1
        fi
    fi

    cp "$base_img" "$out_img"

    local part_info
    part_info="$(sfdisk -d "$out_img" | sed -n 's/.*1 : start=[[:space:]]*\([0-9][0-9]*\), size=[[:space:]]*\([0-9][0-9]*\),.*/\1 \2/p' | head -n 1)"
    if [[ -z "$part_info" ]]; then
        echo "ERROR: failed to locate partition 1 in $out_img" >&2
        exit 1
    fi

    local part_start part_size part_bytes bbl_bytes
    read -r part_start part_size <<< "$part_info"
    part_bytes=$((part_size * 512))
    bbl_bytes="$(stat -c %s "$bbl_bin")"
    if (( bbl_bytes > part_bytes )); then
        echo "ERROR: BBL payload ($bbl_bytes bytes) exceeds partition 1 ($part_bytes bytes)" >&2
        exit 1
    fi

    dd if=/dev/zero of="$out_img" bs=512 seek="$part_start" count="$part_size" conv=notrunc status=none
    dd if="$bbl_bin" of="$out_img" bs=512 seek="$part_start" conv=notrunc status=progress

    echo "variant=$variant"
    echo "  image=$out_img"
    echo "  dts=$dts"
    echo "  dtb=$dtb"
    echo "  bbl=$bbl_bin"
    sha256sum "$out_img" "$dtb" "$bbl_bin"
}

require_file "$base_img"
require_file "$bootrom_dts"
require_file "$source_bbl_c"
require_dir "$source_bbl_dir"

if ! grep -q 'CPU1: cpu@1' "$bootrom_dts"; then
    echo "ERROR: $bootrom_dts does not contain CPU1; run scripts/p3_rebuild_build67_2x1_normal_spi_sd_boot.sh first" >&2
    exit 1
fi

mkdir -p "$build_dir/sd_images"

build_variant "nosmp" "$nosmp_bootargs" "1" "0"
build_variant "bbl_markers" "$marker_bootargs" "0" "1"
