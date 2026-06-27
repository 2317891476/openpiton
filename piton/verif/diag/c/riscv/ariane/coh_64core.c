// Copyright (c) 2026 Princeton University (OpenPiton Ariane bring-up).
// Description: 64-core (8x8) L1 D-cache coherency probe (printf-free).
//
// Scales coh_2core to all 64 harts: core 0 plain-stores a shared line that the
// other 63 cores have already cached; every one of them must observe the new
// value. This stresses broadcast L1 invalidation at scale (the L2 directory
// must invalidate 63 sharers).
//
// Protocol (all sync via AMO, which takes exclusive ownership and invalidates
// other cores' copies of the sync line, so AMO sync is coherent independent
// of the plain-store path under test):
//   cores 1..63 (readers): plain-load data (cache old=0) -> AMO cached_count++
//                          -> spin until phase>=1 -> plain-load data again
//                          -> AMO ok_count++ if NEW else AMO bad_count++
//                          -> AMO done_count++
//   core 1 (also verifier): as reader, then spin until done_count==63,
//                          pass() if bad_count==0 else fail()
//   core 0 (writer): spin until cached_count==63 -> plain-store data=NEW
//                    -> AMO phase=1
//
// Verifier is core 1 (spc(1) traps reliably in this testbench); run with
// -finish_mask=0x2 so core 1's trap ends the sim. bad_count==0 -> PASS.
// No printf (C runtime printbuf polls UART LSR THRE, unmodeled in Verilator).

#include <stdint.h>
#include "util.h"

#define NHARTS 64
#define NEW_VAL 0xCAFE12345678ULL

volatile uint64_t data __attribute__((aligned(64))) = 0;
volatile uint64_t cached_count __attribute__((aligned(64))) = 0;
volatile uint64_t ok_count     __attribute__((aligned(64))) = 0;
volatile uint64_t bad_count    __attribute__((aligned(64))) = 0;
volatile uint64_t done_count   __attribute__((aligned(64))) = 0;
volatile uint64_t phase        __attribute__((aligned(64))) = 0;

#define SPIN_LIMIT 8000000

static inline int spin_ge(volatile uint64_t *p, uint64_t v) {
    uint64_t c = 0;
    while (*p < v) { if (++c > SPIN_LIMIT) return 1; }
    return 0;
}

int main(int argc, char **argv) {
    uint64_t id = argv[0][0];

    if (id == 0) {
        // Writer: wait until all 63 readers have cached data, then plain-store NEW.
        if (spin_ge(&cached_count, NHARTS - 1)) while (1);
        for (volatile int i = 0; i < 500; i++) { }
        data = NEW_VAL;                 // plain store, write-through -> L2
        ATOMIC_OP(phase, 1, add, d);    // release readers
        while (1);                       // core 0's trap is unreliable in this TB; idle
    }

    // Readers (cores 1..63): cache data, signal, wait, re-read, tally.
    volatile uint64_t cached = data;    // plain load -> cache old=0 in L1
    (void)cached;
    ATOMIC_OP(cached_count, 1, add, d);

    if (spin_ge(&phase, 1)) { ATOMIC_OP(bad_count, 1, add, d); ATOMIC_OP(done_count, 1, add, d); while (1); }

    volatile uint64_t fresh = data;     // re-read: NEW iff our L1 line was invalidated
    for (volatile int i = 0; i < 16; i++) { fresh = data; }
    // NOTE: ATOMIC_OP macro expands with a trailing ';', so wrap in braces
    // when used as an if/else body (else the extra ';' breaks the else).
    if (fresh == NEW_VAL) { ATOMIC_OP(ok_count, 1, add, d); }
    else                  { ATOMIC_OP(bad_count, 1, add, d); }
    ATOMIC_OP(done_count, 1, add, d);

    // Core 1 is the verifier: wait for all readers to finish, then verdict.
    if (id == 1) {
        if (spin_ge(&done_count, NHARTS - 1)) fail();
        // give late AMOs a moment to propagate
        for (volatile int i = 0; i < 1000; i++) { }
        if (bad_count == 0 && ok_count == (NHARTS - 1)) pass();
        else fail();
    }
    while (1);
    return 0;
}
