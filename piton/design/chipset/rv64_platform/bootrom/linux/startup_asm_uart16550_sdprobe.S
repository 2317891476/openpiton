# No-stack UART + SD smoke bootrom for the original P3 AXI UART16550 path.
#
# This diagnostic initializes the ns16550 UART, prints a short banner, then
# performs one direct SD mapped read from the native OpenPiton SD window.
# It avoids stack setup, C calls, DDR, and any dependence on a working DDR
# stack. The goal is to keep the software path fixed while isolating the
# UART and SD acceptance path.

#define UART_BASE 0xFFF0C2C000
#define UART_THR  0x00
#define UART_IER  0x01
#define UART_FCR  0x02
#define UART_LCR  0x03
#define UART_MCR  0x04
#define UART_LSR  0x05
#define UART_DLL  0x00
#define UART_DLM  0x01

#define SD_BASE_ADDR 0xF000000000

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

  # 30 MHz / (16 * 115200) = 16.276, matching the validated standalone test.
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
  uart_putc 0x35
  uart_putc 0x30
  uart_putc 0x20
  uart_putc 0x55
  uart_putc 0x41
  uart_putc 0x52
  uart_putc 0x54
  uart_putc 0x20
  uart_putc 0x53
  uart_putc 0x44
  uart_putc 0x0d
  uart_putc 0x0a

  li t5, SD_BASE_ADDR
  ld t6, 0(t5)
  ld t4, 8(t5)

  uart_putc 0x52
  uart_putc 0x0d
  uart_putc 0x0a

  # Print a small fixed stream so the operator can tell the core is still alive.
loop:
  uart_putc 0x41
  li t3, 300000
1:
  addi t3, t3, -1
  bnez t3, 1b
  j loop
