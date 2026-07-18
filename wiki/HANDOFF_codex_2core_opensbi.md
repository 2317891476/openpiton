# Handoff: 2-core OpenSBI cold-boot banner hang (OpenPiton+Ariane, P3/VP1902)

**Date**: 2026-07-13
**From**: Claude Code session → **To**: Codex
**Scope**: Pick up the 2-core (2x1) OpenSBI bring-up. The board boots bootrom fully but OpenSBI prints no banner. Root-cause + fix + verify.

This doc is self-contained. Read it fully before acting. All key facts, paths, hashes, and commands are here.

## Current Build 87 implementation gate -- 2026-07-18

The third Build 87 ECO attempt successfully created and rewired the complete
70-cell implementation, including the `csr_addr==0xc01`, commit-valid, and
CSR-FU qualification.  It stopped before placement because Vivado Advanced
Flow rejects the legacy `place_design -post_place_opt` option with
`Vivado_Tcl 4-2312`.  This means the earlier segmented-net repair is validated,
but no Build 87 DCP/LTX/PDI exists yet.  Replace only the unsupported placement
step with an Advanced-Flow-supported ECO placement path, require locations for
all 70 cells, and retain the existing `route_design -eco` plus signoff gates.

## Current boundary after Build 86 -- 2026-07-18

Build 86 retires the Build 84/85 interpretation that Linux is permanently
blocked at the `timekeeping_update` FENCE.  Its committed-store queue capture
shows the `0x81485280` store accepted with request/grant `1/1` and removed from
the queue on the next cycle.  Three later complete-PC snapshots contain
333/393/393 distinct PCs, proving continued execution.

The full sequence is now resolved:

`Linux udelay rdtime` -> `_trap_handler` -> `sbi_trap_handler` ->
`sbi_illegal_insn_handler` -> `sbi_emulate_csr_read` -> `mtimer_time_rd64` ->
`mret`.

The decisive Linux PC is `0xffffffff807d8a9e`; representative OpenSBI PCs are
`0x8000ceb8`, `0x80016992`, `0x80021744`, `0x80021c6c`, and the trap return at
`0x800004f4/0x800004fc`.  One software-emulated `rdtime` consumes roughly 800
commit-PC samples, which explains why UART appears stopped even though the
core is live.

The RTL cause is `piton/design/chip/tile/ariane/core/csr_regfile.sv`: it has
read cases for CYCLE/INSTRET but none for TIME/TIMEH.  Build 80 measured
`mcounteren=0x3f`, so `TM=1`; the trap is not an access-permission failure.
Instead, legal S-mode `rdtime` reaches the missing-CSR default and becomes an
illegal instruction that OpenSBI emulates by reading CLINT `mtime`.

Build 86 artifacts are PDI SHA-256 `de9d6ed2...f386e`, LTX SHA-256
`85a1f33a...346d`, and pre-route DCP SHA-256 `64c45881...b680`.  Programming
reported `DONE bit: HIGH`, debug hub `0x3ffc0000000`, and four ILAs.  The
current UART log is
`~/p3_uart_logs/ttyUSB0_20260718_085314_build86_store_queue.log`.

Next action is Build 87, a single-hart causal functional ECO that returns
`cycle_q >> 7` for CSR `0xc01`, matching P3's 30 MHz / 128 = 234375 Hz
timebase, and clears the illegal result for that address.  The equivalent
tracked RTL is guarded by `P3_TIME_CSR_DIV128`, with a printf-free `rdtime_p3.c`
regression.  This does not yet claim the final 64-hart shared-time
architecture: a true CLINT `mtime` path from chipset to every tile needs an
explicit 64-bit CDC/coherent-snapshot design.  Do not rewrite the SD card for
Build 87; only the PDI changes.

## Current boundary after Build 83 -- 2026-07-18

Build 82 produced two different pieces of evidence.  Its synchronized trigger
fired too early in bootrom and captured a healthy store-response control: four
stores crossed request acceptance, adapter `L15_ST_ACK`, write-buffer return
ID, and `evict`, ending with an empty write buffer.  A later fault-state
snapshot was much narrower: the write-buffer return FIFO held TID 0 while slot
0 was invalid and only slot 1/entry 3 remained valid and transaction-blocked.
Because RTL indexes `tx_stat_q` with the FIFO head ID, that orphan TID selects a
stale slot and cannot evict entry 3.  This proves a return-ID/active-slot
mismatch state in that run, not yet whether the source is a duplicate ACK, late
ACK, or TID corruption.

Build 83 targeted the first occurrence of that exact mismatch.  It is fully
routed, timing-clean, and board-programmed:

- PDI `D:/p3b83_orphan_return_eco/p3_top_build83_orphan_return_eco.pdi`,
  SHA-256
  `0901f52c19b3cf0361be3b4e94cd5a87900bda4dc5d1383acc014f6231982559`;
- LTX `D:/p3b83_orphan_return_eco/p3_top_build83_orphan_return_eco.ltx`,
  SHA-256
  `8e71b940b6f7ad87e3f1eecb4a7c43ea1b3c15d1982b2166de615a17871cf398`;
- implementation: 151,470/151,470 routable nets, zero routing errors,
  WNS/WHS `16.514/0.013 ns`, baseline 169 warning-class DRCs only;
- programming: `DONE bit: HIGH`, debug hub `0x3ffc0000000`, four ILAs.

UART0 again reached the complete OpenSBI summary and stayed at 61,072 bytes;
log `~/p3_uart_logs/ttyUSB0_20260718_024928_build83_orphan_return.log`,
SHA-256
`0155bf298bd87f977bead62ce876848154f719cb86e0386c82e280236f8fe521`.
However, the synchronized `readptr=0/TID=0/slot0-invalid` trigger did not fire
during a complete uninterrupted 1800-second arm.  Trigger-now snapshots taken
throughout the run show changing, normally matched store-return and evict
activity for at least an hour after UART stopped.  Thus UART silence is not a
core-stop proof, and the Build 82 orphan is not the reproducible active blocker
in this Build 83 run.

Next action: restore full commit PC plus commit valid/ack/FU/op and
privilege/exception state, then take repeated progress snapshots.  The goal is
to distinguish slow Linux execution from a stable software livelock or a
console-only failure.  Do not continue deepening the return-ID path unless a
new run actually reasserts an orphan condition.  Build 83 scripts and the
Build 82 decoder trigger-index fix are in commit `5dbcdd9`.

## Build 82 board result -- 2026-07-18

Programming succeeded with `DONE bit: HIGH`, the expected debug hub, and four
ILAs.  UART0 log
`~/p3_uart_logs/ttyUSB0_20260718_012036_build82_store_return.log` is 61,072
bytes with SHA-256
`0155bf298bd87f977bead62ce876848154f719cb86e0386c82e280236f8fe521`.
The synchronized CSVs triggered at sample 128 in bootrom PC
`0x000000fff1010572` and show a healthy response path, not the Linux failure.
Their hashes are `4cc60f5b...`, `e7bcb383...`, `144fd4fd...`, and
`f0094373...`.  A late snapshot then exposed the orphan TID0/invalid-slot0
state described above; its hashes are `d691abc2...`, `f0ec46c4...`,
`44d40023...`, and `b44d708e...`.

## Build 82 store-response boundary ECO ready -- 2026-07-18

