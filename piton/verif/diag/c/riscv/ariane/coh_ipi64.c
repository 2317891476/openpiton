// Copyright (c) 2026 Princeton University (OpenPiton Ariane bring-up).
// Description: 64-core CLINT MSIP (IPI) delivery probe (printf-free).
//
// stop_machine deadlocks because some hart doesn't converge on the SBI IPI
// (CLINT MSIP). coh_64core tested AMO delivery (L2 path); this tests the
// CLINT MSIP interrupt path directly (the path stop_machine actually uses):
//   hart0: write MSIP[h]=1 for h=1..63 (CLINT @ 0xfff1020000, MSIP offset 4*h)
//   hart h (1..63): poll mip.MSIP (bit 3) until set -> mark slot[h], clear MSIP
//   hart0: check all 63 slots filled -> pass(), else fail()
// MSIE/MIE left disabled (reset default) so MSIP is polled, no trap handler.
// No printf (Verilator doesn't model UART). pass/fail via traps; finish_mask=0x1
// (hart0 is the checker).

#include <stdint.h>
#include "util.h"

#define CLINT_BASE 0xfff1020000ULL
#define NHARTS 64
#define MIP_MSIP (1UL << 3)

volatile uint32_t * const clint_msip = (volatile uint32_t *)CLINT_BASE;
volatile uint64_t slots[NHARTS] __attribute__((aligned(64))) = {0};
volatile uint64_t ready_cnt __attribute__((aligned(64))) = 0;
volatile uint64_t done_cnt  __attribute__((aligned(64))) = 0;

#define SPIN_LIMIT 4000000
static inline int spin_ge(volatile uint64_t *p, uint64_t v) {
    uint64_t c = 0;
    while (*p < v) { if (++c > SPIN_LIMIT) return 1; }
    return 0;
}

int main(int argc, char **argv) {
    uint64_t id = argv[0][0];

    if (id == 0) {
        // hart0: wait for all readers ready, send MSIP to each, wait, verify
        if (spin_ge(&ready_cnt, NHARTS - 1)) fail();
        for (volatile int i = 0; i < 200; i++) { }       // let readers settle into poll
        for (uint64_t h = 1; h < NHARTS; h++) clint_msip[h] = 1;   // assert MSIP[h]
        if (spin_ge(&done_cnt, NHARTS - 1)) fail();      // wait for all readers to finish
        for (volatile int i = 0; i < 2000; i++) { }       // let late stores propagate
        uint64_t ok = 0;
        for (uint64_t h = 1; h < NHARTS; h++) if (slots[h] != 0) ok++;
        if (ok == NHARTS - 1) pass(); else fail();
    } else {
        // reader hart h: signal ready, poll mip.MSIP, mark slot, clear MSIP
        ATOMIC_OP(ready_cnt, 1, add, d);
        uint64_t mip; uint64_t c = 0;
        do {
            __asm__ volatile ("csrr %0, mip" : "=r"(mip));
            if (++c > SPIN_LIMIT) { ATOMIC_OP(done_cnt, 1, add, d); while (1); } // timed out
        } while (!(mip & MIP_MSIP));
        // saw MSIP
        slots[id] = id + 1;                 // mark (plain store; hart0 reads via coherent L2)
        clint_msip[id] = 0;                 // clear own MSIP
        ATOMIC_OP(done_cnt, 1, add, d);
        while (1);
    }
    return 0;
}
