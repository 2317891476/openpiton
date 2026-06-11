#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base_img="${P3_BUILD67_BASE_IMG:-$repo_dir/build/huaprop3/sd_images/huaprop3_linux_xsbench_ext2.img}"
out_img="${P3_BUILD67_OUT_IMG:-$repo_dir/build/huaprop3/sd_images/huaprop3_linux_xsbench_2x1_sbi_trace.img}"
source_bbl_dir="${P3_BUILD67_SOURCE_BBL_DIR:-$repo_dir/build/huaprop3/ariane-sdk/build-bbl-build67-keep_divisor}"
source_pk="${P3_RISCV_PK_SRC:-$repo_dir/build/a7203x/ariane-sdk/riscv-pk}"
bootrom_dts="$repo_dir/piton/design/chipset/rv64_platform/bootrom/rv64_platform.dts"
build_dir="$repo_dir/build/huaprop3"
work_root="$build_dir/ariane-sdk"
variant_name="${P3_BUILD67_TRACE_VARIANT:-sbi_trace}"
variant_dir="$work_root/build-bbl-build67-$variant_name"

bootargs='earlycon=uart8250,mmio,0xfff0c2c000 console=ttyS0,115200n8 rdinit=/bin/sh init=/bin/sh keep_bootcon loglevel=8 ignore_loglevel initcall_debug'

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
    ' "$bootrom_dts" > "$out_dts"
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
    cp "$source_pk/machine/mtrap.c" "$variant_dir/mtrap.c"
    cp "$source_pk/machine/mentry.S" "$variant_dir/mentry.S"

    perl - "$variant_dir/bbl.c" "$variant_dir/mtrap.c" "$variant_dir/mentry.S" <<'PERL'
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

my ($bbl_path, $mtrap_path, $mentry_path) = @ARGV;

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
  printm("B67S linux_entry_ready hart=%ld entry=%p dtb=%p disabled=0x%lx\r\n",
         hartid, entry, (void*)dtb_output(), disabled_hart_mask);
  if ((1 << hartid) & disabled_hart_mask) {
    while (1) {
      __asm__ volatile("wfi");
#ifdef __riscv_div
      __asm__ volatile("div x0, x0, x0");
#endif
    }
  }

  if (hartid != 0) {
    printm("B67S secondary_delay hart=%ld\r\n", hartid);
    for (volatile uintptr_t delay = 0; delay < 2000000; delay++) {
      __asm__ volatile("nop");
    }
  }

  printm("B67S linux_enter hart=%ld entry=%p dtb=%p\r\n", hartid, entry, (void*)dtb_output());

#ifdef BBL_BOOT_MACHINE
NEW

replace_once($bbl_path, <<'OLD', <<'NEW');
  entry_point = kernel_start ? kernel_start : &_payload_start;
  boot_other_hart(0);
OLD
  entry_point = kernel_start ? kernel_start : &_payload_start;
  printm("B67S entry_point_set entry=%p kernel_start=%p payload_start=%p payload_end=%p\r\n",
         entry_point, kernel_start, &_payload_start, &_payload_end);
  boot_other_hart(0);
NEW

replace_once($mtrap_path, <<'OLD', <<'NEW');
void printm(const char* s, ...)
{
  va_list vl;

  va_start(vl, s);
  vprintm(s, vl);
  va_end(vl);
}

static void send_ipi(uintptr_t recipient, int event)
OLD
void printm(const char* s, ...)
{
  va_list vl;

  va_start(vl, s);
  vprintm(s, vl);
  va_end(vl);
}

uint32_t b67s_timer_count[MAX_HARTS][16] __attribute__((aligned(64)));
volatile uintptr_t b67s_mtimer_irq_count[MAX_HARTS][8] __attribute__((aligned(64)));
volatile uintptr_t b67s_msoft_irq_count[MAX_HARTS][8] __attribute__((aligned(64)));
volatile uintptr_t b67s_clear_ipi_count[MAX_HARTS][8] __attribute__((aligned(64)));
volatile uintptr_t b67s_soft_sent_count[MAX_HARTS][MAX_HARTS];
volatile uintptr_t b67c_mtimer_mtie_zero_count[MAX_HARTS][8] __attribute__((aligned(64)));
volatile uintptr_t b67c_mtimer_mie_before[MAX_HARTS][8] __attribute__((aligned(64)));
volatile uintptr_t b67c_mtimer_mie_after[MAX_HARTS][8] __attribute__((aligned(64)));
volatile uintptr_t b67c_mtimer_mip[MAX_HARTS][8] __attribute__((aligned(64)));
volatile uintptr_t b67c_mtimer_mcause[MAX_HARTS][8] __attribute__((aligned(64)));
volatile uintptr_t b67c_mtimer_mepc[MAX_HARTS][8] __attribute__((aligned(64)));
volatile uintptr_t b67c_mtimer_mstatus[MAX_HARTS][8] __attribute__((aligned(64)));
static uint32_t b67s_ipi_count[MAX_HARTS][16] __attribute__((aligned(64)));

