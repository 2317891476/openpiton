// Copyright (c) 2026 Princeton University (OpenPiton Ariane bring-up).
// Description: 2-core L1 D-cache coherency probe (printf-free).
//
// Tests whether a PLAIN (write-through) store by core 0 invalidates core 1's
// stale L1 copy of the same line. The L1 invalidation path exists in RTL
// (wt_l15_adapter L15_EVICT_REQ -> DCACHE_INV_REQ; wt_dcache_missunit clears
// the valid bit) -- this tests whether it actually FIRES for a plain store.
//
// Protocol (sync uses AMO, which itself takes exclusive ownership and
// invalidates the other core's copy of the sync line, so AMO sync is
// coherent independent of the plain-store path under test):
//   core 1: plain-load data (caches old=0) -> AMO ctrl+1 -> spin until ctrl>=3
//           -> plain-load data again -> pass() if NEW else fail()
//   core 0: spin until ctrl>=1 -> plain-store data=NEW -> AMO ctrl+2 -> pass()
//
// Bounded spins: if any sync times out (coherency so broken even AMO
// invalidation fails), the test resolves to fail() instead of hanging.
//
// No printf: the C runtime's printbuf polls UART LSR THRE, which the
// Verilator testbench does not model, so printf would hang the core.

#include <stdint.h>
#include "util.h"

// Each on its own cacheline so their L1 entries are independent.
volatile uint64_t data __attribute__((aligned(64))) = 0;
volatile uint64_t ctrl __attribute__((aligned(64))) = 0;

#define NEW_VAL 0xDEADBEEF12345ULL
#define SPIN_LIMIT 4000000

static inline int spin_ge(volatile uint64_t *p, uint64_t v) {
    uint64_t c = 0;
    while (*p < v) {
        if (++c > SPIN_LIMIT) return 1;  // timed out
    }
    return 0;
}

int main(int argc, char **argv) {
    uint64_t id = argv[0][0];

    if (id == 1) {
        // Core 1: cache the data line (old value 0).
        volatile uint64_t cached = data;
        (void)cached;
        // Tell core 0 we have cached (AMO invalidates core 0's ctrl copy).
        ATOMIC_OP(ctrl, 1, add, d);
        // Wait for core 0 to plain-store data and signal (ctrl -> 3).
        if (spin_ge(&ctrl, 3)) fail();
        // Re-read data. NEW iff core 0's plain store invalidated our L1 line.
        // A few extra plain loads to be robust against timing.
        volatile uint64_t fresh = data;
        for (volatile int i = 0; i < 32; i++) { fresh = data; }
        if (fresh == NEW_VAL) pass();
        else fail();
    } else {
        // Core 0: wait for core 1 to cache data (ctrl -> 1 via its AMO).
        if (spin_ge(&ctrl, 1)) fail();
        // Settle: let core 1's cached load retire.
        for (volatile int i = 0; i < 300; i++) { }
        // PLAIN store (write-through -> L2). Does L2 invalidate core 1's L1?
        data = NEW_VAL;
        // Signal core 1 to re-read (AMO invalidates core 1's ctrl copy).
        ATOMIC_OP(ctrl, 2, add, d);
        pass();
    }
    return 0;
}
