# Timing Closure

Strategies and issues for meeting timing constraints as core count increases.

## Current State

- AX7203 (1-core): 50 MHz core clock, 30 MHz chipset clock. Timing closes with margin.
- P3 / VP1902 Build 42-A (1 OpenPiton/Ariane tile with RTL SiFive TLUART, no-stack ASM UART bootrom, and two narrow BD-owned ILAs): routed on 2026-05-30 with clean route status and all user constraints met. Route status reported 147,901 routable nets, 147,901 fully routed nets, and 0 routing errors. Post-route timing reported `WNS` 9.096 ns, `TNS` 0, `WHS` 0.015 ns, `THS` 0, `WPWS` 0.063 ns, and `TPWS` 0.
- P3 / VP1902 Build 41 (1 OpenPiton/Ariane tile with RTL SiFive TLUART and three narrow BD-owned fetch/bootrom debug ILAs): routed on 2026-05-30 with clean route status and all user constraints met. Route status reported 151,701 routable nets, 151,701 fully routed nets, and 0 routing errors. Post-route timing reported `WNS` 9.105 ns, `TNS` 0, `WHS` 0.016 ns, `THS` 0, `WPWS` 0.063 ns, and `TPWS` 0.
- P3 / VP1902 Build 40 (1 OpenPiton/Ariane tile with RTL SiFive TLUART and two narrow BD-owned ILAs): routed on 2026-05-29 with clean route status and all user constraints met. Post-route timing reported `WNS` 9.084 ns, `TNS` 0, `WHS` 0.017 ns, `THS` 0, `WPWS` 0.063 ns, and `TPWS` 0.
- P3 / VP1902 Build 39 (1 OpenPiton/Ariane tile with RTL SiFive TLUART and one BD-owned ILA): routed on 2026-05-29 with clean route status and all user constraints met. Post-route timing reported `WNS` 9.084 ns, `TNS` 0, `WHS` 0.019 ns, `THS` 0, `WPWS` 0.063 ns, and `TPWS` 0.
- P3 / VP1902 Build 37 (1 OpenPiton/Ariane tile with two BD-owned live-narrow UART ILAs): routed on 2026-05-29 with clean route status and all user constraints met. Post-route timing reported `WNS` 8.964 ns, `TNS` 0, `WHS` 0.020 ns, and `THS` 0.
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
- Build 36 still timed out during hardware AxisILA access despite clean timing and routing. Timing closure alone is therefore insufficient to validate the Versal debug runtime path; each new ILA payload must be checked on hardware against a known-good image such as Build 34.
- Build 37 confirmed that returning from registered last-write capture to a live-narrow UART payload still closes route with large timing margin. Its first failure occurred after route during Versal PLM/BSP PDI generation, so timing data remains valid even though PDI recovery is required before hardware validation.
- Build 37 also passed hardware ILA capture after PDI recovery, proving that a clean route plus Build 34-style live payload preserves runtime debug access. Build 35/36 remain design-specific runtime failures tied to their registered last-write instrumentation, not generic timing or debug hub closure failures.
- Build 39 confirmed that replacing the P3 UART peripheral with the RTL SiFive/Chipyard `TLUART` and a narrow AXI4-Lite to TileLink-UL bridge does not create timing pressure in the single-core image. It routes with a much smaller debug footprint than Builds 34-37 because it uses one BD-owned ILA and removes the `axi_uart16550` IP/debug payload.
- Build 40 confirmed that adding a second narrow BD-owned ILA to the SiFive TLUART variant still routes cleanly and produces PDI/LTX directly. The debug width increase from Build 39 is therefore acceptable for the immediate core/fetch/UART-transaction isolation step, provided the probe set remains narrow.
- Build 41 confirmed that splitting the fetch/bootrom debug payload across three 64-bit-or-smaller BD-owned ILAs still routes cleanly on VP1902 and preserves the runtime debug path. This is the preferred pattern for one-more-build debug: replace narrow payload semantics across multiple ILAs instead of widening one probe block or inserting debug after synthesis.
- Build 42-A confirmed that a two-ILA no-stack UART image keeps the same healthy timing/debug-runtime profile as Builds 40-41. The hardware result is functionally negative, not timing-related: route is clean and both ILAs are accessible, but the serial path remains silent.
