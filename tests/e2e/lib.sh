#!/usr/bin/env bash
# Shared helpers for neovim-power-mode tmux-driven end-to-end tests.
#
# These tests drive a real nvim process inside a tmux session, interact with
# it via `tmux send-keys`, and assert on the captured pane content. Think of
# them as Playwright-style smoke tests for a terminal UI — slow compared to
# unit tests, but they catch real rendering bugs (like windows that never go
# away) that purely headless Lua tests cannot.
#
# Usage from an individual test script:
#
#   source "$(dirname "$0")/lib.sh"
#   e2e_start_session my_test_name "$INIT_LUA" "$SCRATCH_FILE"
#   e2e_type_insert "hello"
#   out="$(e2e_capture)"
#   e2e_assert_contains "box visible" "COMBO" "$out"
#   e2e_finish

set -euo pipefail

E2E_SESSION=""
E2E_PASS=0
E2E_FAIL=0
E2E_FAILURES=()

# Detect the plugin root (repo root) relative to this lib.
E2E_PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

e2e__cleanup() {
  if [[ -n "$E2E_SESSION" ]]; then
    tmux kill-session -t "$E2E_SESSION" 2>/dev/null || true
  fi
}
trap e2e__cleanup EXIT

# Start a tmux session running nvim with the given init.lua and scratch file.
# Args: <session-prefix> <init-lua-path> <scratch-file-path>
e2e_start_session() {
  local prefix="$1" init_lua="$2" scratch="$3"
  E2E_SESSION="${prefix}_$$"
  tmux new-session -d -s "$E2E_SESSION" -x 200 -y 50
  tmux send-keys -t "$E2E_SESSION" \
    "nvim -u NONE --cmd 'set rtp+=$E2E_PLUGIN_DIR' -c 'luafile $init_lua' $scratch" Enter
  sleep 3
}

# Capture the current pane content.
e2e_capture() {
  tmux capture-pane -t "$E2E_SESSION" -p
}

# Enter insert mode and type the given string.
e2e_type_insert() {
  local text="$1"
  tmux send-keys -t "$E2E_SESSION" Escape
  sleep 0.2
  tmux send-keys -t "$E2E_SESSION" "i"
  sleep 0.2
  tmux send-keys -t "$E2E_SESSION" "$text"
  sleep 0.6
}

# Leave insert mode.
e2e_leave_insert() {
  tmux send-keys -t "$E2E_SESSION" Escape
  sleep 0.2
}

e2e_assert_contains() {
  local label="$1" pattern="$2" haystack="$3"
  if echo "$haystack" | grep -q "$pattern"; then
    echo "  ✅ $label"
    E2E_PASS=$((E2E_PASS + 1))
  else
    echo "  ❌ $label (expected pattern: '$pattern')"
    echo "    --- Pane ---" >&2
    echo "$haystack" >&2
    echo "    ---" >&2
    E2E_FAIL=$((E2E_FAIL + 1))
    E2E_FAILURES+=("$label")
  fi
}

e2e_assert_not_contains() {
  local label="$1" pattern="$2" haystack="$3"
  if echo "$haystack" | grep -q "$pattern"; then
    echo "  ❌ $label (unexpected: '$pattern')"
    echo "    --- Pane ---" >&2
    echo "$haystack" >&2
    echo "    ---" >&2
    E2E_FAIL=$((E2E_FAIL + 1))
    E2E_FAILURES+=("$label")
  else
    echo "  ✅ $label"
    E2E_PASS=$((E2E_PASS + 1))
  fi
}

# Print summary and exit non-zero if any assertion failed.
e2e_finish() {
  tmux send-keys -t "$E2E_SESSION" Escape 2>/dev/null || true
  sleep 0.2
  tmux send-keys -t "$E2E_SESSION" ":qa!" Enter 2>/dev/null || true
  sleep 0.3

  echo ""
  echo "══════════════════════════════════════════"
  echo "Results: $E2E_PASS passed, $E2E_FAIL failed"
  if [ ${#E2E_FAILURES[@]} -gt 0 ]; then
    echo ""
    echo "Failures:"
    for f in "${E2E_FAILURES[@]}"; do echo "  - $f"; done
    exit 1
  fi
  echo "  All assertions passed ✅"
}
