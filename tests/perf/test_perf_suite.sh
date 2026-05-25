#!/usr/bin/env bash
# tests/perf/test_perf_suite.sh
#
# Self-validation of the perf evaluation suite. Verifies that the suite
# itself is sound BEFORE we trust the numbers it produces. Three checks:
#
#   1. Schema conformance: every result JSON in tests/perf/results/<sha>/
#      parses, has schema_version==1, and contains the expected stage keys.
#   2. Reproducibility: a single hotspots scenario run twice has p50 of
#      FULL_frame within ±15% of the median (DESIGN.md §6). Defends
#      against accidental dependence on warm caches, RNG seeds, etc.
#   3. Instrumentation overhead: per-iter hrtime() bookends add <=10%
#      to FULL_frame vs an unwrapped tight loop. Confirms the
#      measurement apparatus does not dominate the signal.
#
# Designed to be cheap (<60s) so it can run in CI after the smoke suite.
# Does NOT assert absolute timings — only relative properties of the
# measurement apparatus.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"
mkdir -p ./tmp
: > ./tmp/null

SHA="$(git rev-parse --short HEAD 2>./tmp/null || echo unknown)"
DIR="tests/perf/results/$SHA"

PASS=0
FAIL=0
FAIL_LABELS=()
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); FAIL_LABELS+=("$1"); }

# Pre-req: smoke run produced output. If not, do it now (skip TUI for speed).
if [[ ! -d "$DIR" ]]; then
  echo "[validate] no prior run; invoking smoke run"
  PM_PERF_SMOKE=1 PM_PERF_NO_TUI=1 bash tests/perf/run.sh >./tmp/null 2>&1
fi

# Helper: run validator script and capture stdout; checks for the
# literal token PASS|OK from the script.
run_lua() {
  local script="$1"; shift
  nvim --headless -u tests/minimal_init.lua -l "$script" "$@" 2>&1
}

# ---- 1/3 schema conformance ---------------------------------------------
echo "[validate] 1/3 schema conformance"

check_one() {
  local label="$1" path="$2" stage="$3"
  local out
  out="$(PM_VAL_PATH="$path" PM_VAL_STAGE="$stage" \
        run_lua tests/perf/_validate_schema.lua || echo "FAIL_EXIT")"
  if echo "$out" | grep -q '^OK$'; then
    ok "$label"
  else
    fail "$label ($(echo "$out" | tail -3 | tr '\n' '|'))"
  fi
}

check_one "hotspots.json schema + FULL_frame stage" "$DIR/hotspots.json" "FULL_frame"
check_one "memory.json schema + memory stage"       "$DIR/memory.json"   "memory"
check_one "latency.json schema + spawn_to_render"   "$DIR/latency.json"  "spawn_to_render"

# ---- 2/3 reproducibility -------------------------------------------------
echo "[validate] 2/3 reproducibility (single scenario, 2 runs, ±15% on p50)"

rm -f ./tmp/repro_a.json ./tmp/repro_b.json
PM_PERF_OUT=./tmp/repro_a.json PM_PERF_SCENARIO=particles+combo+fire_wall \
  PM_PERF_ITERS=120 PM_PERF_WARMUP=30 \
  nvim --headless -u tests/minimal_init.lua -l tests/perf/bench_hotspots.lua \
  >./tmp/null 2>&1
PM_PERF_OUT=./tmp/repro_b.json PM_PERF_SCENARIO=particles+combo+fire_wall \
  PM_PERF_ITERS=120 PM_PERF_WARMUP=30 \
  nvim --headless -u tests/minimal_init.lua -l tests/perf/bench_hotspots.lua \
  >./tmp/null 2>&1

repro_out="$(PM_REPRO_A=./tmp/repro_a.json PM_REPRO_B=./tmp/repro_b.json \
  run_lua tests/perf/_validate_repro.lua || true)"
echo "    $(echo "$repro_out" | head -2)"
if echo "$repro_out" | grep -q '^PASS$'; then
  ok "reproducibility within ±15%"
else
  fail "reproducibility band exceeded"
fi

# ---- 3/3 instrumentation overhead ---------------------------------------
echo "[validate] 3/3 instrumentation overhead (≤10% on FULL_frame)"

overhead_out="$(run_lua tests/perf/_validate_overhead.lua || true)"
echo "    $(echo "$overhead_out" | head -2)"
if echo "$overhead_out" | grep -q '^PASS$'; then
  ok "instrumentation overhead ≤10%"
else
  fail "instrumentation overhead band exceeded"
fi

# ---- summary -------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════"
echo "Perf suite self-validation: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  for l in "${FAIL_LABELS[@]}"; do echo "  - $l"; done
  exit 1
fi
echo "  All checks passed ✅"