static int b67s_should_trace(uint32_t *count)
{
  uint32_t c = *count;
  *count = c + 1;
  return c < 8 || ((c & 0x3ff) == 0);
}

static void send_ipi(uintptr_t recipient, int event)
NEW

replace_once($mtrap_path, <<'OLD', <<'NEW');
static void send_ipi(uintptr_t recipient, int event)
{
  if (((disabled_hart_mask >> recipient) & 1)) return;
  // atomic or
  atomic_binop(&OTHER_HLS(recipient)->mipi_pending, event, res | (event));
  mb();
  *OTHER_HLS(recipient)->ipi = 1;
}
OLD
static void send_ipi(uintptr_t recipient, int event)
{
  if (((disabled_hart_mask >> recipient) & 1)) return;
  if (event == IPI_SOFT) {
    uintptr_t sender = read_csr(mhartid);
    if (sender < MAX_HARTS && recipient < MAX_HARTS)
      b67s_soft_sent_count[sender][recipient]++;
  }
  // atomic or
  atomic_binop(&OTHER_HLS(recipient)->mipi_pending, event, res | (event));
  mb();
  *OTHER_HLS(recipient)->ipi = 1;
}
NEW

replace_once($mtrap_path, <<'OLD', <<'NEW');
static uintptr_t mcall_clear_ipi()
{
  return clear_csr(mip, MIP_SSIP) & MIP_SSIP;
}
OLD
static uintptr_t mcall_clear_ipi()
{
  uintptr_t hart = read_csr(mhartid);
  if (hart < MAX_HARTS)
    b67s_clear_ipi_count[hart][0]++;
  return clear_csr(mip, MIP_SSIP) & MIP_SSIP;
}
NEW

replace_once($mtrap_path, <<'OLD', <<'NEW');
static uintptr_t mcall_set_timer(uint64_t when)
{
  *HLS()->timecmp = when;
  clear_csr(mip, MIP_STIP);
  set_csr(mie, MIP_MTIP);
  return 0;
}
OLD
static uintptr_t mcall_set_timer(uint64_t when)
{
  uintptr_t hart = read_csr(mhartid);
  uint32_t idx = hart < MAX_HARTS ? hart : 0;
  if (b67s_should_trace(&b67s_timer_count[idx][0])) {
    printm("B67S set_timer hart=%ld count=%u when=%p timecmp=%p\r\n",
           hart, b67s_timer_count[idx][0], (void*)(uintptr_t)when, HLS()->timecmp);
    if (hart == 0)
      printm("B67I irq_snapshot set0=%u set1=%u mt0=%ld mt1=%ld ms0=%ld ms1=%ld clear0=%ld clear1=%ld send01=%ld send10=%ld mip=0x%lx mie=0x%lx\r\n",
             b67s_timer_count[0][0], b67s_timer_count[1][0],
             b67s_mtimer_irq_count[0][0], b67s_mtimer_irq_count[1][0],
             b67s_msoft_irq_count[0][0], b67s_msoft_irq_count[1][0],
             b67s_clear_ipi_count[0][0], b67s_clear_ipi_count[1][0],
             b67s_soft_sent_count[0][1], b67s_soft_sent_count[1][0],
             read_csr(mip), read_csr(mie));
    if (hart == 0)
      printm("B67C mt1z=%ld mie1b=0x%lx mie1a=0x%lx mip1=0x%lx cause1=0x%lx epc1=%p status1=0x%lx\r\n",
             b67c_mtimer_mtie_zero_count[1][0],
             b67c_mtimer_mie_before[1][0], b67c_mtimer_mie_after[1][0],
             b67c_mtimer_mip[1][0], b67c_mtimer_mcause[1][0],
             (void*)b67c_mtimer_mepc[1][0], b67c_mtimer_mstatus[1][0]);
  }
  *HLS()->timecmp = when;
  clear_csr(mip, MIP_STIP);
  set_csr(mie, MIP_MTIP);
  return 0;
}
NEW

