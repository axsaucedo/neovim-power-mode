#!/usr/bin/env bash
# tests/perf/bench_tui.sh
#
# TUI frame bench. Drives a real nvim inside tmux while bench_tui_frame.lua
# records per-stage hrtime to JSONL, then summarises into the standard
# schema_version=1 JSON.
#
# Each scenario:
#   1) start tmux session with `nvim -u tests/perf/bench_tui_frame.lua`
#   2) wait for the engine to stabilise
#   3) feed the scenario script (typing / backspace / idle / etc.)
#   4) :qa! cleanly so VimLeavePre flushes the JSONL
#   5) summarise the JSONL into <results>/<scenario>.tui.json
#
# Also samples `ps -o %cpu` of the nvim process at 0.5 s cadence and
# embeds the trace in the result.
#
# Env vars:
#   PM_PERF_OUT_DIR   Output directory (default: ./tests/perf/results)
#   PM_PERF_DURATION  Per-scenario typing duration in seconds (default: 6)
#   PM_PERF_SCENARIO  Run only this scenario id (default: all)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

mkdir -p ./tmp
: > ./tmp/null  # ensure exists for redirection sinks

OUT_DIR="${PM_PERF_OUT_DIR:-$REPO_ROOT/tests/perf/results}"
DURATION="${PM_PERF_DURATION:-6}"
ONLY="${PM_PERF_SCENARIO:-}"
mkdir -p "$OUT_DIR"

git_sha() { git rev-parse --short HEAD 2>./tmp/null || echo unknown; }
iso_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
nvim_ver() { nvim --version | head -1 | awk '{print $2}' | sed 's/^v//'; }
os_name()  { uname -s | tr '[:upper:]' '[:lower:]'; }
arch_name(){ uname -m; }

# Run one scenario in tmux. Args:
#   $1 scenario id
#   $2 "0" | "1"   fire_wall enabled
#   $3 fps
#   $4 typing-script function name (called with no args)
run_scenario() {
  local sid="$1" fw="$2" fps="$3" type_fn="$4"
  local session="pmperf_${sid}_$$"
  local jsonl="$REPO_ROOT/tmp/pm_tui_${sid}.jsonl"
  local cpu_csv="$REPO_ROOT/tmp/pm_tui_${sid}.cpu.csv"
  rm -f "$jsonl" "$cpu_csv"

  echo "[bench_tui] scenario: $sid (fw=$fw fps=$fps duration=${DURATION}s)"

  PM_PERF_SCENARIO="$sid" \
  PM_PERF_OUT="$jsonl" \
  PM_PERF_FPS="$fps" \
  PM_PERF_FIRE_WALL="$fw" \
  tmux new-session -d -s "$session" -x 200 -y 60 \
    "env PM_PERF_SCENARIO='$sid' PM_PERF_OUT='$jsonl' PM_PERF_FPS='$fps' PM_PERF_FIRE_WALL='$fw' \
     nvim -u $REPO_ROOT/tests/perf/bench_tui_frame.lua"

  # Give nvim time to set up.
  sleep 2

  # Locate the nvim PID for cpu sampling.
  local pid
  pid="$(pgrep -P "$(tmux list-panes -t "$session" -F '#{pane_pid}' | head -1)" nvim 2>./tmp/null | head -1 || true)"
  if [[ -z "${pid:-}" ]]; then
    pid="$(pgrep -af 'nvim -u .*bench_tui_frame' | awk '{print $1}' | head -1 || true)"
  fi

  # CPU sampler in background.
  (
    local start_ns
    start_ns="$(perl -MTime::HiRes=time -e 'printf "%d\n", time*1e9' 2>./tmp/null || date +%s%N)"
    while true; do
      if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>./tmp/null; then
        local now_ns
        now_ns="$(perl -MTime::HiRes=time -e 'printf "%d\n", time*1e9' 2>./tmp/null || date +%s%N)"
        local cpu
        cpu="$(ps -p "$pid" -o %cpu= 2>./tmp/null | awk '{print $1}')"
        echo "$((now_ns - start_ns)),${cpu:-0}" >> "$cpu_csv"
      else
        break
      fi
      sleep 0.5
    done
  ) &
  local sampler_pid=$!

  # Drive the scenario.
  "$type_fn" "$session"

  # Quit cleanly so VimLeavePre flushes the JSONL.
  tmux send-keys -t "$session" Escape
  sleep 0.3
  tmux send-keys -t "$session" ":qa!" Enter
  sleep 1.0
  tmux kill-session -t "$session" 2>./tmp/null || true

  kill "$sampler_pid" 2>./tmp/null || true
  wait "$sampler_pid" 2>./tmp/null || true

  summarise "$sid" "$fw" "$fps" "$jsonl" "$cpu_csv"
}

