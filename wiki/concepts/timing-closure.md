# Timing Closure

Strategies and issues for meeting timing constraints as core count increases.

## Current State

- AX7203 (1-core): 50 MHz core clock, 30 MHz chipset clock. Timing closes with margin.
- P3 / VP1902 Build 33 (1 OpenPiton/Ariane tile with two BD-owned chipset-focused ILAs): routed on 2026-05-28 with clean route status and positive estimated timing. Post-route timing reported `WNS` about 9.120 ns and `WHS` about 0.015 ns.
- P3 / VP1902 Build 27 (1 OpenPiton/Ariane tile with widened BD-owned RTL debug ILA): routed on 2026-05-27 with all user timing constraints met. Post-route timing summary reported WNS 17.068 ns, TNS 0, WHS 0.022 ns, and THS 0. The report still shows many no-clock and unconstrained internal endpoints, so this is not a full timing-signoff result.
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
- Build 27 showed that widening the BD-owned `axis_ila_0` can still route and generate a PDI, but the direct-flow `write_debug_probes` step may report success without leaving the expected LTX file. Reopening either the route DCP or post-route phys-opt DCP later fails inside the ILA with site routing overlap errors, so future debug builds should verify LTX existence before programming and may need a smaller probe set or different ILA implementation settings.
