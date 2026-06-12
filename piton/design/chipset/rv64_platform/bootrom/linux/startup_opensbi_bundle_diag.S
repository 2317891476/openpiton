# Diagnostic start sequence for the P3 OpenSBI bundle bootrom.
#
# It prints a no-stack UART marker before touching DDR-backed C state, then
# follows the normal Build 68 handoff path after main() passes.

#include <smp.h>

#define UART_BASE 0xFFF0C2C000
#define UART_THR  0x00
#define UART_IER  0x01
#define UART_FCR  0x02
#define UART_LCR  0x03
#define UART_MCR  0x04
#define UART_LSR  0x05
#define UART_DLL  0x00
#define UART_DLM  0x01

#ifndef P3_OPENSBI_FW_ADDR
#define P3_OPENSBI_FW_ADDR 0x80000000
#endif

#ifndef P3_OPENSBI_DTB_ADDR
#define P3_OPENSBI_DTB_ADDR 0x88000000
#endif

  .section .text.init
  .option norvc
  .globl _prog_start

  .macro uart_putc value
1:
  lbu t1, UART_LSR(t0)
  andi t1, t1, 0x20
  beqz t1, 1b
  li t2, \value
  sb t2, UART_THR(t0)
  .endm

_prog_start:
  smp_pause(s1, s2)

  li t0, UART_BASE
  sb zero, UART_IER(t0)
  li t1, 0x80
  sb t1, UART_LCR(t0)
  li t1, 16
  sb t1, UART_DLL(t0)
  sb zero, UART_DLM(t0)
  li t1, 0x07
  sb t1, UART_FCR(t0)
  li t1, 0x03
  sb t1, UART_LCR(t0)
  sb zero, UART_MCR(t0)

  uart_putc 0x42
  uart_putc 0x36
  uart_putc 0x39
  uart_putc 0x20
  uart_putc 0x41
  uart_putc 0x53
  uart_putc 0x4d
  uart_putc 0x0d
  uart_putc 0x0a

  li sp, 0x84000000
  call main
  bnez a0, 44f
  smp_resume(s1, s2)
  csrr a0, mhartid
  li a1, P3_OPENSBI_DTB_ADDR
  fence rw, rw
  fence.i
  li s1, P3_OPENSBI_FW_ADDR
  jr s1
44:
  wfi
  j 44b