Build 82 is generated and ready for the causal board capture.  It is a
probe-only ECO from Build 81 and changes no functional hardware or SD payload.
The common trigger is transaction slot 1 valid rising; trigger position 128
leaves roughly 896 cycles to observe the response after the second slot is
allocated.  Arm all four ILAs in one call during bootrom SD copy, not after the
UART stop.

Artifacts:

- PDI `D:/p3b82_store_return_eco/p3_top_build82_store_return_eco.pdi`,
  SHA-256
  `90de3776572b8033f4a63f8eb723bafcd06ce77ba6d5d919f86ee21def1e0ba7`;
- LTX `D:/p3b82_store_return_eco/p3_top_build82_store_return_eco.ltx`,
  SHA-256
  `98ad8c42fbc5e96afe8dae3e62dfdad524968743d9bd565bcde106e8c3171742`;
- `scripts/p3_ila_capture_build82_store_return_eco.tcl`;
- `scripts/p3_decode_build82_ila_csv.py`.

Implementation is fully routed with zero routing errors and formal
WNS/WHS=16.514/0.013 ns.  The decoder distinguishes the first missing edge
across request FIFO acceptance, adapter `L15_ST_ACK` ingress/egress, missunit
store-return forwarding, and write-buffer return-ID/evict.  Direct
`miss_rtrn_vld[2]` is optimized away in the implemented checkpoint, but the
write-buffer return FIFO pointer/occupancy provides an equivalent downstream
boundary.  Build 82 is not board-tested yet.

## Build 81 board result -- 2026-07-17

Build 81 has been programmed with `DONE bit: HIGH`, debug hub
`0x3ffc0000000`, and four ILAs.  UART0 completed the full 65,536-block copy and
OpenSBI summary, then remained at 61,072 bytes; the log is
`~/p3_uart_logs/ttyUSB0_20260717_203603_build81_wbuffer.log`, SHA-256
`0155bf298bd87f977bead62ce876848154f719cb86e0386c82e280236f8fe521`.

Two complete Build 81 snapshot sets about seven minutes apart are
byte-for-byte identical.  Each field is also stable for 1024/1024 samples.
The persistent write-buffer state is:

- entry0 dirty bytes `ff`;
- entry2/3 transaction-blocked bytes `ff/ff`;
- both transaction slots valid, pointers 3 and 2, byte enables `ff/ff`;
- zero free transaction slots and no `miss_req`, allocation, tag-check, or
  evict activity;
- committed-store queue empty, WT write buffer non-empty.

The head PC `0xffffffff801413d0` resolves to
`__rmqueue_pcplist+0x94`, but commit valid/ack is 0/0, so it is not evidence
that the `mv a0,s5` instruction is currently blocking.  This run did not
retain the Build 80 FENCE at a valid commit head.

The RTL interpretation is narrower and stronger than a generic cache stall:
two previously accepted WT stores have allocated both transaction slots, but
their return IDs never reach the write-buffer `evict` path.  This permanently
blocks the remaining dirty entry because `free_tx_slots=0`.  The next probe
boundary is the store response chain:
`L15_ST_ACK` -> L15 adapter return FIFO -> D-cache `DCACHE_STORE_ACK` and TID ->
write-buffer return-ID FIFO/evict.  Current evidence does not yet identify
which edge loses the response, so L1.5 generation, adapter delivery, and
return-ID routing remain separate hypotheses.

The four CSV hashes (ILA0 through ILA3, identical for both sets) are:

- `162ece71b2dc36ca46386218145f62676dffb3dad4b703ebf050e340774a444e`;
- `24c6585c15f52c016639cc82726cbae10f8de8ab95a8e31e930b10e53bf39504`;
- `6d1a2c43053118ee88639aa3b7d56207060d80c0a576525a95109927640b1864`;
- `d652bd86de7e20f2b4a4d0c42424f385a449166a0a463de1a4222211b7c14eaf`.

## Build 81 WT D-cache write-buffer ECO ready -- 2026-07-17

Build 80's later persistent-state snapshot advances beyond the initial SBI
ECALL capture.  It is stable for 1024/1024 samples at Linux commit PC
`0xffffffff80075e40`, `timekeeping_update+0x104`, instruction `fence w,w`,
with commit valid/ack 1/0, `no_st_pending_ex=1`,
`dcache_commit_wbuffer_empty=0`, and WFI 0.  Thus the current FENCE waits on a
non-empty WT D-cache write buffer.  Historical `mepc/mcause/mtval` values in
that snapshot describe an earlier emulated `rdtime`, not a current trap loop.
The earlier S-to-M capture itself resolves to Linux `sbi_get_mvendorid` with
SBI BASE extension/function `a7=0x10`, `a6=4`; it returned before this later
Linux stop.

Build 81 changes only existing ILA probe loads.  It preserves ILA0's full
commit PC, uses ILA1/2 for all eight entries' dirty and txblock byte masks, and
uses ILA3 for the commit/FENCE gates, entry checked state, both transaction
slots, and write-buffer allocation/check/eviction progress.  It does not
change the functional Build 66 hardware or the SD payload.

Artifacts:

- PDI `D:/p3b81_wbuffer_eco/p3_top_build81_wbuffer_eco.pdi`, 11,972,784
  bytes, SHA-256
  `18de4d2e111665c0c02c0ac3e587e10b687a9f4d74ab64ecb526bf437da77e0a`;
- LTX `D:/p3b81_wbuffer_eco/p3_top_build81_wbuffer_eco.ltx`, 204,077 bytes,
  SHA-256
  `90a6096c94e5de6a342e4b75c224f9ad0773cb1eea091cc3a15a0eed38043b83`;
- restart DCP SHA-256
  `600b57a631f05cb3de1abd12a7f1830c7e37124d18de34df3c212597ee6724e9`;
- `scripts/p3_build81_wbuffer_eco.tcl` and
  `scripts/p3_ila_snapshot_build81_wbuffer_eco.tcl`;
- `scripts/p3_decode_build81_ila_csv.py`, which classifies an unaccepted dirty
  request versus a transaction that remains in flight.

Implementation is fully routed with zero routing errors, formal
WNS/WHS=16.514/0.013 ns, and all timing constraints met.  The first attempts
hit `Route 35-4579` when ILA loads touched the legacy `p3_dbg_core_bus`
synchronizer cone and forced a BUFG topology update.  The final route removes
that cone completely and uses duplicate local checked-state Q bits as safe
fillers; the decoder cross-checks the duplicates.  Build 81 is generated but
not yet board-tested.  Program this exact PDI/LTX pair, wait for the UART stop,
run the Build 81 snapshot Tcl, and decode the four resulting CSV files before
claiming the precise write-buffer substate.

## Build 80 board result -- 2026-07-17

Build 80 has now been programmed and synchronously captured.  Programming
reported `DONE bit: HIGH`, debug hub `0x3ffc0000000`, and four ILAs.  UART
covered the complete 65,536-block copy, `done!`, OpenSBI v1.8, and its full
platform/domain summary.  The four 1024-sample ILA CSVs all have trigger index
512 and identical common-trigger waveforms.

The captured S-to-M transition is a normal S-mode ECALL, not the suspected
TIME CSR denial: the S-mode commit PC is `0x80207bf4`; the M-mode state is
`mepc=0x80207bf4`, `mcause=9`, and `mtval=0x00000073`.  CSR address is zero,
the CSR-illegal condition is low, and `mcounteren=0x3f`, including
`mcounteren.TM=1`.  Retire the `rdtime`/`mcounteren.TM=0` root-cause hypothesis.

