#!/usr/bin/env bash
# Interactive visual test guide for neovim-power-mode
# Opens a tmux session with nvim pre-loaded for human visual verification
set -euo pipefail

PLUGIN_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SESSION="pm_visual"

# Cleanup any existing session
tmux kill-session -t "$SESSION" 2>/dev/null || true

echo ""
echo "🎨 neovim-power-mode Visual Test Guide"
echo "   Opening tmux session: $SESSION"
echo ""

SCRATCH=$(mktemp /tmp/pm_visual_XXXXXX.txt)
cat > "$SCRATCH" << 'TEXT'
=== neovim-power-mode Visual Test ===

Type in insert mode to see particles.
Delete text to see fire backspace effect.
Build a combo by typing fast.

Test each style with :PowerModeStyle <name>
Test fire wall with :PowerModeFireWall <mode>

Happy testing!
TEXT

# Create a tmux session with two panes: nvim (main) + instructions (side)
tmux new-session -d -s "$SESSION" -x 200 -y 50

# Launch nvim in the main pane
tmux send-keys -t "$SESSION" \
  "nvim --cmd 'set rtp+=$PLUGIN_DIR' --cmd 'set termguicolors' -u NONE -c 'luafile $PLUGIN_DIR/tests/minimal_init.lua' -c 'lua require(\"power-mode\").setup({auto_enable=true})' $SCRATCH" \
  Enter

# Split right for instructions
tmux split-window -t "$SESSION" -h -l 50

# Show test checklist
tmux send-keys -t "$SESSION" "cat << 'CHECKLIST'
╔═══════════════════════════════════════════════╗
║    neovim-power-mode Visual Test Checklist    ║
╠═══════════════════════════════════════════════╣
║                                               ║
║  1. PARTICLES                                 ║
║     □ Type text → colored particles appear    ║
║     □ Particles explode upward from cursor    ║
║     □ Particles avoid cursor position         ║
║     □ Particles fade out over time            ║
║                                               ║
║  2. STYLES (try each in left pane)            ║
║     :PowerModeStyle explosion                 ║
║     :PowerModeStyle fountain                  ║
║     :PowerModeStyle rightburst                ║
║     :PowerModeStyle shockwave                 ║
║     :PowerModeStyle stars                     ║
║     :PowerModeStyle emoji                     ║
║                                               ║
║  3. COMBO BOX                                 ║
║     □ Combo counter visible (top-right)       ║
║     □ Counter increments on each keystroke    ║
║     □ Color changes at milestones             ║
║     □ Exclamation text appears                ║
║     □ Combo box shakes on keystroke           ║
║     □ Timeout bar depletes                    ║
║                                               ║
║  4. BACKSPACE FIRE                            ║
║     □ Delete text → fire embers appear        ║
║     □ Fire goes downward (not upward)         ║
║                                               ║
║  5. FIRE WALL (cacafire)                      ║
║     :PowerModeFireWall ember_rise             ║
║     :PowerModeFireWall fire_columns           ║
║     :PowerModeFireWall inferno                ║
║     :PowerModeFireWall none                   ║
║     □ Embers rise from bottom edge            ║
║     □ Intensity scales with combo level       ║
║                                               ║
║  6. SHAKE                                     ║
║     :PowerModeShake scroll                    ║
║     □ Screen shakes on keystroke              ║
║     :PowerModeShake none                      ║
║                                               ║
║  7. COLORS                                    ║
║     □ Particles are colorful (not white)      ║
║     □ Combo box is colored                    ║
║     Try: :set notermguicolors                 ║
║     □ Particles still show cterm colors       ║
║                                               ║
║  8. TOGGLE                                    ║
║     :PowerModeDisable                         ║
║     □ All effects stop                        ║
║     :PowerModeEnable                          ║
║     □ Effects resume                          ║
║                                               ║
║  Press q to quit this pane when done.         ║
╚═══════════════════════════════════════════════╝
CHECKLIST
" Enter

echo ""
echo "Attach to the session with:"
echo "  tmux attach-session -t $SESSION"
echo ""
echo "The LEFT pane is nvim (type there)."
echo "The RIGHT pane shows the test checklist."
echo ""
echo "When done: tmux kill-session -t $SESSION"
echo ""

# Attach
tmux select-pane -t "$SESSION:0.0"  # Focus nvim pane
exec tmux attach-session -t "$SESSION"