replace_once($mtrap_path, <<'OLD', <<'NEW');
static void send_ipi_many(uintptr_t* pmask, int event)
{
  _Static_assert(MAX_HARTS <= 16 * sizeof(*pmask), "# harts > uintptr_t bits");
  uintptr_t mask = hart_mask;
  if (pmask)
    mask &= load_uintptr_t(pmask, read_csr(mepc));

  // send IPIs to everyone
  for (uintptr_t i = 0, m = mask; m; i++, m >>= 1)
    if (m & 1)
      send_ipi(i, event);

  if (event == IPI_SOFT)
    return;

  // wait until all events have been handled.
  // prevent deadlock by consuming incoming IPIs.
  uint32_t incoming_ipi = 0;
  for (uintptr_t i = 0, m = mask; m; i++, m >>= 1)
    if (m & 1)
      while (*OTHER_HLS(i)->ipi)
        incoming_ipi |= atomic_binop(HLS()->ipi, 0, (0)); // atomic swap

  // if we got an IPI, restore it; it will be taken after returning
  if (incoming_ipi) {
    *HLS()->ipi = incoming_ipi;
    mb();
  }
}
OLD
static void send_ipi_many(uintptr_t* pmask, int event)
{
  _Static_assert(MAX_HARTS <= 16 * sizeof(*pmask), "# harts > uintptr_t bits");
  uintptr_t mask = hart_mask;
  if (pmask)
    mask &= load_uintptr_t(pmask, read_csr(mepc));

  uintptr_t current_hart = read_csr(mhartid);
  uintptr_t trace_hart = current_hart < MAX_HARTS ? current_hart : 0;
  uint32_t event_idx = event < 16 ? event : 0;
  int trace_this = b67s_should_trace(&b67s_ipi_count[trace_hart][event_idx]);

  if (trace_this)
    printm("B67S ipi_enter hart=%ld event=%d mask=0x%lx pmask=%p mepc=%p\r\n",
           current_hart, event, mask, pmask, (void*)read_csr(mepc));

  // send IPIs to everyone
  for (uintptr_t i = 0, m = mask; m; i++, m >>= 1)
    if (m & 1)
      send_ipi(i, event);

  if (event == IPI_SOFT) {
    if (trace_this)
      printm("B67S ipi_soft_exit hart=%ld event=%d mask=0x%lx\r\n",
             current_hart, event, mask);
    return;
  }

  // wait until all events have been handled.
  // prevent deadlock by consuming incoming IPIs.
  uint32_t incoming_ipi = 0;
  for (uintptr_t i = 0, m = mask; m; i++, m >>= 1)
    if (m & 1) {
      uint32_t spins = 0;
      while (*OTHER_HLS(i)->ipi) {
        spins++;
        if (trace_this && (spins == (1u << 20) || spins == (1u << 24) || spins == (1u << 28)))
          printm("B67S ipi_wait hart=%ld target=%ld event=%d spins=%u target_msip=%u self_msip=%u\r\n",
                 current_hart, i, event, spins, *OTHER_HLS(i)->ipi, *HLS()->ipi);
        incoming_ipi |= atomic_binop(HLS()->ipi, 0, (0)); // atomic swap
      }
      if (trace_this && spins)
        printm("B67S ipi_wait_done hart=%ld target=%ld event=%d spins=%u\r\n",
               current_hart, i, event, spins);
    }

  if (trace_this)
    printm("B67S ipi_exit hart=%ld event=%d mask=0x%lx incoming=0x%x\r\n",
           current_hart, event, mask, incoming_ipi);

  // if we got an IPI, restore it; it will be taken after returning
  if (incoming_ipi) {
    *HLS()->ipi = incoming_ipi;
    mb();
  }
}
NEW

replace_once($mentry_path, <<'OLD', <<'NEW');
  # Yes.  Simply clear MTIE and raise STIP.
  li a0, MIP_MTIP
  csrc mie, a0
  li a0, MIP_STIP
  csrs mip, a0
