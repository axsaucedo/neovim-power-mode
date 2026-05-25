# tests/perf/RESEARCH.md — Research findings for the perf evaluation suite

This document is the input to `DESIGN.md`. Every claim cites a
file:line so the design can be reasoned about without re-reading the
codebase.

## 1. Engine per-frame call graph

`lua/power-mode/engine.lua:25-58` — `M.start()` creates a libuv timer
that fires every `math.floor(1000 / cfg.engine.fps)` ms (default fps=25
→ 40 ms). The timer callback computes `dt`, then `vim.schedule`s a
closure that:

1. calls `particles_mod.update(dt)`         (line 38)
2. calls `fire_mod.update(dt)`              (line 39)
3. calls `fire_wall_mod.update(dt)`         (line 40)
4. **allocates** `all = {}` and merges three particle lists into it
   via `ipairs` loops (lines 43–52)
5. calls `renderer_mod.render(all)`         (line 54)
6. calls `combo_mod.update(dt)`             (line 55)

Implications for the bench:

- Stages are clearly separable; each can be timed in isolation with
  `vim.loop.hrtime()`.
- The merge step in (4) is a per-frame allocation worth measuring.
- The scheduled closure runs even when every list is empty — an
  "idle tick" scenario is worth running.

## 2. Renderer hot path

`lua/power-mode/renderer.lua:34-123` — `M.render(particles)`:

- Iterates a fixed-size pool (`cfg.particles.pool_size`, default 60)
  in `M.init` (line 12) creating one floating window per slot.
- For each particle, per frame:
  - `vim.fn.strdisplaywidth(p.char)` (line 91) — Lua/vim.fn bridge.
  - `pcall(vim.api.nvim_buf_set_lines, ...)` (line 90).
  - `pcall(vim.api.nvim_win_set_config, ...)` (line 93).
  - `pcall(vim.api.nvim_win_set_option, ..., "winblend", blend)`
    (line 102).
  - `pcall(vim.api.nvim_win_set_option, ..., "winhighlight", ...)`
    (line 104).
- Unused windows are pushed offscreen via another
  `nvim_win_set_config` (lines 113–121) every frame, even if they
  were already offscreen.
- Cursor avoidance recomputes `vim.fn.screenpos` + `vim.fn.win_getid`
  every frame (lines 46–51).

Scratch bench numbers (`tmp/bench_hotspots.lua`, headless,
darwin/arm64, nvim 0.11.5):

| primitive                              | μs/call |
|----------------------------------------|--------:|
| `nvim_win_set_option` (winblend)       | 19.0 |
| `nvim_win_set_option` (winhighlight)   | 19.1 |
| `nvim_buf_set_lines`                   |  1.2 |
| `nvim_buf_add_highlight`               |  1.0 |
| `nvim_win_set_config` (move)           |  0.4 |
| `vim.fn.strdisplaywidth`               |  0.2 |

`nvim_win_set_option` × 2 per particle × N particles × 25 fps is
the worst-case in the existing renderer. The suite must include a
**renderer-stress** scenario (high N) and a per-API primitive table.

## 3. Fire wall hot path

`lua/power-mode/fire_wall.lua:211-302` — `M.update(_dt)`:

- Per-frame allocates the grid only on dimension change
  (`ensure_grid`, lines 85-96 + 220), but propagation loops O(w·h)
  every frame (lines 255-264).
- Per-cell `nvim_buf_add_highlight` inside the render loop
  (lines 290-301) — at 200 cols × 5 rows that is **1000 highlight
  API calls every frame**.
- `grid_has_heat()` (lines 199-208) does an O(w·h) scan every
  cooldown frame.
- `heat_to_char` (lines 98-103) and `heat_to_hl` (lines 105-110)
  are linear scans over 5 entries called per cell.

Scratch headless number: `fire_wall.update` = **0.4513 ms/frame ≈
94% of full-frame cost** when active. This makes it the headline
bench target.

The bench must:

- Run a **fire_wall-only** scenario (combo forced to level ≥ 2 so
  fire is visible).
- Break `fire_wall.update` into seed / propagate / render /
  grid_has_heat sub-timings.

## 4. Combo hot path

`lua/power-mode/combo.lua:267-313`:

- `M.update(dt)` always calls `M.render()` (line 278).
- `M.render()` rebuilds 7 lines and calls `nvim_buf_set_lines`
  (line 312) every frame, even when the visible state is identical.
- The timeout-bar `render_bar(...)` (lines 63-66) only changes
  visibly when `floor(ratio * width)` changes — most frames it is
  identical to the previous frame.

Implication: a **change-detection** recommendation is on the table;
the bench must measure `combo.update + render` cost per frame.

## 5. Particles hot path