# --- typing scripts --------------------------------------------------------

type_idle() {
  local s="$1"
  sleep "$DURATION"
}

type_light() {
  local s="$1" i
  tmux send-keys -t "$s" "i"
  sleep 0.3
  local end=$(( $(date +%s) + DURATION ))
  while [[ $(date +%s) -lt $end ]]; do
    tmux send-keys -t "$s" "hello world "
    sleep 0.4
  done
}

type_heavy() {
  local s="$1"
  tmux send-keys -t "$s" "i"
  sleep 0.3
  local end=$(( $(date +%s) + DURATION ))
  while [[ $(date +%s) -lt $end ]]; do
    tmux send-keys -t "$s" "the quick brown fox jumps over the lazy dog "
    sleep 0.05
  done
}

type_backspace_storm() {
  local s="$1"
  tmux send-keys -t "$s" "i"
  sleep 0.3
  tmux send-keys -t "$s" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  sleep 0.3
  local end=$(( $(date +%s) + DURATION ))
  while [[ $(date +%s) -lt $end ]]; do
    tmux send-keys -t "$s" BSpace BSpace BSpace BSpace BSpace
    sleep 0.05
  done
}

# --- summariser ------------------------------------------------------------

summarise() {
  local sid="$1" fw="$2" fps="$3" jsonl="$4" cpu_csv="$5"
  local out="$OUT_DIR/${sid}.tui.json"

  if [[ ! -s "$jsonl" ]]; then
    echo "[bench_tui][WARN] empty JSONL for $sid; skipping summary"
    return 0
  fi

  local sha; sha="$(git_sha)"
  local ts;  ts="$(iso_now)"
  local nv;  nv="$(nvim_ver)"
  local osn; osn="$(os_name)"
  local an;  an="$(arch_name)"

  PM_INPUT="$jsonl" PM_CPU="$cpu_csv" PM_OUT="$out" \
  PM_SID="$sid" PM_FW="$fw" PM_FPS="$fps" PM_SHA="$sha" PM_TS="$ts" \
  PM_OS="$osn" PM_ARCH="$an" PM_NVIM="$nv" PM_DUR="$DURATION" \
  nvim --headless -u tests/minimal_init.lua -l tests/perf/_summarise_tui.lua
}

# --- scenarios -------------------------------------------------------------

declare -a SCENARIOS=(
  "idle:0:25:type_idle"
  "light_typing:0:25:type_light"
  "heavy_typing:0:25:type_heavy"
  "heavy_typing_fw:1:25:type_heavy"
  "backspace_storm:1:25:type_backspace_storm"
  "high_fps_heavy:1:60:type_heavy"
)

for entry in "${SCENARIOS[@]}"; do
  IFS=":" read -r sid fw fps fn <<<"$entry"
  if [[ -n "$ONLY" && "$ONLY" != "$sid" ]]; then continue; fi
  run_scenario "$sid" "$fw" "$fps" "$fn"
done

echo "[bench_tui] done; results in $OUT_DIR"
