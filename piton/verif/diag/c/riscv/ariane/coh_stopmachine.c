// Copyright (c) 2026 Princeton University (OpenPiton Ariane bring-up).
// Description: 64-core multi_cpu_stop shared-state visibility probe (printf-free).
//
// The board hang is a stop_machine deadlock. Linux `multi_cpu_stop` is a spin
// state machine: a leader advances a SHARED `state` word through phases
// (PREPARE -> DISABLE_IRQ -> RUN -> EXIT) and every follower TIGHTLY SPINS
// reading that same shared word until it observes each new phase. This is
// cross-hart shared-writer visibility under concurrency -- different from
// coh_ipi64 (sequential MSIP + poll of the local mip pending bit) and from
// coh_64core (a single one-shot store broadcast). Those pass; this targets the
// actual failing pattern (hypothesis #1: a coherence/ordering race on the
// tightly-spun shared state, NOT a lost interrupt).
//
// Protocol (NHARTS harts; hart 0 = leader + verifier):
//   ROUNDS times:
//     leader:   wait until arrive_cnt == NHARTS-1 (all followers spinning on
//               this round) -> bump `state` to the next value -> spin until
//               ack_cnt == NHARTS-1 (all followers saw it) -> reset counters.
//     follower: spin-read `state` until it changes to the expected value
//               (this is the tight shared-read the race perturbs) -> record
//               progress[id] = round -> AMO ack_cnt++ -> AMO arrive_cnt for
//               next round. If a follower spins > SPIN_LIMIT without seeing the
//               update, it FAILS (stale shared read == the bug) and stops.
//   All sync counters use AMO (exclusive-ownership, coherent regardless of the
//   plain shared-state path under test). `state` itself is a PLAIN volatile
//   store by the leader / plain load by followers -- exactly the visibility
//   path multi_cpu_stop relies on.
//
// Verdict: leader pass() iff every round converged (all followers observed all
// updates). Any follower that ever read stale `state` past SPIN_LIMIT -> fail().
// finish_mask=0x1 (hart0 is leader/verifier). printf-free (Verilator UART
// unmodeled). The instrumented cmp_l15_messages_mon will self-report
// (COH_IPI64_MONFAIL ...) if the L1.5 coherence anomaly fires on this path.

#include <stdint.h>
#include "util.h"

#define NHARTS 64
#define ROUNDS 8
#define SPIN_LIMIT 6000000

// Each on its own 64B line so the leader's `state` store and the AMO counters
// live in distinct cache lines (mirrors real per-field layout; keeps the race
// on `state` visibility, not false-sharing with the counters).
volatile uint64_t state       __attribute__((aligned(64))) = 0;
volatile uint64_t arrive_cnt  __attribute__((aligned(64))) = 0;
volatile uint64_t ack_cnt     __attribute__((aligned(64))) = 0;
volatile uint64_t fail_flag   __attribute__((aligned(64))) = 0;
volatile uint64_t stuck_hart  __attribute__((aligned(64))) = 0;
volatile uint64_t stuck_round __attribute__((aligned(64))) = 0;
volatile uint64_t progress[NHARTS] __attribute__((aligned(64))) = {0};

static inline int spin_until_eq(volatile uint64_t *p, uint64_t v) {
    uint64_t c = 0;
    while (*p != v) { if (++c > SPIN_LIMIT) return 1; }
    return 0;
}
static inline int spin_until_ge(volatile uint64_t *p, uint64_t v) {
    uint64_t c = 0;
    while (*p < v) { if (++c > SPIN_LIMIT) return 1; }
    return 0;
}

int main(int argc, char **argv) {
    uint64_t id = argv[0][0];

    if (id == 0) {
        // Leader + verifier.
        for (uint64_t r = 1; r <= ROUNDS; r++) {
            // wait for all followers to be spinning on this round
            if (spin_until_ge(&arrive_cnt, NHARTS - 1)) fail();
            if (fail_flag) fail();
            for (volatile int i = 0; i < 100; i++) { }   // let them settle into the tight spin
            arrive_cnt = 0;                               // plain reset (followers already spinning on state)
            state = r;                                    // PLAIN store: advance the shared phase
            // wait for every follower to observe state==r
            if (spin_until_ge(&ack_cnt, NHARTS - 1)) {
                // some follower never saw the update -> stale shared read
                fail();
            }
            if (fail_flag) fail();
            ack_cnt = 0;
        }
        // all rounds converged
        if (fail_flag) fail();
        pass();
    } else {
        // Follower: for each round, tight-spin reading `state` until it advances.
        for (uint64_t r = 1; r <= ROUNDS; r++) {
            ATOMIC_OP(arrive_cnt, 1, add, d);   // signal "spinning on round r"
            if (spin_until_eq(&state, r)) {     // TIGHT shared read -- the race window
                stuck_hart = id;                // record who got stuck and where
                stuck_round = r;
                ATOMIC_OP(fail_flag, 1, add, d);
                while (1);                      // park; leader's spin_until_ge will time out -> fail()
            }
            progress[id] = r;                   // observed the update
            ATOMIC_OP(ack_cnt, 1, add, d);      // tell leader we saw state==r
        }
        while (1);
    }
    return 0;
}
