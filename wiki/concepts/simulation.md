# Simulation

Simulation strategies for validating manycore configurations.

## Simulators

| Simulator | Speed | Multi-core Support | Notes |
|-----------|-------|--------------------|-------|
| VCS | Fast | Full | Primary tool, requires license |
| Verilator | Medium | Partial | Open source, lint-like checks |
| Icarus | Slow | Full | Open source, good for small tests |

## Scaling Simulation

- 1x1: minutes per test (VCS)
- 2x2: ~4x slower, still practical
- 4x4+: hours per test, need targeted diagnostics
- Use `MINIMAL_MONITORING` to reduce overhead

## Key Commands

```bash
sims -sys=manycore -x_tiles=N -y_tiles=M -vcs_build
sims -sys=manycore -x_tiles=N -y_tiles=M -vcs_run <test>
sims -sim_type=vcs -group=<regression>
```

## Ariane Verilator 5.046

The local no-VCS Ariane path uses the system Verilator 5.046. The older
Ariane-bundled Verilator 4.014 is not usable in this environment because it does
not build with the installed bison version.

Environment:

```bash
source $PITON_ROOT/piton/piton_settings.bash
source $PITON_ROOT/piton/ariane_setup.sh
export RISCV=$HOME/scratch/riscv_install
export PATH=$RISCV/bin:$PITON_ROOT/piton/tools/bin:$PATH
unset VERILATOR_ROOT
```

The 8x8 / 64-tile model requires Verilator 5 compatibility flags plus the
scaling workaround below:

```bash
sims -sys=manycore -x_tiles=8 -y_tiles=8 -ariane -vlt_build \
  -vlt_build_args=--no-timing \
  -vlt_build_args=-Wno-WIDTHEXPAND -vlt_build_args=-Wno-WIDTHTRUNC \
  -vlt_build_args=-Wno-WIDTH -vlt_build_args=-Wno-SELRANGE \
  -vlt_build_args=-Wno-ASCRANGE -vlt_build_args=-Wno-WIDTHCONCAT \
  -vlt_build_args=--hierarchical -vlt_build_args=-CFLAGS -vlt_build_args=-O0 \
  -vlt_build_args=--trace -vlt_build_args=-CFLAGS -vlt_build_args=-DVERILATOR_VCD
```

`--hierarchical` keeps the compile to roughly one module copy instead of a
large flattened design. `-CFLAGS -O0` avoids GCC spending 50+ minutes optimizing
the 21 MB root-split `__11` file under the default `-Os`. Use `make -j16`; an
unbounded `make -j` can create enough `cc1plus` processes to OOM the machine.

Diagnostics must not call `printf` because the Verilator testbench does not
model the UART THRE bit. Use `pass()`/`fail()` and inspect `status.log` plus the
`Hit Good trap` / `Hit Bad trap` lines.

## Current 64-Core Simulation Gate

As of 2026-06-30, `coh_2core.c` and `coh_64core.c` both pass, so the previous
L1-coherence diagnosis is retired. The real hardware boot chain has moved past
the stale `linux,initrd-end` truncation issue; dbg26 fixes the initramfs range
and exposes the next blocker: intermittent SMP `stop_machine` / IPI forward
progress failure.

The strongest local reproducer is `coh_ipi64.c`, which writes CLINT MSIP bits
from hart0 to the other 63 harts. It intermittently trips the L1.5 messages
monitor around a TILE0 store to `0x8020e9c`; this path is closer to Linux
`stop_machine` than the AMO-based `coh_64core.c` test.

The next diagnostic goal is a VCD for the failing `coh_ipi64.c` window. Before
looping runs, reduce monitor output by replacing complete `$display`/`$write`
statements with `;` using a statement-aware script. Avoid comment-prefix edits
that leave empty `case` labels, and avoid broad regex deletion that can consume
`begin`/`end` structure.

For the active `coh_ipi64.c` root-cause test, do not use full Verilator
`--trace` as the default capture path. Full hierarchical VCD tracing is too slow
for the intermittent failure loop. Instead, build the existing 8x8 model without
global trace and compile the testbench with `-DCOH_IPI64_SMALL_VCD`. The custom
writer in `piton/tools/verilator/my_top.cpp` emits `coh_ipi64_small.vcd` only
after `main_time >= 16000000`, omits high-frequency clock toggles after the
initial value, and records the CLINT MSIP/AXI bridge, CLINT NoC queues, TILE0
L1.5 NOC1/NOC3/pipeline/MESI write signals, and TILE36 L1.5/CSM signals. TILE36
is included because the older failing verbose log ended at a `TILE36 L15_CSM REQ
MON` line, while TILE0 is still needed for the earlier L1.5 monitor summaries.
The harness also prints `COH_IPI64_PROGRESS main_time=<n>` every 1,000,000 time
units so long 8x8 `-O0` runs are observable before the VCD window opens.

Relink after changing the small-VCD harness:

```bash
make -j16 -C build/manycore/rel-0.1/obj_dir -f Vcmp_top.mk Vcmp_top
```

Then loop the reproducer from `$PITON_ROOT/build` until a messages-monitor
failure appears:

```bash
for i in $(seq 1 20); do
  rm -f coh_ipi64_small.vcd
  log=/tmp/coh_ipi64_vcd_runs/small_run_${i}.log
  sims -sys=manycore -x_tiles=8 -y_tiles=8 -ariane -vlt_run coh_ipi64.c \
    -finish_mask=0x1 -rtl_timeout=20000000 > "$log" 2>&1
  err=$(grep -acE "SIGDIE|L1\\.5 MON|error message type|L15 mon|Simulation -> FAIL" "$log" || true)
  [ "$err" != "0" ] && cp coh_ipi64_small.vcd /tmp/coh_ipi64_vcd_runs/coh_ipi64_fail_small_${i}.vcd && break
done
```

## Quicksilver-Specific Testing (TBD)

- Single-core functional correctness
- Multi-core data race validation
- Performance counter collection for speedup analysis