`lua/power-mode/particles.lua` is a dispatcher.
`lua/power-mode/presets/explosion.lua:60-80` (and the other 7 presets)
contain the actual physics update — table iteration with swap-and-pop
removal. These are cheap (~0.001 ms/frame headless), but each preset
must still be measured (different counts/lifetimes/chars produce
different active-list sizes).

Presets to cover (built-in, `lua/power-mode/particles.lua:7-15`):
explosion, fountain, rightburst, shockwave, emoji, stars, disintegrate,
plus the backspace-fire preset at `lua/power-mode/presets/fire.lua`.

## 6. Config resolution

`lua/power-mode/config.lua:230-247` — `M.resolve(user_opts)` merges
defaults + vim globals + user opts and validates. The bench drives
every scenario by calling `require("power-mode").setup({...})` with
a different table. No need for vim globals.

Config knobs the bench needs to vary:
- `engine.fps` (default 25; high-FPS scenario uses 60)
- `particles.preset` (8 presets)
- `particles.max_particles`, `pool_size`, `count` (renderer stress)
- `combo.enabled`, `combo.shake`
- `fire_wall.enabled`, `fire_wall.max_rows`
- `shake.mode`
- `engine.stop_delay` (set high to keep the engine running during
  measurement)

## 7. Existing test patterns to mirror

- `tests/minimal_init.lua` — 2-line bootstrap that preprends `.` to
  rtp and runtimes the plugin. The perf suite uses the same pattern.
- `tests/test_*.lua` (5 files) — each is a flat Lua script invoked
  via `nvim --headless -u tests/minimal_init.lua -c "luafile <file>"
  -c "qall!"`. The headless benches follow this exact invocation.
- `tests/e2e/lib.sh` — `e2e_start_session`, `e2e_capture`,
  `e2e_type_insert`, `e2e_assert_contains`. The TUI bench reuses
  these helpers verbatim where possible.
- `tests/tmux_smoke_test.sh` — pattern for tmux + nvim + key
  injection + pane capture. Same shell style (`set -euo pipefail`,
  trap cleanup, PASS/FAIL counters) applies to `bench_tui.sh`.

## 8. CI today

`.github/workflows/test.yml`:

- Runs on `push`/`pull_request` to `main`.
- Matrix: `neovim ∈ { v0.9.5, v0.10.0, nightly }`.
- Five steps, each one `nvim --headless -u tests/minimal_init.lua -c
  "luafile tests/test_<name>.lua" -c "qall!"`.
- No tmux step. No perf step. No `setup-tmux` action.

The perf suite adds **one** new CI job (`perf-smoke`) that runs the
fastest single bench per matrix entry, with **no absolute-timing
assertion** — only the suite-runs-cleanly check. Existing jobs are
not modified.

Note: `tmux` is not preinstalled on `ubuntu-latest` runners in all
matrix combinations, but `apt-get install -y tmux` works in CI.
`bench_tui.sh` requires it; the perf-smoke CI job will install tmux.

## 9. Existing scratch harnesses (to promote)

- `tmp/bench_hotspots.lua` — headless microbench, already produced
  the per-stage numbers above. Will be hardened into
  `tests/perf/bench_hotspots.lua` in T3.
- `tmp/bench_tui_cpu.sh` — tmux-driven `ps %cpu` sampler. Will be
  **superseded** in T4 by `bench_tui.sh` which uses engine-injected
  per-frame instrumentation (much more precise than `ps %cpu`).

Both stay under `tmp/` (gitignored) and are not promoted directly;
they are the reference implementations.

## 10. Filesystem / process rules confirmed

- `.gitignore` line `tmp/` confirms scratch is excluded.
- `./docs/` does not exist. `.github/instructions/` does not exist.
- This codebase has **no** Python, Go, or KIND-cluster tests — those
  parts of the standard workflow are N/A.
- Output suppression in scripts must use `./tmp/null`
  (precreated, gitignored) not `/dev/null` or `/tmp/...` — avoids
  host-approval prompts for non-repo paths.

## 11. Open questions resolved before design

| Question | Resolution |
|---|---|
| Source of truth for perf numbers? | TUI bench (engine-instrumented). Headless is secondary because it under-measures UI work. |
| How to keep results reproducible across SHAs? | Stable JSON schema with `schema_version`, machine + nvim version recorded per result. Variance band documented in T6. |
| Will CI assert on absolute timings? | No. CI only checks the suite executes. All recommendation numbers come from the dev machine. |
| What is "substantial"? | ≥5% of full frame cost or ≥0.1 ms/frame saved. Anything smaller lands in the non-recommendations list. |
| Do tests/perf scripts need to pass existing CI before T7? | Yes — every task pushes and waits for green before advancing. |

This file is the input to `tests/perf/DESIGN.md` (T2).
