# Timing Closure

Strategies and issues for meeting timing constraints as core count increases.

## Current State

- AX7203 (1-core): 50 MHz core clock, 30 MHz chipset clock. Timing closes with margin.
- P3 / VP1902 Build 26 (1 OpenPiton/Ariane tile with BD-owned minimal ILA): routed on 2026-05-27 with all user timing constraints met. Post-route timing summary reported WNS 9.008 ns, TNS 0, WHS 0.010 ns, and THS 0.

## Scaling Concerns

- NoC router critical path grows with fanout at mesh edges
- L2 directory width scales with core count (more sharers to track)
- Memory controller arbitration becomes bottleneck
- Cross-SLR paths on large FPGAs add routing delay

## Techniques (TBD)

- Pipeline register insertion at SLR boundaries
- Frequency scaling (lower clock for larger arrays)
- Physical constraints / floorplanning in Vivado

## Lessons

- Keep the P3 debug ILA inside the block design when validating the Versal debug runtime path. Build 26 showed that a BD-owned `axis_ila` can route cleanly with large timing margin while preserving the PMC debug access path in the generated LTX.
