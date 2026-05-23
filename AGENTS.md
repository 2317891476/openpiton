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

## R1: Mandatory Wiki Sync Rule

**Every code change MUST include corresponding wiki updates. No exceptions. No "sync later".**

The project wiki lives at `wiki/` in the repository root. See `wiki/INDEX.md` for the full structure.

### Trigger Conditions (when wiki sync is REQUIRED)

1. **RTL change** -- update the relevant `wiki/concepts/` article (resource estimates, timing notes, coding rules, etc.)
2. **New board / platform port** -- update `architecture-evolution.md`, `resource-estimation.md`, and add devlog entry
3. **Build flow / tooling change** -- update `vivado-tooling.md` or `simulation.md`
4. **Scaling milestone reached** -- update `wiki/INDEX.md` timeline, add devlog entry
5. **Bug fix that revealed a non-obvious root cause** -- add to the relevant concept article's "Pitfalls" or "Lessons" section
6. **New FPGA synthesis results** -- update `resource-estimation.md` and/or `timing-closure.md` with actual numbers
7. **Device tree / address map change** -- update wiki if it affects scaling design
8. **Any decision that affects the P0-P4 roadmap** -- update `wiki/INDEX.md` timeline

### Anti-Patterns (NEVER do these)

- **"I'll update the wiki in a follow-up"** -- No. Wiki sync is part of the change, not a separate task.
- **Wiki article with only a title and "TBD"** -- Every article must have at least a one-paragraph summary. Stub sections within an article are OK if labeled `(TBD)`.
- **Devlog entries without dates** -- Every devlog entry must have an ISO date heading (`## YYYY-MM-DD -- <title>`).
- **Updating code numbers without updating wiki numbers** -- If you change resource usage, clock frequencies, timing results, or core counts in code/constraints, the wiki MUST reflect the new values in the same commit.
- **Orphan wiki articles** -- Every article must be linked from `wiki/INDEX.md`.
- **Deleting wiki content without replacement** -- If information is outdated, update it; don't delete it.

### Devlog Rules

- File naming: `wiki/devlog/YYYY-MM.md` (one file per month)
- Entries are append-only, newest first within each file
- Each entry: `## YYYY-MM-DD -- <short title>` followed by bullet points
- Never edit past entries (append corrections as new entries)

### Git Commit Requirement (ABSOLUTE)

**Every wiki update MUST be committed to git and pushed to GitHub immediately. No exceptions. No queuing for later.**

- After writing ANY wiki file (devlog, concept article, INDEX.md), immediately run `git add <file>` and `git commit` with a descriptive message.
- Wiki commits should use the prefix `wiki:` (e.g., `wiki: add May 23 devlog — Build 19 reset fix verified`).
- After committing, push to the remote: `git push origin openpiton`.
- **Anti-pattern**: accumulating multiple wiki changes without committing. Each logical update gets its own commit.
- **Anti-pattern**: "I'll commit after this build finishes." No — commit the wiki changes NOW. The build proceeds independently.
- If a build or debug session spans hours, commit wiki updates incrementally — don't wait until the end of the session.
- CLAUDE.md and AGENTS.md changes follow the same rule: commit and push immediately.
