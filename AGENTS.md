# Repository Guidelines

## Project Structure & Module Organization
OpenPiton source lives under `piton/`. `piton/design/` contains synthesizable RTL and platform logic: `design/chip/` for tile and chip RTL, `design/chipset/` for off-chip controllers and peripherals, `design/include/` for shared defines, and `design/xilinx/` or `design/aws/` for FPGA targets. Verification assets are in `piton/verif/`, with `env/` testbenches and monitors plus `diag/assembly/` and `diag/c/` diagnostics. Tool wrappers, preprocessors, PLI/VPI libraries, and regression utilities are under `piton/tools/`. Generated simulator output and local models belong in `build/`; manuals and images are in `docs/`.

## Build, Test, and Development Commands
Set `PITON_ROOT` to the repository root and run `source $PITON_ROOT/piton/piton_settings.bash` before using tools. Run simulation commands from `$PITON_ROOT/build`.

- `sims -sys=manycore -x_tiles=1 -y_tiles=1 -vcs_build`: build a 1x1 VCS simulation model.
- `sims -sys=manycore -x_tiles=1 -y_tiles=1 -vcs_run princeton-test-test.s`: run a single diagnostic after building.
- `sims -sim_type=vcs -group=tile1_mini`: build and run a regression group.
- `regreport $PWD > report.log`: summarize regression results from a run directory.
- `contint --bundle=git_push`: run the CI bundle; requires SLURM, PBS, or similar.

For Ariane/RISC-V work, also source `piton/ariane_setup.sh` and pass `-ariane` to relevant `sims` commands.

## Coding Style & Naming Conventions
Match nearby RTL and script style. Verilog/SystemVerilog uses 4-space indentation in module bodies, aligned declarations, lowercase module/file names, and explicit suffixes such as `_clk`, `_rst_n`, `_val`, `_rdy`, and `_top`. Preserve copyright headers. Treat `.pyv` files as PyHP templates; update the template source, not generated temporary files. Python and Perl tools are legacy style, so keep edits minimal and localized.

## Testing Guidelines
Add diagnostics near related tests and register reusable suites through the appropriate `.diaglist` or regression group. For narrow RTL changes, run a focused `sims ... -vcs_run <test>` first, then a relevant regression such as `tile1_mini`, `ariane_tile1_simple`, or `ariane_tile1_amo_tests_p`. Include `regreport` summaries when reporting results.

## Commit & Pull Request Guidelines
Recent history uses short imperative subjects, often scoped by subsystem, plus GitHub merge commits. Example: `Fix typo in l2 pipe1 causing wrong hazard detection`. Keep commits focused. PRs should describe the changed RTL, tools, or tests; list exact `sims` or `contint` commands run; link related issues; and note simulator/tool versions for environment-sensitive changes.

## Security & Configuration Tips
Do not commit generated build directories, local tool installs, simulator licenses, or machine-specific paths. Keep `VCS_HOME`, RISCV toolchain paths, Vivado settings, and license configuration in the local shell unless a documented default is intentionally changed.
