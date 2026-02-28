# Manual Testing Guide — Neovim Power Mode PoC

This guide covers how to test both proof-of-concept implementations.

**Target environment**: macOS, iTerm2, tmux (optional), Neovim ≥ 0.9

---

## PoC 1: Pure Lua (`poc-pure-lua/`)

### Setup

Add the plugin to your Neovim runtimepath. Choose **one** of these methods:

**Option A — In your init.lua (recommended):**
```lua
-- In your init.lua:
vim.opt.rtp:prepend(vim.fn.expand("~/Programming/vim-plugin-power-mode/poc-pure-lua"))
```

**Option B — In your init.vim or .vimrc:**
```vim
" In your init.vim or .vimrc:
lua << EOF
vim.opt.rtp:prepend(vim.fn.expand("~/Programming/vim-plugin-power-mode/poc-pure-lua"))
EOF
```

**Option C — Symlink into your plugin directory:**
```bash
ln -s ~/Programming/vim-plugin-power-mode/poc-pure-lua ~/.local/share/nvim/site/pack/dev/start/power-mode
```

### Enable & Test

1. Open Neovim and a file to edit:
   ```bash
   nvim /tmp/test.txt
   ```

2. Enable Power Mode:
   ```vim
   :PowerModeEnable
   ```
   You should see `⚡ Power Mode ENABLED` notification.

3. Enter insert mode (`i`) and start typing rapidly.

### What to Observe

| Feature | What to look for |
|---------|-----------------|
| **Particles** | Small Unicode characters (✦ ✧ ⬥ • · ★ ⚡) flying outward from cursor with neon colors |
| **Particle fade** | Particles should fade out (increasing transparency) as they age |
| **Particle physics** | Particles should arc downward (gravity) and slow down (drag) |
| **Combo counter** | Floating window at top-right showing `COMBO` + number + streak bar |
| **Streak bar** | `████░░░░` bar that drains over ~3 seconds; combo resets when empty |
| **Combo shake** | The combo window should visibly jitter/shake on each keystroke |
| **Shake intensity** | Shake should get stronger as combo level increases |
| **Level colors** | Combo window color changes: green → cyan → pink → purple → red |
| **Exclamations** | At multiples of 10, phrases like "UNSTOPPABLE!" appear briefly |
| **Cursor glow** | Faint colored glow behind cursor position |
| **Glow color** | Changes with combo level |

### Performance Tests

1. **Rapid typing**: Type as fast as you can — are particles smooth or laggy?
2. **Hold a key**: Hold down a letter key — does the engine keep up?
3. **Split windows**: Open `:vsplit` — do particles still appear correctly?
4. **Large file**: Open a file with 1000+ lines — any slowdown?

### tmux Test

If you use tmux:
1. Start tmux: `tmux`
2. Open Neovim inside tmux
3. Enable Power Mode and type — do floating windows render correctly?

### Disable

```vim
:PowerModeDisable
```
or
```vim
:PowerModeToggle
```

### Troubleshooting

| Issue | Fix |
|-------|-----|
| No particles visible | Check `:set rtp?` includes the plugin path |
| Colors look wrong | Ensure `termguicolors` is on: `:set termguicolors` |
| Lua errors | Run `:messages` to see error details |
| Plugin not loading | Run `:lua print(require('power-mode'))` to check |
| Combo window missing | Check terminal is wide enough (≥ 80 columns) |

---

## PoC 2: Low-Level Overlay (`poc-low-level-overlay/`)

> **Architecture note**: The overlay system has two parts:
> 1. **Overlay process** (Swift or Rust) — the visual renderer that draws particles
> 2. **Neovim bridge plugin** (`nvim-plugin/`) — sends keystroke events to the overlay process
> 
> When you use "Method 2" or "Method 3" (with Neovim), you're using the bridge plugin to connect Neovim to an overlay. The bridge is not a separate visual approach.

### 2A: Swift Overlay

