// AMO flood: generate heavy D-cache miss traffic then AMO, to stress L1.5 MSHRs.
// No printf. pass()/fail() only.

#include <stdint.h>
#include "util.h"

extern void pass(void) __attribute__((noreturn));
extern void fail(void) __attribute__((noreturn));

#define CACHELINE 64
#define NPAGES 32
#define BUFSZ (NPAGES * CACHELINE / sizeof(uint32_t))

int main(void)
{
    // Use multiple buffers at different cache line offsets to generate
    // many L1.5 cache misses before doing AMOs.
    volatile static uint32_t big[BUFSZ];

    // Phase 1: fill L1.5/L2 with stores (many cache line fills)
    for (int i = 0; i < BUFSZ; i++) big[i] = (uint32_t)i;

    // Phase 2: random-ish load pattern to create L1.5 miss pressure
    for (int i = 0; i < BUFSZ; i += 7) { volatile uint32_t x = big[i]; (void)x; }
    for (int i = 1; i < BUFSZ; i += 5) { volatile uint32_t x = big[i]; (void)x; }
    for (int i = 3; i < BUFSZ; i += 3) { volatile uint32_t x = big[i]; (void)x; }

    // Phase 3: now do AMOs interleaved with loads
    for (int i = 0; i < BUFSZ; i++) {
        ATOMIC_OP(big[i], 1, add, w);
    }

    // Phase 4: verify
    for (int i = 0; i < BUFSZ; i++) {
        if (big[i] != (uint32_t)(i + 1)) fail();
    }

    pass();
    return 0;
}
