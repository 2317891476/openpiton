#include "uart.h"
#include "spi.h"
#include "sd.h"
#include "gpt.h"
#include "info.h"

int main()
{
    init_uart(UART_FREQ, 115200);
    print_uart(info);

    print_uart("sd initialized!\r\n");

    int res = gpt_find_boot_partition((uint8_t *)0x80000000UL, 2 * 32768);

    // Verify DDR content at jump target
    print_uart("DDR[0x80000000]: ");
    print_uart_addr(*(volatile uint64_t *)0x80000000UL);
    print_uart("\r\n");
    print_uart("DDR[0x80000008]: ");
    print_uart_addr(*(volatile uint64_t *)0x80000008UL);
    print_uart("\r\n");

    // Check raw SD mapped data at sector 0 and sector 2048
    print_uart("SD[sector0]: ");
    print_uart_addr(*(volatile uint64_t *)0xf000000000UL);
    print_uart("\r\n");
    print_uart("SD[sect2048]: ");
    print_uart_addr(*(volatile uint64_t *)(0xf000000000UL + 2048UL * 512UL));
    print_uart("\r\n");

    return 0;
}

void handle_trap(void)
{
    // print_uart("trap\r\n");
}
