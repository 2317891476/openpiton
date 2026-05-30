#define UART_BASE     0xFFF0C2C000
#define SIFIVE_TXDATA 0x00
#define SIFIVE_TXCTRL 0x08
#define SIFIVE_RXCTRL 0x0C
#define SIFIVE_IE     0x10
#define SIFIVE_DIV    0x18

  .section .text.init
  .option norvc
  .globl _prog_start
  .globl main
_prog_start:
main:
  li t0, UART_BASE

  # 30 MHz / 115200 - 1 = 259.
  li t1, 259
  sw t1, SIFIVE_DIV(t0)

  li t1, 1
  sw t1, SIFIVE_TXCTRL(t0)
  sw t1, SIFIVE_RXCTRL(t0)
  sw zero, SIFIVE_IE(t0)

loop:
wait_tx:
  lw t1, SIFIVE_TXDATA(t0)
  bltz t1, wait_tx

  li t2, 0x41
  sw t2, SIFIVE_TXDATA(t0)

  li t3, 300000
delay:
  addi t3, t3, -1
  bnez t3, delay

  j loop
