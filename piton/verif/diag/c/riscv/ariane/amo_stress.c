// AMO stress test: multiple AMO types + loads/stores, simulating Linux patterns.
// No printf: Verilator Ariane UART model does not implement LSR THRE.

#include <stdint.h>
#include "util.h"

extern void pass(void) __attribute__((noreturn));
extern void fail(void) __attribute__((noreturn));

#define N 64

int main(void)
{
    volatile uint32_t buf[N];

    // Phase 1: initialize with normal stores (fills L1.5/L2)
    for (int i = 0; i < N; i++) buf[i] = i;

    // Phase 2: normal loads to verify
    for (int i = 0; i < N; i++) { if (buf[i] != i) fail(); }

    // Phase 3: AMO operations of various types
    for (int i = 0; i < N; i++) ATOMIC_OP(buf[i], 1, add, w);
    for (int i = 0; i < N; i++) ATOMIC_OP(buf[i], 0x10, or, w);
    for (int i = 0; i < N; i++) ATOMIC_OP(buf[i], 0x1, and, w);

    // Phase 4: verify
    for (int i = 0; i < N; i++) {
        // i + 1 (add) | 0x10 (or) & 1 (and) = (i+1) | 0x10 & 1
        uint32_t exp = ((i + 1) | 0x10) & 0x1;
        if (buf[i] != exp) fail();
    }

    // Phase 5: LR/SC test
    volatile uint32_t lrsc_val = 0;
    uint32_t lr_ret;
    LR_OP(lr_ret, lrsc_val, w);
    if (lr_ret != 0) fail();

    pass();
    return 0;
}