OpenSBI remains active after entry rather than freezing immediately: the next
512 cycles contain 275 commit-valid samples, 35 commit-ack samples, and 41
distinct PCs, all in M-mode.  The current boundary is therefore normal Linux
SBI ECALL dispatch/handling that has not returned to S-mode within the capture
window.  Resolve the post-trigger PC sequence against the exact Build 66
OpenSBI ELF and identify the ECALL extension/function arguments before
choosing another ECO or software change.

## Build 80 trap/CSR ECO ready -- 2026-07-17

The next causal diagnostic described below has now been built, but not yet
programmed.  Build 80 reuses the Build 66 functional design and debug hub from
the Build 79 pre-route checkpoint; it changes only the loads on the four
existing, synchronous ILAs.  It captures the full commit PC, recoverable full
`mepc`, `mcause`, illegal-instruction `mtval`, implementation-level CSR
address, commit FU/op/valid/ack, privilege, `mcounteren`, and WFI/interrupt
context.  All four ILAs duplicate `priv_lvl_q[1]` as an S-to-M rising-edge
trigger.

Artifacts:

- `D:/p3b80_trap_csr_eco/p3_top_build80_trap_csr_eco.pdi`, 11,972,000 bytes,
  SHA-256 `60de526cdaa5876b8cbb71c2506c0a431317efa89f0a009b931571cb65576123`;
- matching `.ltx`, 203,673 bytes, SHA-256
  `1741b94f7727bb2329b88cf719979c014386bca6ff1e72bdd8f5cfdea75f6001`;
- `scripts/p3_ila_capture_build80_trap_csr_eco.tcl` for one-call synchronized
  arming and CSV export;
- `scripts/p3_decode_build80_ila_csv.py` for LTX-position-based decoding and
  CSR-instruction/address cross-checking.

Implementation is fully routed with zero routing errors and formal
WNS/WHS=16.514/0.013 ns.  The board programming/capture action originally
listed here is complete; its result is the ECALL evidence above.  No SD-card
rewrite or repeated Build 80 programming is required for that conclusion.

## Current evidence correction -- 2026-07-17

The latest single-hart board state is Build 79 running the readback-verified
Build 66 OpenSBI/Linux 6.6 SD image.  A new live ILA snapshot on 2026-07-17,
taken without resetting or reprogramming the FPGA, proves that the core is not
statically hung: `commit_valid=1` in 517/1024 samples, `commit_ack=1` in
444/1024, `wfi_q=0` throughout, and the L1.5 request/history bus is active with
no L1.5 or DDR response error.

This supersedes the 2026-07-16 devlog claim that Build 79 captured
`commit_valid=0 (1024/1024)` and therefore a commit-stage stall.  Recounting
that original CSV gives 467 commit-valid and 429 commit-ack samples.  The old
UART capture also ended during bootrom SD copy at 74%, before `done!`, OpenSBI,
or Linux, so it did not synchronize the later ILA with a UART-confirmed final
stop.

Both the original and current Build 79 ILA2 captures show the same circular
privilege pattern: 907 M-mode samples and one contiguous 117-sample S-mode
interval.  The current L1.5 history repeatedly fetches OpenSBI
`_trap_handler_hyp` (`0x80000520`) and `sbi_emulate_csr_read()`
(`0x80021940`) and reads CLINT `mtime` at `0xfff102bff8`.  During the capture,
CSR pending interrupt bits and wrapper timer/IPI/external/debug inputs are all
low.  The strongest current interpretation is an active synchronous
S/M trap/CSR-emulation loop, not WFI, a pending interrupt, a persistent store
request, or a commit deadlock.  The exact S-mode instruction and trap cause
remain unproven because Build 79 does not probe PC, mcause, mepc, mtval, or the
decoded CSR number.

The Build 79 probe map is also wrong for probe0[45:46].  The ECO reconnects
only [28:44], so [45:63] retain Build 78 diagnostic indices 17 through 35;
[45] and [46] are not `no_st_pending_ex` and
`dcache_commit_wbuffer_empty`.  Do not infer a drained store path from those
bits.

That minimal experiment is now the generated Build 80 artifact described
above.  Do not start the previously proposed commit-kill/flush ECO until its
synchronized board capture resolves the trap boundary.  The detailed
append-only correction, build attempts, artifact hashes, and route/timing
evidence are in `wiki/devlog/2026-07.md` under 2026-07-17.  The older Build 75
preparation text below is historical and has been superseded by completed
Builds 75 through 80.

## Resolution update -- 2026-07-13

