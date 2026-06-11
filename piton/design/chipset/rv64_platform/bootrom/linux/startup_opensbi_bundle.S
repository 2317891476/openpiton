# start sequence for the P3 OpenSBI bundle bootrom
#
# Hart 0 copies the SD bundle into DDR, then all harts enter OpenSBI.
# OpenSBI receives a0=hartid and a1=P3_OPENSBI_DTB_ADDR.

#include <smp.h>

#ifndef P3_OPENSBI_FW_ADDR
#define P3_OPENSBI_FW_ADDR 0x80000000
#endif

#ifndef P3_OPENSBI_DTB_ADDR
#define P3_OPENSBI_DTB_ADDR 0x88000000
#endif

  .section .text.init
  .option norvc
  .globl _prog_start
_prog_start:
  smp_pause(s1, s2)
  li sp, 0x84000000
  call main
  bnez a0, 44f
  smp_resume(s1, s2)
  csrr a0, mhartid
  li a1, P3_OPENSBI_DTB_ADDR
  fence.i
  li s1, P3_OPENSBI_FW_ADDR
  jr s1
44:
  wfi
  j 44b
