# start sequence of the bootloader
# 
# 
#include <smp.h>
#define DRAM_BASE 0x80000000

  .section .text.init
  .option norvc
  .globl _prog_start
_prog_start:
  smp_pause(s1, s2)
  li sp, 0x84000000
  call main
  smp_resume(s1, s2)
  csrr a0, mhartid
  # Use lla (PC-relative) instead of la (may use GOT) to get DTB address
  # This is critical because bootrom is linked at 0x10000 but runs at 0xFFF1010000
  .option push
  .option norelax
  1: auipc a1, %pcrel_hi(_dtb)
  addi a1, a1, %pcrel_lo(1b)
  .option pop
  fence.i
  li s1, DRAM_BASE
  jr s1

  .section .dtb
  .globl _dtb
  .align 4, 0
_dtb:
  .incbin "rv64_platform.dtb"
