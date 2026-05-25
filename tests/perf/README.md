# tests/perf — Performance evaluation suite

Repeatable performance measurement for neovim-power-mode. Measurement
only — no plugin source is modified.

## Quick start

```bash
# Full suite (headless + TUI + memory + latency, ~3-5 min on a laptop)
bash tests/perf/run.sh

# Headless microbench only (fast, ~10 s)
nvim --headless -u tests/minimal_init.lua -l tests/perf/bench_hotspots.lua

# TUI bench only (needs tmux)
bash tests/perf/bench_tui.sh
```

Results land under `tests/perf/results/<sha>/` (gitignored bodies; the
folder itself is kept by `.gitkeep`).

## What each tool measures

| Tool | What it measures | Output |
|---|---|---|
| `bench_hotspots.lua` | Per-subsystem `vim.loop.hrtime()` ms/frame in headless nvim, per-preset, per-particle-count sweep, per-API primitive table. | `results/<sha>/hotspots.json` |
| `bench_memory.lua` | `collectgarbage("count")` delta over 30 s of scenario activity → KB/s allocation rate. | `results/<sha>/memory.json` |
| `bench_latency.lua` | `InsertCharPre` → first-rendered-frame latency, sampled across keystrokes. | `results/<sha>/latency.json` |
| `bench_tui_frame.lua` + `bench_tui.sh` | Per-frame `(stage, hrtime_delta)` from a real nvim inside tmux, post-processed to p50/p95/p99/max. **Source of truth** for API-bound numbers. | `results/<sha>/tui_<scenario>.json` |
| `run.sh` | Orchestrates all of the above. | `results/<sha>/summary.md` |
| `test_perf_suite.sh` | Asserts the suite itself works and is reproducible. | exit code |

## Methodology

See `tests/perf/DESIGN.md` for the full design (schema, scenario
matrix, instrumentation, fitness with the existing codebase). See
`tests/perf/RESEARCH.md` for the codebase analysis that drove the
design.

Recommendations from a full run are written to `./REPORT.md` at the
repo root (gitignored, posted as a PR comment, not committed).

## Conventions

- All scratch I/O (JSONL frame logs, suppression sinks) goes under
  `./tmp/` (gitignored). `./tmp/null` is the in-repo equivalent of
  `/dev/null` for this suite — never use the system `/tmp` or
  `/dev/null` in this repo's scripts.
- All scripts are `set -euo pipefail`; failure aborts the run and
  prints the captured pane / log for debugging.
- All Lua benches use `tests/minimal_init.lua`'s bootstrap pattern.

## What CI runs

A single non-asserting `perf-smoke` job runs the smallest scenario per
Neovim matrix entry and verifies the suite *executes* cleanly. It does
**not** assert absolute timings — runner variance makes that flaky.
All recommendation numbers come from the dev machine and are tagged
with the machine spec in the JSON.
