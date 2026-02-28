# Neovim Power Mode Plugin — Implementation Plan

## Problem Statement

Build a Neovim plugin that replicates and exceeds the effects from [activate-power-mode](https://github.com/JoelBesada/activate-power-mode) (Atom) and VS Code's "Power Mode" — featuring animated particle explosions, a large shaking combo counter with exclamation phrases, cyberpunk glow effects, and opacity-based visual overlays triggered on every keystroke. Nothing in the Neovim ecosystem has fully achieved this yet.

## Research Summary

### What activate-power-mode (Atom) Does — Deep Dive
Studied the full source: `JoelBesada/activate-power-mode` (CoffeeScript, Atom API).

**Architecture:**
- **Canvas overlay**: Creates an HTML `<canvas>` absolutely positioned over the editor with `pointer-events: none` and `z-index: 0`. Uses `requestAnimationFrame` for 60fps animation loop. All particles drawn with 2D canvas context.
- **Plugin system**: Modular plugins — `power-canvas`, `combo-mode`, `screen-shake`, `play-audio` — each wired via a plugin manager that dispatches events (`onInput`, `onComboLevelChange`, `onComboMaxStreak`, etc.)
- **Combo renderer**: DOM-based floating container with:
  - "Combo" title, max streak tracker (persisted to localStorage)
  - **Giant 60px counter** with CSS bump animation (scale 1.3x on increment)
  - Streak timeout bar (CSS scaleX transition draining over time)
  - **Exclamation texts** that float up and fade out (CSS `translate3D(0, 100px, 0)` + opacity→0 over 1.5s)
  - **Level system**: Activation thresholds escalate color via CSS `spin()` (hue rotation per level)
  - Retro gaming font: "Press Start 2P"
- **Screen shake**: Applied via CSS `will-change: transform` on the scroll-view, with `shakeScreen(intensity)` API
- **Particle rendering**: Canvas-based with configurable spawn count, size, color (cursor-matched, random, or fixed), and pluggable effect renderers

### VS Code Power Mode
- Same concepts: particle explosions (presets: explosions, fireworks, flames, magic, rift), screen shake, combo counter, custom GIFs
- Uses `TextEditorDecorations` API (web-based, similar canvas overlay approach)

### Existing Neovim Landscape
| Plugin | What it does | Gap |
|--------|-------------|-----|
| `power-mode.nvim` (Nowaaru) | Basic combo bar, minimal effects | No particles, no shake, no glow |
| `cellular-automaton.nvim` | Buffer text transformation animations | Not keystroke-reactive, one-shot |
| `drop.nvim` | Falling characters screensaver | Not interactive |
| `mini.animate` | Smooth cursor/scroll/window animations | No particles or power-mode effects |
| **Neovide** (GUI) | GPU particle trails, smooth cursor | Requires abandoning terminal entirely |

**Conclusion: No existing plugin delivers a true Power Mode experience in terminal Neovim.**

### Technical Feasibility Analysis

#### Neovim APIs Available for Effects

| Capability | API | Suitability |
|-----------|-----|-------------|
| **Particle overlay** | Floating windows (`nvim_open_win`) with `blend` highlights | ✅ Can position anywhere, set transparency |
| **Inline particles** | Extmarks with virtual text (`nvim_buf_set_extmark`, `virt_text`) | ✅ Unicode sparkle/dot characters near cursor |
| **Animation timer** | `vim.loop.new_timer()` (libuv) or `vim.defer_fn` | ✅ ~30fps achievable |
| **Transparency/glow** | Highlight groups with `blend` attribute (0=opaque, 100=transparent) | ✅ Fade-in/out effects |
| **Combo counter** | Floating window with styled buffer content | ✅ Full control over positioning and style |
| **Combo shake** | Jitter the floating combo window's `row`/`col` position via `nvim_win_set_config` | ✅ Smooth and safe (no viewport hack) |
| **Color cycling / glow** | Dynamic highlight group updates via `nvim_set_hl` | ✅ Can cycle colors per-frame |
| **Cursor tracking** | `CursorMovedI`, `InsertCharPre`, `TextChangedI` autocmds | ✅ Reliable keystroke detection |

#### Key Limitations
- **Terminal = text cells only**: No true pixel rendering; particles must be Unicode characters (sparkles ✦✧⬥•·★☆⚡🔥💥 etc.)
- **Frame rate ceiling**: ~20-30fps practical max before event loop contention
- **No native per-window alpha**: Only `blend` on highlight groups (works well enough)

---

## Architecture Options (For Approval)

### Option A: Pure Lua Terminal Plugin (Recommended Starting Point)
**The core plugin — works in any terminal + Neovim ≥0.9**

All effects rendered using Neovim's native Lua API:
- Particle system using floating windows with Unicode characters and `blend` highlights
- **Large combo counter + exclamation phrases in a floating window — the combo UI itself shakes** (not the editor viewport)
- Cyberpunk glow via dynamic highlight color cycling
- All in Lua, no external dependencies

**Pros**: Works everywhere, single plugin install, pure Lua
**Cons**: Limited to text-cell resolution for particles

### Option B: Neovide-Aware Enhanced Mode
**Extends Option A — detects Neovide and unlocks GPU-powered effects**

When running inside Neovide:
- Programmatically toggle `g:neovide_cursor_vfx_mode` (railgun/torpedo/pixiedust)
- Adjust `g:neovide_cursor_vfx_particle_density`, opacity, speed per combo level
- Enable `g:neovide_cursor_trail_size` for motion blur

Falls back to Option A's text-based effects in terminal.

**Pros**: Best visual quality possible, GPU-accelerated particles
**Cons**: Requires Neovide as the frontend

### Option C: External Transparent Overlay Process
**Companion native binary that renders real graphics on top of the terminal**

- A separate **Rust** binary (`power-mode-overlay`) creates a transparent OS-level window
  - Rust chosen for: GPU access via `wgpu`/`skia-safe`, low latency, cross-platform, no GC
  - **Prototyping**: Can start with Python (pygame/tkinter) to validate the approach quickly, then rewrite in Rust
  - **Alternative languages considered**: Go (viable for prototype, limited GPU libs), C/C++ (viable but Rust is safer and equally fast)
- Positioned on top of the terminal window, tracks its geometry
- Neovim sends cursor position events over RPC (msgpack or Unix socket)
- Overlay renders true pixel-based particle effects, explosions, sprites with GPU acceleration
- macOS: Cocoa `NSWindow` with `NSWindowLevelFloating` + `isOpaque=false`; Linux: X11 composite overlay / Wayland layer-shell

**Pros**: True pixel graphics, unlimited visual potential, real particle physics with thousands of particles
**Cons**: Platform-specific, requires companion binary install, window tracking complexity

---

## Recommended Approach: Build Option A First, Then Layer B and C

Build the plugin in three phases, each shippable independently.

---

## Phase 1: Core Engine & Particle System

### 1.1 Plugin Scaffold
- Create standard Neovim plugin structure: `lua/power-mode/init.lua`, `plugin/power-mode.lua`
- Setup configuration system with `vim.g.power_mode_*` variables and `setup({})` function
- Register autocmds for keystroke detection: `InsertCharPre`, `TextChangedI`, `CursorMovedI`

### 1.2 Particle Engine
- Implement a particle system manager in `lua/power-mode/particles.lua`
- Each particle: `{ x, y, vx, vy, char, lifetime, max_lifetime, color_idx }`
- On each keystroke: spawn N particles at cursor position with random velocity vectors
- Animation loop via `vim.loop.new_timer()` at ~25fps:
  - Update particle positions (apply velocity + gravity + drag)
  - Remove expired particles
  - Render surviving particles as floating windows (1x1 character) with `blend` highlights
- Particle character sets (configurable):
  - `sparks`: `{"⬥", "✦", "✧", "•", "·", "∗"}`
  - `fire`: `{"🔥", "⬥", "★", "☆", "·"}`
  - `stars`: `{"★", "☆", "✦", "✧", "✶", "✴"}`
  - `blocks`: `{"█", "▓", "▒", "░"}`
  - `cyberpunk`: `{"⚡", "◈", "◆", "⬥", "⬦", "△"}`

### 1.3 Particle Rendering Strategy
- **Primary method**: Each particle = one floating window (1 col × 1 row, `style=minimal`, no border)
  - Set `winblend` for transparency fade as particle ages
  - Set highlight group with `blend` + color matching particle type
  - Close window when particle dies
- **Optimization**: Pool floating windows (reuse instead of create/destroy)
  - Pre-allocate a pool of ~50-100 floating windows
  - Mark as available/in-use
  - Only create new ones if pool exhausted
- **Alternative for dense effects**: Single large floating window with a scratch buffer
  - Place particles as characters at computed positions within the buffer
  - Single window = fewer API calls
  - Tradeoff: coarser positioning, but better for "explosion" bursts

### 1.4 Color & Glow System
- Define a palette of highlight groups: `PowerModeParticle1` through `PowerModeParticle10`
- Each with different `fg`, `bg=NONE`, and `blend` values
- Cyberpunk palette: neon cyan `#00FFFF`, hot pink `#FF1493`, electric purple `#BF00FF`, neon green `#39FF14`
- Glow effect: create a 3×3 floating window behind the cursor with a bright background + high `blend`
  - This simulates a "glow" or "aura" around the typing position
  - Color cycles based on combo level

## Phase 2: Combo System (with Shake) & Cyberpunk Theme

### 2.1 Combo Counter — Large Display with Shake & Exclamations

Inspired by activate-power-mode's combo renderer, but adapted for Neovim floating windows.

**Combo Floating Window:**
- **Large floating window** (configurable size, e.g. 25 cols × 8 rows) positioned top-right of editor
- Contents rendered with multiple styled lines:
  - Line 1: `"COMBO"` title text (small, dim)
  - Line 2: **Giant combo number** using big Unicode block art or large highlight text (e.g., `"██ 47 ██"`)
  - Line 3: Streak timeout bar rendered as `"████████░░░░"` (filled portion shrinks over time)
  - Line 4: Max streak: `"MAX 142"`
  - Line 5+: **Exclamation phrases** that appear on milestones

**Shake the Combo Window (NOT the editor viewport):**
- On each keystroke while combo is active, jitter the combo floating window position:
  - Use `vim.api.nvim_win_set_config(win, { relative="editor", row=base_row + random(-2,2), col=base_col + random(-2,2) })`
  - Shake intensity scales with combo level
  - Return to base position after 50-80ms via timer
  - This is smooth, safe, and doesn't disturb the editing area at all
- On milestone hits (25x, 50x, 100x), do a larger "slam" shake (±4-6 cells)

**Exclamation Phrases:**
- Configurable list, e.g.: `{"UNSTOPPABLE!", "GODLIKE!", "RAMPAGE!", "MEGA KILL!", "DOMINATING!", "WICKED SICK!"}`
- Displayed inside or below the combo window with fade-out animation (reduce blend over ~1.5s)
- On combo milestones, show phrases; on every Nth keystroke show `"+1"` / `"+5"` increments
- Color escalation per level: green → yellow → orange → red → purple → rainbow cycle

**Level System (following activate-power-mode pattern):**
- Thresholds: `[10, 25, 50, 100, 200]`
- Each level changes: particle colors, particle count multiplier, combo window color, exclamation frequency
- Level transitions show special exclamation: `"2x MULTIPLIER!"`, `"3x MULTIPLIER!"`

**Combo Counter Bump Animation:**
- On each increment, briefly scale the counter text appearance:
  - Frame 1: Replace counter line with a slightly different rendering (e.g., extra padding/border chars)
  - Frame 2: Restore to normal
  - Creates a visual "bump" similar to activate-power-mode's CSS `scale(1.3)` animation

### 2.2 Cyberpunk Theme Integration
- Optional dark base colorscheme with neon accents:
  - Background: `#0a0a0f` (near-black with blue tint)
  - Foreground: `#e0e0e0`
  - Keywords: neon cyan `#00FFFF`
  - Strings: neon pink `#FF1493`
  - Comments: dim purple `#6B5B95`
- Glow cursor line: `CursorLine` highlight with subtle neon `bg` and `blend`
- Scanline effect (optional): extmarks with very faint horizontal lines via virtual text

## Phase 3: Advanced Effects & Multi-Backend Support

### 3.1 Neovide Detection & GPU Effects (Option B)
- Detect Neovide: `vim.g.neovide ~= nil`
- When detected, dynamically configure:
  ```lua
  vim.g.neovide_cursor_vfx_mode = "railgun" -- escalate: torpedo → pixiedust at higher combos
  vim.g.neovide_cursor_vfx_particle_density = 7.0 + (combo * 0.5)
  vim.g.neovide_cursor_vfx_opacity = 200.0
  vim.g.neovide_cursor_trail_size = 0.8
  ```
- Disable text-based particles when Neovide GPU particles active (avoid doubling)
- Still use the Lua combo counter and glow (Neovide doesn't have those)

### 3.2 Effect Presets
- **Explosion**: Large burst of particles outward from cursor, fast decay
- **Fireworks**: Particles rise then burst at peak height
- **Flames**: Particles drift upward with warm color gradient
- **Matrix Rain**: Green characters fall downward from cursor position
- **Lightning**: Brief extmark-based flash lines extending from cursor
- **Shockwave**: Ring of particles expanding outward (hollow circle)

### 3.3 Sound Effects (Optional)
- Play keystroke sounds via system command (`afplay` on macOS, `aplay` on Linux)
- Short click/pop sounds on each keystroke
- Special sounds on combo milestones
- Disabled by default; opt-in via config

### 3.4 External Overlay Process (Option C)

**Prototyping (Python):**
- Quick prototype with Python + pygame or tkinter to validate:
  - Transparent window creation on macOS/Linux
  - Neovim RPC connection and cursor position tracking
  - Basic particle rendering
- Purpose: prove the concept, identify platform-specific issues

**Production Implementation (Rust):**
- Separate Rust binary: `power-mode-overlay`
- Crate dependencies: `wgpu` or `skia-safe` for GPU rendering, `winit` for windowing, `neovim-lib` or raw msgpack-rpc for Neovim communication
- Architecture:
  ```
  Neovim (Lua plugin) ──RPC/socket──> power-mode-overlay (Rust)
       │                                    │
       │ sends: cursor_pos, combo_level,    │ renders: GPU particles,
       │        keystroke events             │          explosions, glow
       │                                    │          on transparent window
  ```
- Platform support:
  - **macOS**: Cocoa `NSWindow` with `backgroundColor = .clear`, `isOpaque = false`, `level = .floating`; track terminal window via Accessibility API or AppleScript
  - **Linux X11**: `_NET_WM_WINDOW_TYPE_DOCK` or composite overlay with `XComposite`; ARGB visual
  - **Linux Wayland**: Layer shell protocol (`zwlr_layer_shell_v1`) for overlay surface
- Features: true pixel particles (thousands), GPU-accelerated, sprite-based explosions, glow shaders, motion blur
- Distribution: pre-built binaries via GitHub Releases, or `cargo install power-mode-overlay`

**Alternative language considerations:**
- **Go**: Good for prototyping, `ebiten` game library for rendering, but less mature GPU access
- **C/C++**: Maximum control, SDL2/OpenGL viable, but Rust preferred for safety and modern tooling
- **Zig**: Viable but smaller ecosystem

---

## File Structure

```
vim-plugin-power-mode/
├── plugin/
│   └── power-mode.lua              # Plugin entry point, autocmds, commands
├── lua/
│   └── power-mode/
│       ├── init.lua                 # Setup, config merging, public API
│       ├── config.lua               # Default configuration & validation
│       ├── engine.lua               # Core animation loop & frame management
│       ├── particles.lua            # Particle system (spawn, update, physics)
│       ├── renderer.lua             # Floating window management & rendering
│       ├── combo.lua                # Combo counter, level system, shake & exclamations
│       ├── glow.lua                 # Cursor glow & color cycling
│       ├── highlights.lua           # Dynamic highlight group management
│       ├── presets.lua              # Effect presets (explosion, fireworks, etc.)
│       ├── neovide.lua              # Neovide-specific GPU effect integration
│       ├── overlay.lua              # External overlay process management (Option C)
│       └── utils.lua                # Math helpers, random, easing functions
├── overlay/                         # Option C: External overlay companion
│   ├── prototype/                   # Python prototype
│   │   ├── main.py
│   │   └── requirements.txt
│   └── rust/                        # Production Rust implementation
│       ├── Cargo.toml
│       └── src/
│           ├── main.rs
│           ├── particles.rs
│           ├── window.rs
│           └── nvim_rpc.rs
├── colors/
│   └── power-mode-cyberpunk.lua     # Optional cyberpunk colorscheme
├── README.md
├── LICENSE
└── doc/
    └── power-mode.txt               # Vim help documentation
```

## Configuration API (Draft)

```lua
require('power-mode').setup({
  enabled = true,

  -- Particle settings
  particles = {
    enabled = true,
    preset = "explosion",       -- "explosion" | "fireworks" | "flames" | "matrix" | "lightning" | "shockwave"
    charset = "sparks",         -- "sparks" | "fire" | "stars" | "blocks" | "cyberpunk" | custom table
    count = { min = 3, max = 8 },  -- particles per keystroke
    lifetime = { min = 300, max = 800 },  -- ms
    speed = { min = 1.0, max = 4.0 },
    gravity = 0.15,
    drag = 0.95,
    colors = { "#00FFFF", "#FF1493", "#BF00FF", "#39FF14", "#FF6600" },
  },

  -- Combo counter (with shake)
  combo = {
    enabled = true,
    timeout = 3000,             -- ms before combo resets
    position = "top-right",     -- "top-right" | "bottom-right" | "cursor" | {row, col}
    size = { width = 25, height = 8 },
    shake = {
      enabled = true,
      intensity = 2,            -- cells of jitter
      milestone_intensity = 5,  -- cells of jitter on milestones
      decay = 0.9,
    },
    levels = { 10, 25, 50, 100, 200 },  -- activation thresholds
    exclamations = {
      enabled = true,
      every = 10,               -- show exclamation every N keystrokes
      texts = {
        "UNSTOPPABLE!", "GODLIKE!", "RAMPAGE!", "MEGA KILL!",
        "DOMINATING!", "WICKED SICK!", "LEGENDARY!", "BEYOND GODLIKE!",
      },
    },
    max_streak = {
      persist = true,           -- save max streak across sessions
    },
  },

  -- Glow effect
  glow = {
    enabled = true,
    color = "#00FFFF",
    intensity = 0.3,            -- blend value (lower = more visible)
    radius = 1,                 -- cells around cursor
  },

  -- Cyberpunk theme
  theme = {
    enabled = false,            -- opt-in cyberpunk colorscheme
  },

  -- Neovide (Option B)
  neovide = {
    auto_detect = true,
    vfx_mode = "railgun",
    escalate_with_combo = true,
  },

  -- External overlay (Option C)
  overlay = {
    enabled = false,
    binary = "power-mode-overlay",  -- path to companion binary
    auto_start = true,
  },

  -- Sound effects
  sound = {
    enabled = false,
    volume = 0.5,
    clip = "typewriter",        -- "typewriter" | "mechanical" | custom path
  },

  -- Performance
  performance = {
    fps = 25,
    max_particles = 100,
    pool_size = 60,             -- pre-allocated floating windows
  },
})
```

## Implementation Todos

1. **plugin-scaffold** — Create plugin directory structure, entry point, setup function, and config system
2. **animation-engine** — Build the core animation loop with `vim.loop.new_timer()`, frame timing, and cleanup
3. **particle-system** — Implement particle spawning, physics (velocity, gravity, drag), and lifecycle management
4. **floating-window-renderer** — Build floating window pool, render particles as 1×1 windows with blend highlights
5. **keystroke-detection** — Wire up autocmds (`InsertCharPre`, `TextChangedI`) to trigger particle spawns at cursor position
6. **combo-counter** — Build combo tracker with levels, timeout, max streak, exclamation phrases, large floating window display, and **combo window shake** (jitter the combo floating window position on keystroke, intensifying with combo level)
7. **glow-effect** — Implement cursor glow via a blended floating window behind cursor, with color cycling
8. **highlight-system** — Create dynamic highlight groups for particles, combo, and glow with cyberpunk palette
9. **presets** — Implement multiple effect presets (explosion, fireworks, flames, matrix, lightning, shockwave)
10. **neovide-integration** — Detect Neovide and dynamically configure GPU cursor VFX based on combo level
11. **cyberpunk-colorscheme** — Create optional cyberpunk dark theme with neon accents
12. **overlay-prototype** — Build Python prototype for transparent overlay window (validate concept: RPC connection, cursor tracking, basic particles)
13. **overlay-rust** — Build production Rust binary with GPU-accelerated particle rendering, transparent window overlay, and Neovim RPC integration
14. **documentation** — Write README with demos, configuration reference, and Vim help file
15. **testing-polish** — Test across terminals (kitty, alacritty, iTerm2, wezterm), optimize performance, handle edge cases

## Dependencies Between Todos
- `animation-engine` depends on `plugin-scaffold`
- `particle-system` depends on `animation-engine`
- `floating-window-renderer` depends on `plugin-scaffold`
- `keystroke-detection` depends on `plugin-scaffold`
- `combo-counter` depends on `keystroke-detection`, `animation-engine`
- `glow-effect` depends on `animation-engine`, `floating-window-renderer`
- `highlight-system` depends on `plugin-scaffold`
- `presets` depends on `particle-system`
- `neovide-integration` depends on `combo-counter`, `presets`
- `cyberpunk-colorscheme` depends on `highlight-system`
- `overlay-prototype` depends on `plugin-scaffold`
- `overlay-rust` depends on `overlay-prototype`
- `documentation` depends on all features
- `testing-polish` depends on all features

