#!/usr/bin/env bash
# tests/perf/run.sh
#
# Orchestrator for the perf evaluation suite. Runs all benches end-to-end,
# writes per-bench JSON to tests/perf/results/<git-sha>/, then renders a
# concise Markdown summary to tests/perf/results/<git-sha>.md.
#
# Usage:
#   bash tests/perf/run.sh             # full suite
#   PM_PERF_SMOKE=1 bash tests/perf/run.sh   # tiny fast subset (for CI)
#
# Env vars:
#   PM_PERF_SMOKE    "1" => smoke mode: small iter counts, 1 TUI scenario.
#   PM_PERF_OUT_DIR  Override results dir (default: tests/perf/results)
#   PM_PERF_NO_TUI   "1" => skip TUI bench (useful when tmux unavailable).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

mkdir -p ./tmp
: > ./tmp/null

SMOKE="${PM_PERF_SMOKE:-0}"
NO_TUI="${PM_PERF_NO_TUI:-0}"
OUT_DIR_ROOT="${PM_PERF_OUT_DIR:-$REPO_ROOT/tests/perf/results}"

SHA="$(git rev-parse --short HEAD 2>./tmp/null || echo unknown)"
OUT_DIR="$OUT_DIR_ROOT/$SHA"
mkdir -p "$OUT_DIR"

echo "[run] git sha: $SHA"
echo "[run] output:  $OUT_DIR"
echo "[run] smoke:   $SMOKE"
echo "[run] no_tui:  $NO_TUI"

# ---- hotspots ------------------------------------------------------------
if [[ "$SMOKE" == "1" ]]; then
  ITERS=50 WARMUP=10
else
  ITERS=200 WARMUP=50
fi

echo "[run] bench_hotspots (iters=$ITERS warmup=$WARMUP)"
PM_PERF_OUT="$OUT_DIR/hotspots.json" \
PM_PERF_ITERS="$ITERS" PM_PERF_WARMUP="$WARMUP" \
${PM_PERF_SMOKE_SCENARIO:+PM_PERF_SCENARIO="$PM_PERF_SMOKE_SCENARIO"} \
nvim --headless -u tests/minimal_init.lua -l tests/perf/bench_hotspots.lua \
  >./tmp/null 2>&1 || { echo "[run] bench_hotspots FAILED"; exit 1; }

# ---- memory --------------------------------------------------------------
if [[ "$SMOKE" == "1" ]]; then FRAMES=100; else FRAMES=750; fi
echo "[run] bench_memory (frames=$FRAMES)"
PM_PERF_OUT="$OUT_DIR/memory.json" PM_PERF_FRAMES="$FRAMES" \
nvim --headless -u tests/minimal_init.lua -l tests/perf/bench_memory.lua \
  >./tmp/null 2>&1 || { echo "[run] bench_memory FAILED"; exit 1; }

# ---- latency -------------------------------------------------------------
if [[ "$SMOKE" == "1" ]]; then LITERS=30 LWARM=5; else LITERS=100 LWARM=20; fi
echo "[run] bench_latency (iters=$LITERS warmup=$LWARM)"
PM_PERF_OUT="$OUT_DIR/latency.json" \
PM_PERF_ITERS="$LITERS" PM_PERF_WARMUP="$LWARM" \
nvim --headless -u tests/minimal_init.lua -l tests/perf/bench_latency.lua \
  >./tmp/null 2>&1 || { echo "[run] bench_latency FAILED"; exit 1; }

# ---- TUI bench -----------------------------------------------------------
if [[ "$NO_TUI" == "1" ]]; then
  echo "[run] TUI bench: skipped (PM_PERF_NO_TUI=1)"
elif ! command -v tmux >./tmp/null 2>&1; then
  echo "[run] TUI bench: skipped (tmux not installed)"
else
  if [[ "$SMOKE" == "1" ]]; then
    PM_PERF_SCENARIO=light_typing PM_PERF_DURATION=3 PM_PERF_OUT_DIR="$OUT_DIR" \
      bash tests/perf/bench_tui.sh || { echo "[run] bench_tui FAILED"; exit 1; }
  else
    PM_PERF_DURATION="${PM_PERF_DURATION:-6}" PM_PERF_OUT_DIR="$OUT_DIR" \
      bash tests/perf/bench_tui.sh || { echo "[run] bench_tui FAILED"; exit 1; }
  fi
fi

# ---- Markdown summary ----------------------------------------------------
MD_OUT="$OUT_DIR_ROOT/$SHA.md"
echo "[run] rendering markdown summary -> $MD_OUT"
PM_RUN_DIR="$OUT_DIR" PM_MD_OUT="$MD_OUT" PM_SHA="$SHA" \
nvim --headless -u tests/minimal_init.lua -l tests/perf/_render_md.lua \
  >./tmp/null 2>&1 || { echo "[run] markdown render FAILED"; exit 1; }

echo "[run] done"
echo "  JSON dir:  $OUT_DIR"
echo "  Summary:   $MD_OUT"
