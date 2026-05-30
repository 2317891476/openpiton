# No-stack UART smoke bootrom for the original P3 AXI UART16550 path.
#
# This file intentionally avoids stack setup, C calls, DDR, and SD. It only
# fetches from bootrom and accesses the ns16550 MMIO window at CPU-visible
# byte offsets. The P3 uart_top transforms those offsets to the Xilinx
# axi_uart16550 word-aligned register addresses.

#define UART_BASE 0xFFF0C2C000
#define UART_THR  0x00
#define UART_IER  0x01
#define UART_FCR  0x02
#define UART_LCR  0x03
#define UART_MCR  0x04
#define UART_LSR  0x05
#define UART_DLL  0x00
#define UART_DLM  0x01

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
  uart_putc 0x34
  uart_putc 0x33
  uart_putc 0x20
  uart_putc 0x41
  uart_putc 0x58
  uart_putc 0x49
  uart_putc 0x31
  uart_putc 0x36
  uart_putc 0x35
  uart_putc 0x35
  uart_putc 0x30
  uart_putc 0x0d
  uart_putc 0x0a

loop:
wait_tx:
  lbu t1, UART_LSR(t0)
  andi t1, t1, 0x20
  beqz t1, wait_tx

  li t2, 0x41
  sb t2, UART_THR(t0)

  li t3, 300000
delay:
  addi t3, t3, -1
  bnez t3, delay

  j loop
