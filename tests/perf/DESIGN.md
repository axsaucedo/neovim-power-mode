# tests/perf/DESIGN.md — Suite design

Input: `tests/perf/RESEARCH.md`. Output: this document, which defines
the suite layout, result schema, scenario matrix, instrumentation, and
how it all fits the existing codebase patterns.

## 1. Directory layout

```
tests/perf/
  README.md              # how to run, methodology (top-level entry point)
  RESEARCH.md            # T1 findings (input to this design)
  DESIGN.md              # this file

  bench_hotspots.lua     # T3 — headless per-stage microbench
  bench_memory.lua       # T3 — GC / allocation profiler
  bench_latency.lua      # T3 — InsertCharPre → first-frame latency

  bench_tui_frame.lua    # T4 — init.lua that instruments engine.start
  bench_tui.sh           # T4 — tmux driver + JSONL post-processor

  run.sh                 # T5 — orchestrator: runs everything, emits report files
  test_perf_suite.sh     # T6 — validates the suite itself

  results/
    .gitkeep             # keeps the dir; *.json + *.md are gitignored
```

`./REPORT.md` (repo root) is **gitignored, not committed** — produced
by T7 and posted as a PR comment.

## 2. Stable result schema

All benches emit JSON conforming to this schema so deltas across runs
or SHAs diff cleanly. Schema is versioned to allow future changes.

```json
{
  "schema_version": 1,
  "tool": "bench_hotspots.lua",
  "git_sha": "<short sha>",
  "timestamp": "<ISO 8601>",
  "machine": {
    "os": "darwin",
    "arch": "arm64",
    "nvim": "0.11.5",
    "tmux": "3.4"
  },
  "scenario": "particles+combo+fire_wall",
  "config_overrides": { "particles": { "preset": "explosion" }, "...": "..." },
  "iterations": 200,
  "warmup_iterations": 50,
  "stages": {
    "fire_wall.update": {
      "n":     200,
      "p50_ms": 0.451,
      "p95_ms": 0.612,
      "p99_ms": 0.741,
      "max_ms": 1.123,
      "mean_ms": 0.478,
      "stddev_ms": 0.084
    }
  },
  "notes": []
}
```

Rules:

- Times are always **milliseconds**, never raw nanoseconds.
- Headless benches set `tool` to the script filename; TUI bench emits
  per-scenario JSON and a roll-up.
- `machine.nvim` is captured via `vim.version()`; `machine.tmux` via
  `tmux -V` (skipped for headless benches).
- `config_overrides` records the exact `setup({})` table used, so the
  scenario is reproducible verbatim.
- Variance band (T6) is asserted on `p50_ms` per stage.

## 3. Scenario matrix

Each scenario is named, deterministically configured, and runs in both
headless and TUI benches where applicable.

| ID                              | Notes |
|---------------------------------|-------|
| `baseline`                      | All features off (`combo.enabled=false, fire_wall.enabled=false, shake.mode=none, particles.max_particles=0`). Lower bound on engine overhead. |
| `particles.<preset>`            | One scenario per preset: `explosion`, `fountain`, `rightburst`, `shockwave`, `emoji`, `stars`, `disintegrate`. Combo + fire_wall off. |
| `particles+combo`               | Default particles + combo (no shake). Fire wall off. |
| `particles+combo+fire_wall`     | All three on. Combo forced to ≥ level 2 (drives fire). |
| `fire_wall_only`                | Combo forced to level 3, zero particles. Isolates fire wall cost. |
| `backspace_storm`               | Type "x" 30 times then BS×30 to drive the `fire` preset. |
| `renderer_stress`               | `max_particles=300, pool_size=200, count={20,30}`. |
| `high_fps`                      | Defaults but `engine.fps=60`. |
| `large_editor`                  | `vim.o.columns=300, vim.o.lines=80` (drives fire grid). |
| `small_editor`                  | `vim.o.columns=80, vim.o.lines=24`. |
| `long_session`                  | 60 s continuous typing → drift / leak detection. |

The TUI bench runs all scenarios. The headless microbench runs every
scenario except `long_session` and `backspace_storm` (which require a
real key stream).

## 4. Instrumentation strategy

