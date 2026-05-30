# No-stack DDR probe bootrom for the original P3 AXI UART16550 path.
#
# This diagnostic initializes the ns16550 UART, prints progress markers, then
# performs one DDR store/fence/load/compare using only registers. It avoids
# stack setup, C calls, SD, and any dependency on a working DDR-backed stack.

#define UART_BASE 0xFFF0C2C000
#define UART_THR  0x00
#define UART_IER  0x01
#define UART_FCR  0x02
#define UART_LCR  0x03
#define UART_MCR  0x04
#define UART_LSR  0x05
#define UART_DLL  0x00
#define UART_DLM  0x01

#define DDR_PROBE_ADDR 0x84000000

  .section .text.init
  .option norvc
  .globl _prog_start
  .globl main

  .macro uart_putc value
1:
  lbu t1, UART_LSR(t0)
  andi t1, t1, 0x20
  beqz t1, 1b
  li t2, \value
  sb t2, UART_THR(t0)
  .endm

_prog_start:
main:
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

  la t6, trap_handler
  csrw mtvec, t6

  uart_putc 0x42
  uart_putc 0x34
  uart_putc 0x34
  uart_putc 0x20
  uart_putc 0x44
  uart_putc 0x44
  uart_putc 0x52
  uart_putc 0x0d
  uart_putc 0x0a

  uart_putc 0x57
  li t4, 0x1122334455667788
  li t5, DDR_PROBE_ADDR
  sd t4, 0(t5)
  fence rw, rw
  uart_putc 0x77

  uart_putc 0x52
  ld t6, 0(t5)
  fence rw, rw
  uart_putc 0x72

  bne t6, t4, ddr_fail
  uart_putc 0x50
  uart_putc 0x0d
  uart_putc 0x0a
  j pass_loop

ddr_fail:
  uart_putc 0x46
  uart_putc 0x0d
  uart_putc 0x0a
  j fail_loop

trap_handler:
  li t0, UART_BASE
  uart_putc 0x45
  uart_putc 0x0d
  uart_putc 0x0a
  j fail_loop

pass_loop:
  uart_putc 0x41
  li t3, 300000
1:
  addi t3, t3, -1
  bnez t3, 1b
  j pass_loop

fail_loop:
  uart_putc 0x58
  li t3, 300000
1:
  addi t3, t3, -1
  bnez t3, 1b
  j fail_loop
