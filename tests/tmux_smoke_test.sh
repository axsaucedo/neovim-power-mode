#!/usr/bin/env bash
# Automated tmux smoke test for neovim-power-mode
# Tests: plugin loads, commands work, no errors during typing
# Usage: bash tests/tmux_smoke_test.sh [path/to/plugin]
set -euo pipefail

PLUGIN_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SESSION="pm_smoke_$$"
PASS=0
FAIL=0
ERRORS=()

cleanup() { tmux kill-session -t "$SESSION" 2>/dev/null || true; }
trap cleanup EXIT

log_pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
log_fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

assert_contains() {
  local label="$1" pattern="$2" haystack="$3"
  if echo "$haystack" | grep -q "$pattern"; then
    log_pass "$label"
  else
    log_fail "$label (expected pattern: '$pattern')"
    echo "    --- Captured ---" >&2
    echo "$haystack" | tail -15 >&2
    echo "    ---" >&2
  fi
}

assert_not_contains() {
  local label="$1" pattern="$2" haystack="$3"
  if echo "$haystack" | grep -qE "$pattern"; then
    log_fail "$label (found unexpected: '$pattern')"
    echo "    --- Captured ---" >&2
    echo "$haystack" | grep -E "$pattern" | head -5 >&2
    echo "    ---" >&2
  else
    log_pass "$label"
  fi
}

send_cmd() {
  # Send Escape first to ensure normal mode, then the command
  tmux send-keys -t "$SESSION" Escape ""
  sleep 0.2
  tmux send-keys -t "$SESSION" ":$1" Enter
  sleep "${2:-1}"
}

capture() { tmux capture-pane -t "$SESSION" -p; }

# Get :messages content via nvim's redir
get_messages() {
  send_cmd 'redir => g:_smoke_msgs | silent messages | redir END | call writefile([get(g:,"_smoke_msgs","")], "/tmp/pm_smoke_msgs.txt")' 0.5
  cat /tmp/pm_smoke_msgs.txt 2>/dev/null | tr -d '\000' || echo ""
}

echo ""
echo "🔬 neovim-power-mode smoke tests"
echo "   Plugin: $PLUGIN_DIR"
echo ""

# ── Launch nvim ───────────────────────────────────────────────────────────────
echo "▶ Launching nvim..."
SCRATCH=$(mktemp)
tmux new-session -d -s "$SESSION" -x 200 -y 50
tmux send-keys -t "$SESSION" \
  "nvim --cmd 'set rtp+=$PLUGIN_DIR' -u NONE -c 'luafile $PLUGIN_DIR/tests/minimal_init.lua' $SCRATCH" \
  Enter
sleep 4  # nvim start + plugin load

# ── Test 1: Clean load ────────────────────────────────────────────────────────
echo "▶ Test 1: Plugin loads cleanly"
OUT=$(capture)
assert_not_contains "No E5107/load errors" "E5107|E5113|Error loading|stack traceback" "$OUT"

# ── Test 2: PowerModeEnable (without prior setup — auto-init test) ────────────
echo "▶ Test 2: :PowerModeEnable (no prior setup)"
send_cmd "PowerModeEnable" 1.5
MSGS=$(get_messages)
assert_contains "Enable notification" "Power Mode" "$MSGS"
assert_not_contains "No errors on enable" "E[0-9][0-9][0-9]:|stack traceback" "$MSGS"

# ── Test 3: PowerModeStatus ───────────────────────────────────────────────────
echo "▶ Test 3: :PowerModeStatus"
send_cmd "PowerModeStatus" 1.5
OUT=$(capture)
assert_contains "Status shows Enabled" "Enabled:" "$OUT"
assert_contains "Status shows preset" "Particle preset:" "$OUT"

# Press enter to dismiss status (if pager open)
tmux send-keys -t "$SESSION" Enter ""
sleep 0.3

# ── Test 4: Switch style ──────────────────────────────────────────────────────
echo "▶ Test 4: :PowerModeStyle fountain"
send_cmd "PowerModeStyle fountain" 1
MSGS=$(get_messages)
assert_contains "Style switch notification" "fountain" "$MSGS"
assert_not_contains "No error on style switch" "E[0-9][0-9][0-9]:|stack traceback" "$MSGS"

# ── Test 5: Typing in insert mode ─────────────────────────────────────────────
echo "▶ Test 5: Typing in insert mode triggers no errors"
tmux send-keys -t "$SESSION" Escape ""
sleep 0.3
tmux send-keys -t "$SESSION" "i" ""   # Enter insert mode
sleep 0.3
tmux send-keys -t "$SESSION" "hello power mode" ""
sleep 1
tmux send-keys -t "$SESSION" Escape ""
sleep 0.5
MSGS=$(get_messages)
assert_not_contains "No errors during typing" "E[0-9][0-9][0-9]:|stack traceback" "$MSGS"

# ── Test 6: PowerModeDisable ──────────────────────────────────────────────────
echo "▶ Test 6: :PowerModeDisable"
send_cmd "PowerModeDisable" 1.5
MSGS=$(get_messages)
assert_contains "Disable notification" "Power Mode" "$MSGS"
assert_not_contains "No errors on disable" "stack traceback" "$MSGS"

# ── Test 7: PowerModeToggle ───────────────────────────────────────────────────
echo "▶ Test 7: :PowerModeToggle (on/off)"
send_cmd "PowerModeToggle" 1
send_cmd "PowerModeToggle" 1
MSGS=$(get_messages)
assert_not_contains "No errors on toggle" "E[0-9][0-9][0-9]:|stack traceback" "$MSGS"

# ── Test 8: PowerModeStyle switching ─────────────────────────────────────────
echo "▶ Test 8: Style presets load without error"
for STYLE in explosion rightburst shockwave stars emoji; do
  send_cmd "PowerModeStyle $STYLE" 0.5
done
MSGS=$(get_messages)
assert_not_contains "No errors switching presets" "E[0-9][0-9][0-9]:|stack traceback" "$MSGS"

# ── Test 9: PowerModeFireWall on/off ──────────────────────────────────────────
echo "▶ Test 9: :PowerModeFireWall modes"
for MODE in on off; do
  send_cmd "PowerModeFireWall $MODE" 0.5
done
MSGS=$(get_messages)
assert_contains "Fire wall mode set" "Fire wall:" "$MSGS"
assert_not_contains "No errors switching fire wall modes" "E[0-9][0-9][0-9]:|stack traceback" "$MSGS"

# ── Test 10: Status shows fire wall ──────────────────────────────────────────
echo "▶ Test 10: Status shows fire wall mode"
send_cmd "PowerModeStatus" 1.5
OUT=$(capture)
assert_contains "Status shows fire wall" "Fire wall:" "$OUT"
tmux send-keys -t "$SESSION" Enter ""
sleep 0.3

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -f "$SCRATCH" /tmp/pm_smoke_msgs.txt

echo ""
echo "══════════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
if [ ${#ERRORS[@]} -gt 0 ]; then
  echo ""
  echo "Failures:"
  for e in "${ERRORS[@]}"; do echo "  - $e"; done
  echo ""
  exit 1
else
  echo "  All smoke tests passed ✅"
  echo ""
fi
