# Timing Closure

Strategies and issues for meeting timing constraints as core count increases.

## Current State

- AX7203 (1-core): 50 MHz core clock, 30 MHz chipset clock. Timing closes with margin.
- P3 / VP1902 Build 36 (1 OpenPiton/Ariane tile with two BD-owned narrow UART last-write ILAs): routed on 2026-05-28 with clean route status and all user constraints met. Post-route timing reported `WNS` 9.015 ns, `TNS` 0, `WHS` 0.022 ns, and `THS` 0.
- P3 / VP1902 Build 35 (1 OpenPiton/Ariane tile with two BD-owned UART last-write ILAs): routed on 2026-05-28 with clean route status and all user constraints met. Post-route timing reported `WNS` 8.871 ns, `TNS` 0, `WHS` 0.014 ns, and `THS` 0.
- P3 / VP1902 Build 34 (1 OpenPiton/Ariane tile with two BD-owned UART-local ILAs): routed on 2026-05-28 with clean route status and all user constraints met. Post-route timing reported `WNS` 9.125 ns, `TNS` 0, `WHS` 0.011 ns, and `THS` 0.
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
- Build 33 confirmed that the two-ILA, 97-bit BD-owned payload is small enough to preserve the P3 debug runtime path and route with large margin. Future bring-up probes should stay similarly narrow and replace payload content between builds instead of accumulating more probes.
- Build 34 confirmed that the same 97-bit structure still routes cleanly after swapping in UART-local payload content. The next UART bring-up builds should continue replacing selected payload bits rather than increasing total probe width.
- Build 35 preserved the Build 34 97-bit debug width and only changed payload semantics to sticky UART last-write capture. It routed cleanly, confirming that replacing payload semantics without increasing probe width remains the right pattern for P3 bring-up.
- Build 36 confirmed that preserving the Build 34 chipset status-byte wrapper while packing the UART last-write payload into the wrapper-preserved 56-bit field also routes cleanly. This is the preferred pattern after Build 35's hardware AxisILA timeout on the raw 64-bit wrapper-bypass variant.