Headless benches drive subsystems directly via Lua function calls
inside a single `nvim --headless` invocation, timing with
`vim.loop.hrtime()`. No instrumentation needed.

The TUI bench (`bench_tui_frame.lua`) is loaded as an `-c 'luafile …'`
into a real `nvim` running inside `tmux`. After `require("power-mode").setup()`
runs, it **monkey-patches** `engine.set_modules` (the same hook used
internally) to wrap `particles_mod.update`, `fire_mod.update`,
`fire_wall_mod.update`, `renderer_mod.render`, `combo_mod.update` with
per-call timers that append `(stage, hrtime_delta_ns)` lines to a
JSONL file at `./tmp/pm_perf_<scenario>_<pid>.jsonl`.

The instrumentation never touches plugin source. It also writes the
scenario name into the JSONL header line and emits a sentinel `end`
line on `VimLeavePre` so the post-processor knows the file is complete.

The post-processor (`bench_tui.sh`) reads the JSONL, computes per-stage
p50/p95/p99/max/mean/stddev, and emits the schema JSON.

Instrumentation overhead is measured by T6 (run two passes: one with
the wrappers, one with no-op wrappers) and the report subtracts it.

## 5. How it fits the existing codebase

| Existing pattern | Where the suite mirrors it |
|---|---|
| `tests/minimal_init.lua` (rtp prepend + `runtime plugin/...`) | Every bench Lua file does the same bootstrap. |
| Tests invoked via `nvim --headless -u tests/minimal_init.lua -c "luafile …"` | `bench_hotspots.lua`, `bench_memory.lua`, `bench_latency.lua` are invoked the same way. |
| `tests/e2e/lib.sh` — `e2e_start_session`, `e2e_capture`, `e2e_type_insert`, `e2e_assert_*` | `bench_tui.sh` sources `lib.sh` (relative include) and reuses these helpers. |
| `tests/tmux_smoke_test.sh` shell style (`set -euo pipefail`, trap cleanup, PASS/FAIL counters) | `bench_tui.sh` + `test_perf_suite.sh` + `run.sh` follow the same style. |
| `.github/workflows/test.yml` — 3-version Neovim matrix, all jobs use `nvim --headless` | T5 adds **one** new job `perf-smoke` that runs the smallest scenario per matrix entry and installs `tmux` first. Existing jobs are not modified. |

## 6. CI policy

- The new `perf-smoke` job **does not assert on absolute timings**. It
  asserts only that:
  - `bench_hotspots.lua` exits 0 and produces parseable JSON.
  - `bench_tui.sh` runs the `baseline` scenario and produces parseable
    JSON.
- This guards against the suite breaking without making the build
  flaky due to runner-to-runner variance.
- All recommendation numbers in `REPORT.md` come from the dev machine.
  The runner-class is recorded in JSON via `machine.os` so it is never
  conflated with dev-machine data.

## 7. "Substantial" recommendation threshold

A recommendation reaches `REPORT.md` only if:

- It would save **≥ 0.1 ms/frame** in at least one scenario at default
  settings, **OR**
- It would reduce the full-frame cost of a scenario by **≥ 5%**.

Anything smaller is enumerated in the **non-recommendations** section
so reviewers don't chase noise.

## 8. Reproducibility

- Same dev machine, same git SHA, same `engine.fps` → re-running the
  suite three times must yield `p50_ms` per stage within ±15% of the
  median of the three runs. T6 asserts this; any stage outside the
  band is flagged in the report.
- All randomness is bounded: presets use `math.random` but particle
  counts are drawn from explicit `count={a,b}` ranges, so per-frame
  cost has a known envelope. The suite documents the seed if a future
  step needs determinism (none required today).

## 9. Outputs

- Per-bench JSON files under `tests/perf/results/<sha>/<scenario>.json`
  (one JSON per scenario per bench).
- `tests/perf/results/<sha>/summary.md` rendered by `run.sh`
  with the headline tables.
- Repo-root `./REPORT.md` (T7) with the full narrative + recommendations
  — gitignored, **not committed**, posted to the PR as a comment.

This document is the contract that T3, T4, T5, T6, T7 implement.
