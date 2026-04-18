#!/usr/bin/env bash
# E2E test for combo.combo_box_disappear_seconds.
#
# Drives nvim inside tmux and verifies the combo floating window's three
# lifecycle states: visible while typing → hidden after timeout + linger →
# visible again on a new keystroke.
#
# Run manually:   bash tests/e2e/test_combo_hide.sh
# CI-friendly:    exits 0 on success, 1 on any assertion failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/e2e/lib.sh
source "$SCRIPT_DIR/lib.sh"

SCRATCH="$(mktemp)"
INIT_LUA="$(mktemp -t pm_combo_hide_init.XXXX).lua"
trap 'rm -f "$SCRATCH" "$INIT_LUA"' EXIT

# Short combo.timeout + linger so wall-clock stays small (~5s).
cat > "$INIT_LUA" <<LUA
vim.opt.rtp:prepend("$E2E_PLUGIN_DIR")
vim.cmd("runtime plugin/power-mode.lua")
require("power-mode").setup({
  combo = {
    timeout = 1500,
    combo_box_disappear_seconds = 1,
    shake = false,
  },
  particles = { count = { 1, 2 } },
  engine = { stop_delay = 200 },
})
LUA

echo ""
echo "🔬 E2E: combo_box_disappear_seconds"
echo "   Plugin : $E2E_PLUGIN_DIR"
echo ""

e2e_start_session "pm_combo_hide" "$INIT_LUA" "$SCRATCH"

echo "▶ Phase 1: typing → COMBO box visible"
e2e_type_insert "hello power mode"
e2e_assert_contains "COMBO visible while typing" "COMBO" "$(e2e_capture)"

echo "▶ Phase 2: idle → COMBO box hidden after timeout + linger"
e2e_leave_insert
# timeout (1s) + linger (1s) + render/event headroom.
sleep 3.5
e2e_assert_not_contains "COMBO hidden after timeout + linger" "COMBO" "$(e2e_capture)"

echo "▶ Phase 3: new keystroke → COMBO box reappears"
e2e_type_insert "again"
e2e_assert_contains "COMBO reappears on new keystroke" "COMBO" "$(e2e_capture)"

e2e_finish