OLD
  # Count per-hart MTIP entries before redirecting the interrupt to S-mode.
  la a0, b67s_mtimer_irq_count
  csrr a1, mhartid
  slli a1, a1, 6
  add a0, a0, a1
  ld a1, 0(a0)
  addi a1, a1, 1
  sd a1, 0(a0)

  # Record the incoming timer-trap state.
  la a0, b67c_mtimer_mie_before
  csrr a1, mhartid
  slli a1, a1, 6
  add a0, a0, a1
  csrr a1, mie
  sd a1, 0(a0)
  andi a1, a1, MIP_MTIP
  bnez a1, 2f

  la a0, b67c_mtimer_mtie_zero_count
  csrr a1, mhartid
  slli a1, a1, 6
  add a0, a0, a1
  ld a1, 0(a0)
  addi a1, a1, 1
  sd a1, 0(a0)
2:
  la a0, b67c_mtimer_mip
  csrr a1, mhartid
  slli a1, a1, 6
  add a0, a0, a1
  csrr a1, mip
  sd a1, 0(a0)

  la a0, b67c_mtimer_mcause
  csrr a1, mhartid
  slli a1, a1, 6
  add a0, a0, a1
  csrr a1, mcause
  sd a1, 0(a0)

  la a0, b67c_mtimer_mepc
  csrr a1, mhartid
  slli a1, a1, 6
  add a0, a0, a1
  csrr a1, mepc
  sd a1, 0(a0)

  la a0, b67c_mtimer_mstatus
  csrr a1, mhartid
  slli a1, a1, 6
  add a0, a0, a1
  csrr a1, mstatus
  sd a1, 0(a0)

  # Clear MTIE and record the post-clear value before raising STIP.
  li a0, MIP_MTIP
  csrc mie, a0

  la a0, b67c_mtimer_mie_after
  csrr a1, mhartid
  slli a1, a1, 6
  add a0, a0, a1
  csrr a1, mie
  sd a1, 0(a0)

  li a0, MIP_STIP
  csrs mip, a0
NEW

replace_once($mentry_path, <<'OLD', <<'NEW');
  # Yes.  First, clear the MIPI bit.
  LOAD a0, MENTRY_IPI_OFFSET(sp)
  sw x0, (a0)
  fence
OLD
  # Count per-hart MSIP entries before clearing the CLINT MIPI bit.
  la a0, b67s_msoft_irq_count
  csrr a1, mhartid
  slli a1, a1, 6
  add a0, a0, a1
  ld a1, 0(a0)
  addi a1, a1, 1
  sd a1, 0(a0)

  # Clear the CLINT MIPI bit.
  LOAD a0, MENTRY_IPI_OFFSET(sp)
  sw x0, (a0)
  fence
NEW
PERL
}

require_file "$base_img"
require_file "$bootrom_dts"
require_file "$source_pk/bbl/bbl.c"
require_file "$source_pk/machine/mtrap.c"
require_dir "$source_bbl_dir"

if ! grep -q 'CPU1: cpu@1' "$bootrom_dts"; then
    echo "ERROR: $bootrom_dts does not contain CPU1; run scripts/p3_rebuild_build67_2x1_normal_spi_sd_boot.sh first" >&2
    exit 1
fi

rm -rf "$variant_dir"
cp -a "$source_bbl_dir" "$variant_dir"

build_dts="$build_dir/huaprop3_2x1_${variant_name}.dts"
build_dtb="$build_dir/huaprop3_2x1_${variant_name}.dtb"
bbl_bin="$build_dir/bbl_build67_2x1_${variant_name}.bin"

make_dts "$build_dts"
grep -q 'riscv,ndev = <2>;' "$build_dts"
dtc -I dts "$build_dts" -O dtb -o "$build_dtb"
dtc -I dtb "$build_dtb" -O dts 2>/dev/null | grep -q 'cpu@1'
dtc -I dtb "$build_dtb" -O dts 2>/dev/null | grep -q 'initcall_debug'
dtc -I dtb "$build_dtb" -O dts 2>/dev/null | grep -q 'keep_bootcon'

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

if ! grep -a -q 'B67S' "$bbl_bin"; then
    echo "ERROR: SBI trace BBL binary does not contain B67S strings: $bbl_bin" >&2
    exit 1
fi
if ! grep -a -q 'B67I irq_snapshot' "$bbl_bin"; then
    echo "ERROR: IRQ-chain trace BBL binary does not contain B67I snapshot strings: $bbl_bin" >&2
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

echo "Build 67 2x1 SBI trace image written: $out_img"
echo "Embedded DTB: $build_dtb"
echo "BBL binary: $bbl_bin"
sha256sum "$out_img" "$build_dtb" "$bbl_bin"