The controlled Build 73 probe stopped after marker W; the otherwise equivalent
no-CSR image printed II[SHDMWRTEPB, OpenSBI v1.8, and Linux early console.
This proves the CSR 0x701 D-cache-disable mode change blocks the two-hart
cold-boot path. Historical Build 68 dbg23 evidence shows the same mode also
froze the 64-hart board immediately after the OpenSBI jump, so this is not a
two-hart limitation. The superseded greater-than-two-hart gate must not be
used: the clean P3 OpenSBI patch now keeps L1 D-cache enabled for every hart
count. Exact transaction-level RTL failure remains open.

### Single-hart control reproduces the later L1.5 S1 acceptance stop -- 2026-07-15

The requested one-hart hardware control used the unchanged validated Build 66
PDI, not a newly synthesized 1x1 design.  Windows full Vivado 2024.2.2
programmed it through the remote hw_server/XVC chain with `DONE bit: HIGH`,
debug hub `0x3ffc0000000`, and four ILAs.  The new flat SD image then passed
Build 66's fixed 65,536-sector copy path and printed `done!`; OpenSBI v1.8
reported one hart, `aclint-mtimer @ 234375Hz`, next address `0x80200000`, and
FDT argument `0x81600000`.  UART stopped after the complete OpenSBI platform
summary, before a Linux banner.  The logs are
`~/p3_uart_logs/ttyUSB0_20260715_170943_build66_1hart_opensbi.log` (27,226
bytes) and
`~/p3_uart_logs/ttyUSB0_20260715_171943_build66_1hart_opensbi_cont.log`
(33,762 bytes).

A non-resetting ILA capture showed `p3_dbg_core_bus64=0x008189b7800bf487`:
address `0x8189b780`, request type `1` (ordinary store), size `3` (8 bytes),
and handshake byte `0x87`.  Correctly decoded, bit 7 has
`transducer_l15_val=1` while the actual request acknowledgement, bit 4
`l15_transducer_ack`, is 0.  Heartbeat and resets are live; no sticky L1.5,
DDR BRESP, or DDR RRESP error is set.  Ariane status `0xf4` has the timer
pending but IPI, external IRQ, and debug request all low.

This reproduces the same observable L1.5 S1 acceptance/backpressure class as
the Build 73 two-hart store at `0x8185dc80` without a second hart or IPI.  SMP
or IPI concurrency is therefore not a necessary trigger.  Do not overstate
the result as a transaction-level root cause: the retained ILAs still cannot
separate matched-MSHR/tag conflict, S2/S3 or same-index backpressure, exhausted
MSHRs, or unavailable NoC1 command/data credits.  The software phases also
differ (the one-hart run stops before the Linux banner, while the two-hart
`mem=1G` run reached later init), so the common claim is limited to the stable
store-valid-without-L1.5-ack state.

### Build 75 causal diagnostic prepared -- 2026-07-15

Build 75 is the next hardware action and replaces further inference from the
four aggregate Build 66 ILAs.  A synthesized Build 66 DCP inspection found
that the CVA6 commit-head PC/FU/op, LSU commit state, and aggregate L1.5 stalls
survive synthesis, while the individual tag/index/MSHR/NoC1 blockers do not.
The diagnostic consequently requires a fresh one-hart synthesis with
conditional `P3_BUILD75_PC_L15_DEBUG` retention in `l15_pipeline.v.pyv`.

`scripts/p3_build75_1hart_l15_pc_diag.tcl` drives the self-contained Build
52-derived flow.  Its post-synthesis hook requires exact, unique probe paths
and inserts `u_ila_build75` at depth 8192.  The trigger fires after an ordinary
store has remained valid without the real L1.5 acknowledgement for 256 cycles;
the capture also contains the request fields, detailed stage/tag/index/MSHR and
NoC1 credit blockers, commit-head PC/FU/op/valid/ack, and LSU commit readiness.
Build and decode with:

```bash
vivado -mode batch -source scripts/p3_build75_1hart_l15_pc_diag.tcl \
  -tclargs -jobs 16
vivado -mode batch \
  -source scripts/p3_ila_capture_build75_1hart_l15_pc_diag.tcl
python3 scripts/p3_decode_build75_ila_csv.py \
  huaprop3_build75_1hart_l15_pc_diag/debug_build \
  --vmlinux build/p3_64core/riscv64-linux-64core-src-20260610/linux/vmlinux
```

The decoder is fail-closed: it will not report a stuck instruction unless the
`0x75` format tag, 256-cycle store/no-ack condition, valid CVA6 STORE commit
head, and a concrete L1.5 blocker all agree.  No Build 75 PDI/LTX, board
programming result, capture, or exact instruction exists yet.  Keep the
readback-verified one-hart OpenSBI/Linux 6.6 image on the SD card unchanged.
Do not create the excluded OpenSBI/Linux 5.1 control image and do not repeat
the unchanged failing Build 66/OpenSBI/Linux 6.6 baseline.

The first clean-tree Build 75 attempt stopped before synthesis during project
creation.  Bootrom and the forced tile/L1.5 PyHP outputs passed, but an
unrelated missing `bram_sdp_wrapper.tmp.v` caused the legacy Windows Vivado
helper to execute Unix `pyhp.py` directly and fail.  The P3 create flow now
pre-generates every missing RTL/include PyHP result through WSL `python3`
before calling that helper.  This failure produced no PDI/LTX and no board
evidence; rerun the same Build 75 command from the new clean commit.

The second zero-generated-file attempt proved that PyHP fix, then exposed a
second clean-source gap before synthesis: Build 66 regenerated only
`bootrom_linux.sv`, although `riscv_peripherals.sv` unconditionally
instantiates both Linux and baremetal ROM modules.  The Build 66 rebuild now
also creates `baremetal/bootrom.sv` from an inline minimal DTS and validates
its module name.  The self-contained preflight requires both ROMs in the
snapshot.  That interrupted attempt also produced no PDI/LTX or board result.

### Timer-frequency fix verified on the FPGA -- 2026-07-13

All retained P3 OpenSBI logs, including the reliable 64-hart shell run and the
current two-hart run, reported the stale platform fallback
`aclint-mtimer @ 1000000Hz`; P3 hardware and every relevant DTB use 234375 Hz.
The cause was initialization order: timer registration copied the fallback
before platform `early_init` parsed the DTB.  This was a long-lived OpenSBI
platform bug, not a regression caused by removing CSR 0x701, and the historical
64-hart shell result shows it is not by itself sufficient to explain the later
two-hart Linux-early stop.

Commit `adcb11f` moves the DTB frequency parse into the OpenPiton timer callback
before mtimer cold initialization and makes the preparation flow reject stale
work trees.  Two clean builds produced identical firmware SHA-256
`69d3549ff1ada4faa09666247126b22656d32c9d8cc66ad79a4f5be018e00b7d`.
The prepared 256 MiB image is
`build/huaprop3/opensbi64/p3_opensbi_linux_2hart_timerfix.img`, SHA-256
`c420d81dcbec5f637d8ebcdeb5fab8f5aaba16badc2ee49d2797c096f334f55e`.
It preserves the prior Linux, two-hart DTB, and initramfs byte-for-byte and is
already uploaded and hash-verified at
`illya@100.93.77.36:/tmp/p3_opensbi_linux_2hart_timerfix.img`.

The image is now on the SD card.  Immediately before writing, `/dev/sdc` was
revalidated as the expected unmounted 31,914,983,424-byte USB removable disk,
model `Multi-Reader -1`.  All 268,435,456 bytes were written, synchronized and
flushed, then the same complete 256 MiB span was read back.  Its SHA-256 was
`c420d81dcbec5f637d8ebcdeb5fab8f5aaba16badc2ee49d2797c096f334f55e`,
exactly matching the candidate image; the reread partition table exposed
`/dev/sdc1` at 267,369,984 bytes.

Board validation is now complete for the timer fix.  A persistent capture at
`~/p3_uart_logs/ttyUSB0_20260713_202255_build73_timerfix.log` was running
before local Windows full Vivado 2024.2.2 programmed the unchanged Build 73
PDI through the remote hw_server/XVC path.  Vivado exited zero with
`DONE bit: HIGH`, debug hub `0x3ffc0000000`, and four ILAs.  The bootrom passed
DDR, SD, GPT/`P3OS`, and all component copies; OpenSBI v1.8 then printed
`Platform Timer Device : aclint-mtimer @ 234375Hz`.  This is direct FPGA proof
that commit `adcb11f` fixes the stale 1 MHz timer registration.

OpenSBI also handed off to Linux 6.6.0, which detected SBI TIME/IPI/RFENCE and
the early UART console.  The 39,980-byte log remained unchanged for 91 seconds
after the two reserved-memory lines at `[0.000000]`; no SMP or shell result is
claimed.  Do not rewrite this card or rebuild the timer fix for that symptom.
The next work is the separate Linux-early internal-stall investigation,
ideally with a single-CPU bootarg discriminator or a probe exposing
PC/timer/IPI state.

### Linux-early DDR aperture mismatch -- 2026-07-13

Static inspection of the exact self-contained source used by the programmed
PDI found a definite Build 73 configuration error.  The XPR points to
`p3b73_2x1_diag/source_snapshot/piton/design/chip/tile/rtl/tile.tmp.v`, whose
`ExecuteRegionLength` and `CachedRegionLength` are both `0x40000000`.  CVA6
therefore regards only the first 1 GiB at `0x80000000` as executable and
cacheable.  In contrast, both
`piton/design/xilinx/huaprop3/devices_ariane.xml` and the current two-hart DTB
declare 2 GiB (`0x80000000` bytes), ending at `0xffffffff`.  Validated Build 66
and Build 67 snapshots contain the correct `0x80000000` CVA6 lengths; Build 72
and Build 73 contain the same stale 1 GiB `tile.tmp.v` hash.

A new immediate ILA capture, which did not reset or reprogram the FPGA, ties
the mismatch to the live symptom.  The retained last L1.5 address is
`0xffe5e000`, in the incorrectly classified upper GiB, and the DDR-side
translation is `0x7fe5e000`.  Across 1024 samples the core repeatedly performs
the same 8-byte load with accepted requests and returned responses; no L1.5 or
DDR error is present.  The previous statement that the core was completely
internally stalled is therefore too strong.  It is repeatedly polling or page
walking the same upper-RAM location.

The UART boundary is also consistent: after the final reserved-memory print,
Linux enters `setup_vm_final()`, allocates/fills final page tables, builds the
linear map, switches `satp`, and flushes the TLB without intervening console
messages.  The timer, IRQ, and SMP initialization stages are later, so this is
independent of the verified 234375 Hz OpenSBI timer correction.

The generation defect is in the Build 52-derived flow: its forced PyHP list
does not include `piton/design/chip/tile/rtl/tile.v.pyv`, and
`p3_create_bd.tcl` reuses a pre-existing `.tmp.v` when its timestamp is newer
than the template without checking the device-map context.  Treat the DDR
aperture mismatch as a confirmed configuration bug and high-confidence current
root-cause candidate, not fully causal-closed until one of these controls
passes:

1. Keep Build 73 programmed and boot a DTB/command line limited to `mem=1G`.
2. Build a corrected PDI after regenerating `tile.tmp.v` in the HuaPro P3
   context, with snapshot preflight assertions that both lengths equal
   `0x80000000`, then boot the current timer-fix SD card unchanged.

Flow repair committed on 2026-07-15: the common Build 52-derived runner now
forces `tile.v.pyv` regeneration and validates both live and self-contained
`tile.tmp.v` execute/cacheable ranges against the P3 device map.  Reusing the
old Build 73 snapshot now fails closed; a newly created project will contain
the required 2 GiB apertures.  The OpenSBI image path also derives its DTB
memory/peripheral nodes from the same device map, computes initrd bounds from
the actual rootfs, derives `234375` Hz from `30 MHz / 128`, and validates DTB
and bundle ranges before packing.  Software-only 2-hart and 64-hart complete
flow tests pass, but no corrected PDI or new board result has yet been
produced.

Do not rebuild OpenSBI, reopen the timer-frequency issue, or rewrite the current
card as part of the formal PDI repair.

### Prepared `mem=1G` SD-image control -- 2026-07-13

The image-only A/B control is built and remotely staged.  It reuses the exact
board-tested timer-fix OpenSBI, Linux Image, and initramfs.  Its DTB keeps the
real 2 GiB `memory` node and appends only `mem=1G` to `/chosen/bootargs`.
RISC-V Linux calls `parse_early_param()` before `paging_init()`, so
`setup_bootmem()` and `setup_vm_final()` are restricted to physical
`0x80000000` through `0xbfffffff`; OpenSBI's view of the hardware is unchanged.

Artifacts:

- Local and remote image:
  `p3_opensbi_linux_2hart_timerfix_mem1g.img`, 268435456 bytes, SHA-256
  `7a61b8e7426a79f628b84331faec0642ae722e745ea11905f78419b56a5e60d9`.
- Local and remote DTB: `p3_opensbi_2hart_initrd_mem1g.dtb`, 2228 bytes,
  SHA-256
  `17bfda300c2298ef3bd78391f4c6b627503df4da8e57c57330e8623da2e97c73`.
- Remote paths are `/tmp/<basename>` on `illya@100.93.77.36`; the manifest is
  also staged there.  Full remote hashes match local values.

GPT/P3OS validation parsed all four header entries and read their exact byte
ranges back from the finished image.  Load addresses remain OpenSBI
`0x80000000`, Linux `0x80200000`, DTB `0x88000000`, and initrd `0x90000000`.
The non-DTB component hashes are unchanged: `69d3549f...` (OpenSBI),
`47c9daa8...` (Linux), and `60aaf85d...` (initramfs).  The DT retains two CPUs,
234375 Hz, 2 GiB physical memory, and initrd end `0x90107d9c`.

The card still contains the prior timer-fix image and remains in the FPGA.
Before writing this control, move it to the reader and revalidate the removable
disk identity.  After returning it to the FPGA, keep the Build 73 PDI unchanged
and require UART evidence of both `mem=1G`/`Memory limited to 1024MB` and
progress beyond the reserved-memory boundary.  A successful boot proves the
upper-GiB-use discriminator; it does not replace the later corrected-PDI test.

### Board result for the `mem=1G` control -- 2026-07-15

The control is now board-verified.  The SD write and full 256 MiB readback
matched image SHA-256
`7a61b8e7426a79f628b84331faec0642ae722e745ea11905f78419b56a5e60d9`.
The unchanged Build 73 PDI programmed with `DONE bit: HIGH`, debug hub
`0x3ffc0000000`, and four ILAs.  The valid UART log is
`~/p3_uart_logs/ttyUSB0_20260715_155614_build73_mem1g_boardreset.log`
(94097 bytes).  It shows DDR/SD/GPT/all-component-copy success, OpenSBI v1.8,
`aclint-mtimer @ 234375Hz`, `Memory limited to 1024MB`, and the kernel command
line containing `mem=1G`.

Linux crossed the previous reserved-memory/`setup_vm_final()` silent boundary,
reported `992124K/1048576K available`, executed many initcalls, and reached
`Freeing initrd memory: 1052K`.  This closes the image-only discriminator:
upper-GiB use or the extra mapping triggers the old stop.  It does **not** yet
prove that the stale CVA6 aperture is the complete transaction-level cause;
the required formal closure remains a corrected PDI with
`ExecuteRegionLength=CachedRegionLength=0x80000000` booting the unbounded
timer-fix image.

The control exposed a later, separate stop before shell.  The last UART region
contains `calling pty_init` followed by the asynchronous initrd-free message;
do not name `pty_init` as the root cause from printk ordering alone.  A live
ILA capture recorded `p3_dbg_core_bus64=0x008185dc800cf687`: L1.5 address
`0x8185dc80` (within the low 1 GiB), request type `1` (store), size `4`, and
handshake byte `0x87`.  Correct signal-direction decode: bit 7 has
`transducer_l15_val=1` and the actual request acknowledgement, bit 4
`l15_transducer_ack`, is 0.  Bit 6 `transducer_l15_req_ack=0` acknowledges an
L1.5 **return** packet into Ariane's return FIFO and is expected here because
bit 5 `l15_transducer_val=0`; it is not the request-accept signal.  Ordinary
stores use `L15_ACK_STAGE_S1`, so this persistent valid-without-ack state
localizes the stop to the L1.5 S1 acceptance/backpressure path.  The current
ILA cannot distinguish matched-MSHR/tag conflict, S2/S3 or same-index
backpressure, exhausted MSHRs, or unavailable NoC1 command/data credits.
Timer and IPI were pending (`ariane_hi=0xf6`), but those are simultaneous
observations rather than proven causes, and no L1.5 or DDR response error was
asserted.  Treat this as a later store-accept/forward-progress issue needing
the L1.5 stall vector plus hart/PC, or a `maxcpus=1` control, not as a failure
of the timer repair or the `mem=1G` discriminator.

---

## 1. Project context (do not lose)

**Ultimate goal**: Run Quicksilver on a 1000-core OpenPiton manycore, measure parallel speedup. Phases P0(1c)→P4(1024c).

**Current phase**: 2-core (2x1) bring-up as a controlled experiment vs the working 64-core (8x8) path. Target board: **P3 / Versal VP1902** (remote).

**Working reference**: 64-core (Build 68/69 era, dbg21 fw) reliably reached an interactive Linux shell with `nproc=64` on this same board. OpenSBI prints its banner there.

**The 2-core regression**: bootrom runs to completion and jumps to OpenSBI at `0x80000000`, but **OpenSBI prints no banner** (UART goes permanently silent). This blocks all 2-core progress.

---

## 2. What is PROVEN working on 2-core (do NOT re-debug these)

Verified on the 2-core board (Build 73 diag bootrom, 2026-07-13):

| Path | Evidence | Status |
|------|----------|--------|
| UART TX/RX | bootrom banner + progress lines; 16550 LSR poll reads succeed | ✅ GOOD |
| DDR read/write | `B69 DDR probe addr=0x84001000 → B69 DDR OK` | ✅ GOOD |
| SD data read | bootrom reads GPT + copies OpenSBI(528)+Linux(38831)+dtb+initrd | ✅ GOOD (after re-seating card — see §5) |
| bootrom handoff | `jump fw=0x80000000 dtb=0x88000000`, a0=mhartid, a1=fdt | ✅ GOOD |
| io_xbar / NoC fabric | DDR + UART reads return; 9-port io_xbar incl. SD | ✅ GOOD |
| PDI / debug hub | DONE bit HIGH, debug hub `0x3ffc0000000`, 4 ILAs live | ✅ GOOD |

**The hang is squarely inside OpenSBI cold boot, after the jump.** Everything below the jump is clean.

---

## 3. The exact blocker + board evidence already in hand

**Symptom**: after `B69 jump fw=0000000080000000`, UART goes silent forever (no `OpenSBI v1.x` banner).

**ILA board evidence (captured 2026-07-13, no SD swap needed)** — the design was still programmed with Build 73 PDI; captured all 4 ILAs to CSV (`/tmp/b73_ila_*.csv`):

Decoded `p3_tile_debug_bus` packing (`piton/design/chip/tile/rtl/tile.tmp.v:1022`, fields MSB→LSB: `last_l15_address[39:24,23:8,7:0]`, rqtype, size, ariane_debug_bus, L15 handshake, rst/clk):

- `core_bus64 = 0x008004208003f407` → **last L15 (memory) address = `0x80042080`** = `console_dev + 0x80` (nm: `console_dev` @ `0x80042000`, bss).
- L15 handshake bits (low byte `0x07`): `transducer_l15_val=0`, `l15_transducer_val=0` → **L1.5 interface IDLE**. CPU is NOT stalled on a memory/NoC response.
- ILA1 counters frozen over 1024-sample window: `core_seen16`/`uart_seen16`/`ddr_seen16` constant. **No UART activity = no banner (board-confirmed).**
- `p3_ariane_debug_bus[15:8]=0xf4` → `time_irq_i=1` (timer interrupt pending), ipi=0, irq=0, not in reset.

**Interpretation**: CPU reaches the OpenSBI console-init path (last mem op = console_dev), then enters an **internal stall** (L15 idle, not memory-waiting), consistent with `sbi_hart_hang` (`wfi; j` loop) from an init failure or double-trap. No UART output.

**Limitation**: the debug bus has **no PC**, so this localizes to the console-init *region* (last mem op), not an exact instruction. The exact step needs the probe fw (§6).

---

## 4. Static audit result (already done — do NOT redo)

A subagent extracted all 64-core OpenSBI cold-boot gates (dbg3→dbg27) from `wiki/devlog/2026-{05,06,07}.md` and checked each against the 2-core source tree at `build/p3_64core/riscv64-linux-64core-src-20260610/opensbi/`. **Every fix is present.** This is NOT a missing-known-fix problem.

| Gate | Fix | Present? |
|------|-----|----------|
| PIE relocation (dbg3) | Makefile `-fno-pie`/`-no-pie`, fw_base `0x80000000` | ✅ |
| mhpmevent4 illegal instr | `sbi_hart_mhpm_mask()` returns 0 | ✅ |
| 3-hart CLINT/PLIC (dbg6/7) | `openpiton.c OPENPITON_DEFAULT_HART_COUNT=64` | ✅ (2-core coldboot=hart0 bypasses anyway) |
| plic context_map stack overflow (dbg7) | `openpiton_early_init` parses into static `&plic` (no stack copy) | ✅ |
| PMP exhaustion (dbg8/12) | `sbi_hart_oldpmp_configure` | ✅ |
| DTB initrd-end truncation (dbg26) | 2-core DTB `linux,initrd-end=0x90107d9c` | ✅ |
| CSR 0x701 L1 D-cache disable (dbg23) | `sbi_hart.c:783 csrw 0x701,zero` | ✅ |
| coherency barrier (dbg21) | `sbi_trap.c` non-IRQ UART LSR read | ✅ |
| dbg28 probe remnants | aclint_mswi.c / openpiton.c clean | ✅ |

Also verified: PLIC/CLINT init loops use `sbi_for_each_hartindex` (DTB-driven) → safe on 2-core. 2-core DTB structure identical to 64-core (only cpu@N count differs). 

**The regression is the fw lineage (§5), not a missing fix.**

---

## 5. Root-cause hypothesis (high confidence, board-unverified)

The 2-core image was carrying **`fw_jump_p3_64core.bin` = byte-identical to `dbg28b_noprobe` (sha `12b4ff22`)**. This fw was built 2026-07-06 during the dbg28 mswi-probe experiments and **was NEVER hardware-verified to print the OpenSBI banner** (the session ended and the SD card went unseated before any verification).

- A clean `make clean && make` from current source reproduces `12b4ff22` exactly → source is stable, the binary is the issue's carrier.
- `dbg21` fw (sha `ab543745`, built 2026-06-26) is from the **verified-banner era** (OpenSBI banner reliably seen in 64-core logs dbg9 6/22 → ev_retry2 7/3).

**⚠️ dbg21 fw is at-risk**: the ILA board evidence points to the console-init path. Since dbg21 also runs console init, if the hang is a 2-core-specific console-path issue, dbg21 may also hang. **Do not blindly trust dbg21 to fix it — verify with the probe fw first (§6).**

---

## 6. THE NEXT STEP (everything is prepared; only a physical SD card swap is needed)

The exact hang step + fix + verification all require booting the **probe fw** (OpenSBI with raw-UART markers `I[SHDMWRTEPB` between init_coldboot steps). It needs the SD card in the reader.

### 6.1 Prepared artifacts (in `build/huaprop3/opensbi64/`)

| File | sha256 (head) | What it is |
|------|---------------|------------|
| `p3_opensbi_linux_2hart_probefw.img` | `b9bfcedb` | **PRIORITY TEST** — OpenSBI + raw UART probes `I`(sbi_init)`[`(init_coldboot)`S H D M W R T E P B` then banner |
| `p3_opensbi_linux_2hart_final.img` | `910f390e` | dbg21 fw image (at-risk fix candidate) |
| `p3_opensbi_linux_2hart_nocsr701_probefw.img` | `b8717aba` | probe fw + CSR 0x701 reverted |
| `p3_opensbi_linux_2hart_dbg21fw.img` | `517d9b87` | dbg21 fw image (alias, same fw as final) |
| `fw_jump_p3_64core_probe.bin` | `fd024769` | probe fw binary |
| `fw_jump_p3_64core_dbg21.bin` | `ab543745` | dbg21 fw binary |
| `fw_jump_p3_64core.broken_dbg28b.bin` | `12b4ff22` | the broken fw (backup) |

Remote host already has `/tmp/p3_opensbi_linux_2hart_probefw.img` (sha `b9bfcedb`) and `/tmp/p3_opensbi_linux_2hart_final_fix.img` (sha `910f390e`).

### 6.2 Probe marker meaning

```
I = sbi_init() entry (OpenSBI C code started)
[ = init_coldboot() entry
S = sbi_scratch_init done
H = sbi_heap_init done
D = sbi_domain_init done
M = sbi_hsm_init done
W = wake_coldboot_harts done
R = sbi_hart_init done (incl. CSR 0x701 L1 disable)
T = sbi_timer_init done (CLINT mtimer access)
E = sbi_platform_early_init done (= generic_early_init = console/fdt init)
P = sbi_pmu_init done
B = sbi_dbtr_init done → then sbi_boot_print_banner
```
**The last marker before silence = the failed init step.** ILA evidence predicts stop at/near `E` (console). If it stops before `T`, it's CLINT/timer; if before `R`, it's CSR 0x701.

### 6.3 Exact procedure (the only un-automated step is the physical SD card swap)

There is a background auto-write monitor running locally (`/tmp/auto_write_probe.sh`, polls remote `/dev/sdc` every 30s; when the card appears it dd-writes the probe fw `b9bfcedb` and verifies readback). So the flow is:

1. **PHYSICAL (user/human)**: move SD card from the FPGA slot → the remote card reader.
2. The monitor auto-writes probe fw + readback-verifies (watch `/tmp/auto_write_probe.log` for `PROBE_WRITE_COMPLETE`, readback sha must = `b9bfcedb`). If the monitor is dead, do it manually (§7.4).
3. **PHYSICAL**: move SD card reader → FPGA slot (push-push, click fully in — a loose card produces exactly the "bootrom hangs at first SD block" signature; see §8 pitfall #1).
4. Program the (unchanged) Build 73 diag PDI + UART capture:
   ```
   vivado -mode batch -source scripts/p3_program_pdi.tcl -tclargs \
     huaprop3_build73_2x1_opensbi_diag/debug_build/p3_top_build73_2x1_opensbi_diag.pdi \
     huaprop3_build73_2x1_opensbi_diag/debug_build/p3_top_build73_2x1_opensbi_diag.ltx
   ```
   (PDI sha `52e1400a`. XVC upload of 15.5 MB to VP1902 is slow — use `timeout 900`.)
5. Read the UART trace from `illya@100.93.77.36:~/p3_uart_logs/` — the `I[SHDMWRTEPB` sequence localizes the hang.
6. Based on the failed step, apply a targeted fix in the OpenSBI source (`build/p3_64core/.../opensbi/`), rebuild fw (`make PLATFORM=generic FW_JUMP=y FW_JUMP_ADDR=0x80200000 FW_JUMP_FDT_ADDR=0x88000000 CROSS_COMPILE=riscv64-linux-gnu-`), repackage image (`scripts/p3_make_opensbi_bundle_image.py`), rewrite SD, re-verify.

---

## 7. Environment, endpoints, commands (READ BEFORE RUNNING ANYTHING)

### 7.1 Board / remote host
- **Board UART + SD reader host**: `illya@100.93.77.36`, SSH password `123456` (NEVER write this into a repo file; use `/tmp/ssh_run.py` pexpect helper).
- `hw_server`: `100.93.77.36:3121`. XVC debug bridge: `202.197.4.99:2540`.
- UART devices on remote: `/dev/ttyUSB0` = P3 UART (115200 8N1), `/dev/ttyUSB1` = XVC JTAG.
- **SD card = `/dev/sdc`** on remote (Kingston Multi-Reader -1, ~29.7 GB, RM=1). **NEVER write `/dev/sda` or `/dev/nvme*`** — `/dev/sda` is a 2 TB WDC disk.
- SSH helper exists at `/tmp/ssh_run.py` (pexpect, handles password). Usage: `python3 /tmp/ssh_run.py "<remote-cmd>" <timeout>`.

### 7.2 Local repo (WSL, `/home/illya/openpiton`)
- Vivado runs on Windows (`D:\Xilinx\Vivado\2024.2`) via wrapper `/home/illya/bin/vivado`; invoked from WSL. P3 builds also work on the offline Ubuntu build host.
- **Offline Ubuntu build host** (for P3 Vivado builds): `cs@202.197.4.150` via jump `23178@100.70.176.125`. Vivado `/media/d1/Xilinx/Vivado/2024.2/bin/vivado`. Remote workspace `/home/cs/openpiton`. Use `scripts/p3_remote_vivado_64core.sh`.
- RISC-V toolchains: `riscv64-unknown-elf-gcc` 7.2.0 at `$HOME/scratch/riscv_install/bin/` (bootrom); `riscv64-linux-gnu-gcc` 11.4.0 at `/usr/bin/` (OpenSBI fw, Linux).
- Source env: `source piton/piton_settings.bash`; for Ariane also `source piton/ariane_setup.sh`.

### 73 OpenSBI / image paths
- OpenSBI source (with all fixes): `build/p3_64core/riscv64-linux-64core-src-20260610/opensbi/`
- Image packer: `scripts/p3_make_opensbi_bundle_image.py`
- Full image builder (rebuilds OpenSBI+Linux+DTB+initramfs): `scripts/p3_prepare_64core_opensbi_image.sh` (set `P3_64CORE_HARTS=2` for 2-core)
- 2-core Linux Image: `build/huaprop3/opensbi64/Image_p3_2hart`
- 2-core DTB: `build/huaprop3/opensbi64/p3_opensbi_2hart_initrd.dtb` (initrd-end=0x90107d9c)
- initramfs: `build/huaprop3/opensbi64/p3_rootfs_64hart_xsbench_v2.cpio.gz` (1080732 B)
- Bundle layout: GPT, P3OS/BI64 header @ sector 2048, then fw@0x80000000, Image@0x80200000, dtb@0x88000000, initrd@0x90000000.

### 7.4 Manual SD write (if monitor is dead)
```
img=build/huaprop3/opensbi64/p3_opensbi_linux_2hart_probefw.img   # b9bfcedb
sha256sum "$img"   # local
scp "$img" illya@100.93.77.36:/tmp/   # via /tmp/ssh_run.py pexpect, password 123456
# on remote:
lsblk -b -o NAME,SIZE,TYPE,MODEL,TRAN,RM /dev/sdc   # confirm real disk, RM=1
echo '123456' | sudo -S sh -c '
  umount /dev/sdc1 2>/dev/null || true
  dd if=/tmp/p3_opensbi_linux_2hart_probefw.img of=/dev/sdc bs=4M conv=fsync status=progress
  sync
  dd if=/dev/sdc bs=4M count=64 status=none | sha256sum   # MUST match b9bfcedb...'
```

---

## 8. Critical pitfalls / lessons (avoid these time-sinks)

1. **Loose SD card mimics an RTL bug.** On 2026-07-09 the 2-core boot "hung at first SD block read" (`copying block 0 of 1 blocks`). Root cause was the SD card not seated in the FPGA slot, NOT a 2x1 RTL defect. Always re-seat the card firmly (push-push click) before debugging SD-path RTL. DDR/UART still work with a loose card; only SD data reads hang. **Already ruled out for the current hang** (bootrom reads SD fine after re-seating on 7/13).

2. **Stale PyHP tmp files break 2x1 synthesis** (`dataIn_8 does not exist`, zero-byte `packet_filter.tmp.v`). For any new 2x1 PDI build, regenerate the PyHP tmp set (define.tmp.h, chip.tmp.v, chipset_impl.tmp.v, flat_id_to_xy, xy_to_flat_id) with `PITON_X_TILES=2 PITON_Y_TILES=1 PITON_NUM_TILES=2` AND the P3 9-device io_xbar, before Vivado. The WSL→Windows Vivado wrapper cannot exec `pyhp.py`; pre-generate tmp in WSL.

3. **Vivado impl crash at write_device_image** (Build 73 first run, 2026-07-09): a one-time WSL↔Windows Vivado hiccup at PDI write (NOT OOM, NOT a design error — route + timing met). Recover from `p3_top_physopt.dcp` via a minimal `open_checkpoint → route_design → write_device_image → write_debug_probes` Tcl (~30 min vs 5.5 h full rebuild).

4. **XVC PDI upload is slow**: programming the 15.5 MB PDI to VP1902 over XVC can take >500 s. Always use `timeout 900` for `p3_program_pdi.tcl`. 400/500 s timeouts killed mid-`program_hw_devices`.

5. **UART capture must outlive the boot**: bootrom copy of the 19 MB Linux Image takes ~3-4 min. Use `timeout 600 cat /dev/ttyUSB0 > log` and start capture BEFORE programming.

6. **Versal DONE bit is not `REGISTER.BOOTSTS.DONE`** (that's for arm_dap). The PDI/ILA programming script reports `DONE bit: HIGH` correctly via its own mechanism.

7. **dbg21 "reached /bin/sh + nproc=64" was NOT verified** (2026-06-28 correction). The first RELIABLE 64-core shell was 2026-07-03 (ev_retry2.log). Treat dbg21 as "prints banner reliably" but not "full shell verified".

8. **Timer-data-corruption and MSIP-delivery and L1-coherency diagnoses are RETIRED** (dbg27, coh_2core/coh_64core/coh_ipi64 all PASS in sim). Do not re-chase them.

---

## 9. Likely root-cause candidates to expect from the probe fw

Based on the ILA (console_dev last access, internal stall, timer_irq pending), in priority order:

1. **Console-init failure → sbi_hart_hang** (stop at `E`): `fdt_serial_init` → `uart8250_device_init`. Why 2-core-specific is unclear (same DTB + UART RTL as 64-core). Check if `uart8250_init` writes a register that wedges the chipset UART on 2-core, or if fdt parsing of the 2-hart DTB faults.
2. **Timer init → sbi_hart_hang** (stop at `T`): CLINT mtimer access. `time_irq_i=1` pending in ILA is suggestive.
3. **CSR 0x701 L1-disable stall** (stop at `R`, i.e., last marker `W`): the `csrw 0x701,zero` drains the D-cache; if the drain stalls on 2-core. Test directly with the `nocsr701_probefw` image (`b8717aba`).
4. **Double-trap** (marker sequence stops abruptly mid-run): an exception whose handler also exceptions → `sbi_hart_hang`.

If the probe fw prints NO marker at all (not even `I`), OpenSBI `_start`/lottery/relocate hangs before C entry — that would point to a coherency/atomic issue in the coldboot lottery on 2-core.

---

## 10. If dbg21 fw ALSO hangs (likely, given ILA console-path evidence)

Then it's a genuine 2-core-specific OpenSBI cold-boot issue, not fw lineage. The probe fw (b9bfcedb) localizes it. Then:
- Identify the failing function from the last marker.
- Read that function in `build/p3_64core/.../opensbi/`, find the 2-core-specific trigger (likely a DTB-driven loop or an MMIO access whose response differs at 2x1).
- Apply a minimal source fix, rebuild fw, repackage, rewrite SD, re-verify.

---

## 11. Reference: where everything is logged

- **Devlogs** (append-only, newest first): `wiki/devlog/2026-07.md` (2-core work, ILA evidence, fix application), `2026-06.md` (64-core OpenSBI gates dbg3→dbg27), `2026-05.md` (P3 migration/bootrom).
- **Wiki index**: `wiki/INDEX.md`. Concept articles in `wiki/concepts/`.
- **R1 rule**: every code/RTL/build change MUST have a wiki devlog entry, committed + pushed with `wiki:` prefix, immediately. Devlog DAILY when any FPGA work occurs. See `CLAUDE.md`.
- This 2-core investigation is committed across `9a5b044`, `867a74e`, `93ee208`, `9d58dd4`, `d5e81e2`, `9ee8fab`, `491531e`, etc.

---

## 11.5 Current OpenSBI source-tree state (IMPORTANT — it is NOT clean)

The OpenSBI source tree at `build/p3_64core/riscv64-linux-64core-src-20260610/opensbi/` currently has **uncommitted experimental edits** (it's an extracted tarball under `build/`, not git-tracked). Specifically:

- `lib/sbi/sbi_init.c`: has `p3_probe_putc()` helper + probe calls (`I` at sbi_init entry; `[S H D M W R T E P B` in init_coldboot).
- `lib/sbi/sbi_hart.c`: CSR 0x701 write is **commented out** (`/* asm volatile("csrw 0x701, zero" ...); */`).

So **a fresh `make` from the current tree produces the `nocsr701_probefw` variant** (probes + CSR 0x701 reverted), sha `b8717aba` image / `df3ef695...`-class fw. To get:
- the **stock current-source fw** (12b4ff22, = the broken dbg28b_noprobe lineage): restore both edits (remove probes, uncomment CSR 0x701).
- the **probe fw with CSR 0x701 KEPT** (`b9bfcedb`): restore the `sbi_hart.c` CSR 0x701 line (uncomment), keep the `sbi_init.c` probes.
- the **dbg21 fw** (`ab543745`): use the **pre-built binary** `fw_jump_p3_64core_dbg21.bin` — it is NOT reproducible from this tree (dbg21 was built 6/26 from a source state that no longer exists in this extracted tree; do not try to rebuild it).

The probe markers and their meaning are defined in `sbi_init.c` (`p3_probe_putc`). `p3_probe_putc` writes directly to AXI16550 THR `0xfff0c2c000` with an LSR `0xfff0c2c005` THRE poll — same path the bootrom proved working, so markers print before console init.

## 12. One-line summary for Codex

> 2-core OpenSBI prints no banner after bootrom jump. All 64-core fixes are present in source (static audit done). ILA shows CPU internally hung after accessing `console_dev`. The image carried an unverified fw (`dbg28b_noprobe`); dbg21 fw is the candidate fix but is at-risk. **The next action is to boot the probe-fw image (`b9bfcedb`, already built + on the remote + auto-write monitor running) to localize the exact failing init step — this only needs a human to physically swap the SD card FPGA↔reader.** Everything else is prepared.