#### Build

```bash
cd ~/Programming/vim-plugin-power-mode/poc-low-level-overlay/swift-overlay
chmod +x build.sh
./build.sh
```

This produces `./power-mode-overlay` binary (~195KB).

#### Run

**Method 1 — Test with piped JSON:**
```bash
echo '{"event":"keystroke","row":10,"col":25,"combo":5,"level":1}' | ./power-mode-overlay
```

**Method 2 — Interactive stdin test:**
```bash
./power-mode-overlay
```
Then paste JSON lines:
```json
{"event":"keystroke","row":10,"col":25,"combo":1,"level":0}
{"event":"keystroke","row":10,"col":26,"combo":2,"level":0}
{"event":"keystroke","row":10,"col":27,"combo":3,"level":0}
{"event":"keystroke","row":10,"col":28,"combo":15,"level":1}
{"event":"keystroke","row":10,"col":29,"combo":30,"level":2}
```

**Method 3 — With Neovim bridge:**
```bash
nvim -c "lua vim.opt.rtp:prepend(vim.fn.expand('~/Programming/vim-plugin-power-mode/poc-low-level-overlay/nvim-plugin'))"
```
```vim
:OverlayStart ~/Programming/vim-plugin-power-mode/poc-low-level-overlay/swift-overlay/power-mode-overlay
```

#### What to Observe

- Native macOS transparent window (borderless, click-through)
- GPU-accelerated particles via CAEmitterLayer (or Core Graphics fallback)
- Neon cyberpunk colors (cyan, pink, purple, green)
- Combo counter with shake
- Radial glow effect

### 2B: Rust Overlay

#### Prerequisites

You need Rust installed (`rustup`).

#### Build

```bash
cd ~/Programming/vim-plugin-power-mode/poc-low-level-overlay/rust-overlay
chmod +x build.sh
./build.sh
```

This produces `./power-mode-overlay` binary.

#### Run

**Method 1 — Test with piped JSON:**
```bash
echo '{"event":"keystroke","row":10,"col":25,"combo":5,"level":1}' | ./power-mode-overlay
```

**Method 2 — Interactive stdin test:**
```bash
./power-mode-overlay
```
Then paste JSON lines:
```json
{"event":"keystroke","row":10,"col":25,"combo":1,"level":0}
{"event":"keystroke","row":10,"col":26,"combo":2,"level":0}
{"event":"keystroke","row":10,"col":27,"combo":3,"level":0}
```

**Method 3 — With Neovim bridge:**
```bash
nvim -c "lua vim.opt.rtp:prepend(vim.fn.expand('~/Programming/vim-plugin-power-mode/poc-low-level-overlay/nvim-plugin'))"
```
```vim
:OverlayStart ~/Programming/vim-plugin-power-mode/poc-low-level-overlay/rust-overlay/power-mode-overlay
```

#### What to Observe

- Native macOS transparent window (borderless, click-through)
- Particle effects with neon cyberpunk colors
- Particle trails and glow effects
- Particles following cursor position

---

## Quick Reference

| Command | What it does |
|---------|-------------|
| `:PowerModeEnable` | Enable pure Lua particles + combo + glow |
| `:PowerModeDisable` | Disable pure Lua mode |
| `:PowerModeToggle` | Toggle pure Lua mode |
| `:OverlayStart [cmd]` | Start external overlay process |
| `:OverlayStop` | Stop external overlay process |
| `:OverlayStatus` | Check overlay process status |

## Recording Results

After testing, note these for each approach:

1. **Did it work at all?** (Y/N + any errors)
2. **Visual quality** (1-5 scale)
3. **Performance** (smooth / occasional lag / unusable)
4. **Max particles before lag** (if applicable)
5. **tmux compatibility** (works / broken / partial)
6. **Latency feel** (instant / slight delay / noticeable lag)
7. **Screenshots** (use `Cmd+Shift+4` to capture)
