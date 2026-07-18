// AMO smoke test: does amoadd.w through L1.5/L2, then pass/fail.
// No printf: Verilator Ariane UART model does not implement LSR THRE.

#include <stdint.h>
#include "util.h"

extern void pass(void) __attribute__((noreturn));
extern void fail(void) __attribute__((noreturn));

int main(void)
{
    volatile uint32_t amo_val = 100;
    volatile uint32_t *p = &amo_val;

    // amoadd.w zero, 5, (p)  -> amo_val should become 105
    ATOMIC_OP(*p, 5, add, w);

    if (amo_val == 105) {
        pass();
    } else {
        fail();
    }
    return 0;
}
