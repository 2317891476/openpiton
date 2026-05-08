#include <cstdint>
#include <iostream>
#include <string>

#include "Va7203x_mmcm_smoke_top.h"
#include "verilated.h"

static void tick(Va7203x_mmcm_smoke_top* top) {
    top->chipset_clk_osc_p = 0;
    top->chipset_clk_osc_n = 1;
    top->eval();

    top->chipset_clk_osc_p = 1;
    top->chipset_clk_osc_n = 0;
    top->eval();
}

static void run_cycles(Va7203x_mmcm_smoke_top* top, int cycles) {
    for (int i = 0; i < cycles; i++) {
        tick(top);
    }
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Va7203x_mmcm_smoke_top top;
    top.sys_rst_n = 0;
    top.uart_rx = 1;
    top.chipset_clk_osc_p = 0;
    top.chipset_clk_osc_n = 1;
    top.eval();

    run_cycles(&top, 8);
    top.sys_rst_n = 1;

    bool saw_locked = false;
    for (int i = 0; i < 128; i++) {
        tick(&top);
        if (top.leds & 0x2) {
            saw_locked = true;
            break;
        }
    }

    if (!saw_locked) {
        std::cerr << "TEST: FAIL simulated MMCM lock LED did not assert\n";
        return 1;
    }

    const int uart_clks_per_bit = 8;
    const std::string expected = "AX7203 MMCM\r\n";
    std::string received;
    int previous_tx = top.uart_tx;

    for (int cycles = 0; cycles < 20000 && received.size() < expected.size(); cycles++) {
        tick(&top);
        const int tx = top.uart_tx;

        if (previous_tx == 1 && tx == 0) {
            run_cycles(&top, uart_clks_per_bit + (uart_clks_per_bit / 2));

            uint8_t byte = 0;
            for (int bit = 0; bit < 8; bit++) {
                if (top.uart_tx) {
                    byte |= static_cast<uint8_t>(1U << bit);
                }
                run_cycles(&top, uart_clks_per_bit);
            }

            if (!top.uart_tx) {
                std::cerr << "TEST: FAIL UART stop bit was not high\n";
                return 1;
            }

            received.push_back(static_cast<char>(byte));
            previous_tx = top.uart_tx;
        } else {
            previous_tx = tx;
        }
    }

    if (received != expected) {
        std::cerr << "TEST: FAIL UART received mismatch\n";
        std::cerr << "TEST: expected=" << expected << "\n";
        std::cerr << "TEST: received=" << received << "\n";
        return 1;
    }

    std::cout << "TEST: PASS AX7203 MMCM smoke top\n";
    std::cout << "TEST: uart_banner=AX7203 MMCM\\r\\n\n";
    std::cout << "TEST: final_leds=0x" << std::hex << static_cast<int>(top.leds) << std::dec << "\n";
    return 0;
}
