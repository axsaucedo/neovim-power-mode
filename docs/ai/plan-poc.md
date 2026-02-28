# Neovim Power Mode Plugin — Proof of Concept Plan

## Goal

Before committing to full development, build **two proof-of-concept implementations** that explore the full extent of what's possible for a Power Mode experience in terminal Neovim.

- **`poc-pure-lua/`**: Pure Neovim Lua plugin — floating windows, extmarks, blend, timers
- **`poc-low-level-overlay/`**: External transparent overlay on macOS + iTerm2 image protocol experiments — real pixel-based graphics

Each PoC implements **all core features at once** (particles, combo counter with shake, glow) in a single implementation pass. This is about **experimentation**, not polish.

A `MANUAL_TESTING.md` will be provided at the repo root with exact instructions for testing both PoCs in your own Neovim setup.

**Target environment**: macOS, iTerm2, tmux, Neovim ≥ 0.9

---

## Research Summary

### Reference Implementations Studied

**activate-power-mode (Atom)** — `JoelBesada/activate-power-mode`:
- Canvas overlay (`<canvas>` with `pointer-events: none`) using `requestAnimationFrame` for 60fps
- Giant 60px combo counter with CSS bump animation (scale 1.3x), streak timeout bar, exclamation phrases floating up and fading out
- Level system: activation thresholds escalate color via CSS `spin()` (hue rotation)
- Screen shake via CSS `will-change: transform` on scroll-view
- Retro gaming font: "Press Start 2P"
- Modular plugin architecture: `power-canvas`, `combo-mode`, `screen-shake`, `play-audio`

**VS Code Power Mode**: Same concepts via `TextEditorDecorations` API — particles, shake, combo, custom GIFs

### Neovim Technical Capabilities (for PoC A)

| Capability | API | Notes |
|-----------|-----|-------|
| Particle overlay | `nvim_open_win()` floating windows | Position anywhere, 1×1 char, `style=minimal` |
| Transparency | `winblend` + highlight `blend` attr | 0=opaque, 100=transparent; fade particles as they age |
| Animation | `vim.loop.new_timer()` (libuv) | ~25-30fps practical max |
| Glow | Floating window with bright `bg` + high `blend` | Simulates aura/glow behind cursor |
| Combo shake | `nvim_win_set_config()` to jitter row/col | Smooth, safe — shake the combo window, not the viewport |
| Color cycling | `nvim_set_hl()` per-frame updates | Dynamic highlight group color changes |
| Keystroke detection | `InsertCharPre`, `TextChangedI` autocmds | Reliable |
| Inline virtual text | `nvim_buf_set_extmark` with `virt_text` | Unicode particles near cursor |

**Limitations**: Text-cell resolution only, ~25fps ceiling, no native per-window alpha (only blend)

### macOS Overlay Capabilities (for PoC C)

| Capability | Approach | Notes |
|-----------|----------|-------|
| Transparent overlay | `NSWindow` with `backgroundColor=.clear`, `isOpaque=false` | Click-through via `ignoresMouseEvents=true` |
| Always on top | `window.level = .floating` | Stays above iTerm2 |
| GPU rendering | Metal/Core Animation or SDL2+OpenGL | True pixel particles, thousands of them |
| Terminal tracking | AppleScript / Accessibility API to get iTerm2 window frame | Or: user manually positions, or detects via screen coords |
| Neovim RPC | Unix socket or TCP, msgpack-rpc | Send cursor position, combo events |
| iTerm2 passthrough | `set -g allow-passthrough on` in tmux | Needed if using iTerm2 image protocol approach |

**Additional discovery — iTerm2 Inline Image Protocol (OSC 1337)**:
- iTerm2 can render inline images via `ESC]1337;File=inline=1:BASE64_DATA BEL`
- Works through tmux with `allow-passthrough on`
- Could render pre-computed particle frame images directly in terminal (no external window needed!)
- Worth testing as a sub-experiment in PoC C

---

## PoC: Pure Lua (`poc-pure-lua/`)

### What to Build

A minimal but complete Neovim plugin that demonstrates ALL core power-mode features using only Neovim's Lua API. Built in a single pass — all features implemented together.

### Features to Implement

#### Particle System with Floating Windows
- Spawn 3-8 Unicode character particles at cursor position on each keystroke
- Physics: random velocity, gravity pulling down, drag slowing, lifetime decay
- Render each particle as a 1×1 floating window with `winblend` fading as it ages
- Pool ~50 floating windows to avoid create/destroy overhead
- Character sets: `{"✦", "✧", "⬥", "•", "·", "★", "⚡"}`
- Cyberpunk colors: neon cyan, hot pink, electric purple, neon green

#### Combo Counter with Shake & Exclamations
- Large floating window (20×6) at top-right
- Display: `COMBO` title, giant number, streak timeout bar (`████░░░░`), max streak
- **Shake the combo window** on each keystroke via `nvim_win_set_config` row/col jitter
- Shake intensity scales with combo level (±1 at low, ±4 at high)
- Exclamation phrases on milestones: `"UNSTOPPABLE!"`, `"GODLIKE!"`, `"RAMPAGE!"`
- Level system: thresholds at 10/25/50/100 change colors and particle intensity
- Bump animation: briefly modify counter text rendering on increment
- Timeout bar drains over 3 seconds, combo resets when empty

#### Cursor Glow
- 3×3 floating window behind cursor with bright background + high `blend`
- Color cycles with combo level (cyan → pink → purple → green cycle)

#### Highlight System
- `PowerModeParticle1` through `PowerModeParticle8` with cyberpunk neon palette
- `PowerModeCombo0` through `PowerModeCombo4` for combo level colors
- `PowerModeGlow` with animated blend value

### File Structure

```
poc-pure-lua/
├── plugin/
│   └── power-mode.lua          # Entry point: autocmds, commands (:PowerModeToggle)
└── lua/
    └── power-mode/
        ├── init.lua             # setup(), enable/disable, config
        ├── engine.lua           # Animation loop (vim.loop timer, frame management)
        ├── particles.lua        # Particle system (spawn, physics, lifecycle)
        ├── renderer.lua         # Floating window pool & rendering
        ├── combo.lua            # Combo counter, levels, shake, exclamations
        ├── glow.lua             # Cursor glow effect
        ├── highlights.lua       # Dynamic highlight group management
        └── utils.lua            # Math: random, clamp, lerp, easing
```

### Key Experiments to Run
- **Floating window throughput**: How many 1×1 floating windows can we create/update per frame before lag?
- **winblend fade quality**: Does blend 0→100 look smooth or steppy?
- **Combo window shake feel**: Is `nvim_win_set_config` jitter fast enough to feel responsive?
- **Particle density sweet spot**: What's the max particle count before performance degrades?
- **tmux compatibility**: Do floating windows render correctly inside tmux?

---

## PoC: Low-Level Overlay (`poc-low-level-overlay/`)

### What to Build

An external process that creates a transparent, click-through window on top of iTerm2, receives events from Neovim over RPC, and renders real pixel-based particle effects. Also includes an iTerm2 image protocol experiment. **All approaches built at once** so they can be tested side by side.

### Features to Implement

#### Python Overlay with Transparent Window + Particles
- Python + `pyobjc` (native Cocoa bindings) to create transparent `NSWindow` overlay on macOS
  - `backgroundColor = NSColor.clearColor()`, `isOpaque = False`
  - `ignoresMouseEvents = True` for click-through
  - `level = NSFloatingWindowLevel` to stay above iTerm2
- Connect to Neovim via `pynvim` RPC (Unix socket)
- Subscribe to custom events for cursor position and keystrokes
- Render particle effects using Core Graphics / Quartz 2D (via pyobjc)
  - Particle system with physics (velocity, gravity, drag, lifetime)
  - Neon cyberpunk colors with alpha fade
  - ~60fps animation loop via `NSTimer` or `CADisplayLink`
- Track iTerm2 window position via `osascript` (AppleScript): get window bounds, map Neovim cursor position to screen pixels
- **Combo counter** rendered as large text overlay with shake (jitter the text position)
- **Glow effect** rendered as a radial gradient behind cursor position

#### Swift Overlay with Native Performance
- Minimal Swift app built via `swiftc` (no Xcode project needed)
- Same `NSWindow` transparent/click-through/floating setup
- `NSView` subclass with `draw()` rendering particles via Core Graphics
- OR: `CAEmitterLayer` for GPU-accelerated particle emission (built into macOS!)
  - `CAEmitterCell` configured for particle color, velocity, lifetime, spin
  - This is the easiest path to beautiful particles on macOS
- Reads Neovim events from stdin (JSON lines) — launched as a child process
- Full combo counter + glow + particles in native performance

#### iTerm2 Inline Image Protocol Experiment
- Generate small particle frame images (e.g., 100×50 PNG with transparent background) using Python (Pillow)
- Emit them from Neovim Lua via iTerm2's OSC 1337 protocol:
  ```lua
  local img_data = base64_encode(png_frame)
  vim.api.nvim_chan_send(2, "\x1b]1337;File=inline=1;width=10;height=5:" .. img_data .. "\a")
  ```
- Test: Does it work inside tmux? (requires `set -g allow-passthrough on`)
- Test: Can we position the image at cursor location via Neovim cursor control?
- Test: Can we update fast enough for animation (~10fps)?
- Includes: frame generator script + Neovim Lua test script

#### Neovim-Side Event Bridge (shared by all overlay approaches)
- Small Lua module that:
  - Starts the overlay process via `vim.fn.jobstart()` as a child
  - Sends cursor position + keystroke events over stdin as JSON lines
  - Protocol: `{"event":"keystroke","row":10,"col":25,"combo":15,"level":2}`
  - Also exposes `:OverlayStart` and `:OverlayStop` commands

### File Structure

```
poc-low-level-overlay/
├── python-overlay/
│   ├── main.py                  # pyobjc transparent window + particle rendering
│   ├── particles.py             # Particle physics system
│   ├── nvim_bridge.py           # Neovim RPC connection via pynvim
│   ├── window_tracker.py        # Track iTerm2 window position via AppleScript
│   └── requirements.txt         # pynvim, pyobjc-framework-Cocoa, Pillow
├── swift-overlay/
│   ├── main.swift               # App entry point
│   ├── OverlayWindow.swift      # Transparent NSWindow setup
│   ├── ParticleView.swift       # Core Graphics / CAEmitterLayer particles
│   ├── JsonReader.swift         # Read JSON lines from stdin
│   └── build.sh                 # swiftc compile command
├── iterm2-image-experiment/
│   ├── generate_frames.py       # Generate particle frame PNGs with Pillow
│   ├── test_protocol.lua        # Neovim Lua script to test OSC 1337 emission
│   ├── test_animation.lua       # Neovim Lua script to test rapid frame updates
│   └── README.md                # Results and findings
└── nvim-plugin/
    ├── plugin/
    │   └── power-overlay.lua    # Entry point: :OverlayStart, :OverlayStop
    └── lua/
        └── power-overlay/
            └── init.lua         # Event bridge: jobstart, JSON line protocol
```

### Key Experiments to Run
- **Overlay latency**: How fast can overlay update after Neovim keystroke event?
- **Window tracking accuracy**: Can we reliably match overlay position to iTerm2 + tmux pane?
- **Particle rendering FPS**: How many particles at what frame rate (Python vs Swift)?
- **CAEmitterLayer**: Does macOS's built-in particle system give us "free" beautiful particles?
- **iTerm2 image protocol**: Can it animate? Positioning accuracy? tmux passthrough latency?
- **Click-through reliability**: Does `ignoresMouseEvents` work perfectly on macOS?

---

## MANUAL_TESTING.md

A `MANUAL_TESTING.md` file will be created at the repo root with:

### For poc-pure-lua/
1. How to add the plugin to Neovim's runtimepath (`:set rtp+=...` or symlink)
2. How to load and enable: `:PowerModeToggle`
3. What to look for: type in insert mode and observe particles, combo counter, glow
4. Performance tests: rapid typing, holding keys, testing in splits/tabs
5. tmux test: confirm floating windows render correctly inside tmux

### For poc-low-level-overlay/
1. Python overlay: `pip install` dependencies, start Neovim with `--listen /tmp/nvim.sock`, run `python main.py`
2. Swift overlay: `./build.sh` to compile, run the binary, start Neovim with bridge plugin
3. iTerm2 image experiment: load Lua test scripts in Neovim, enable tmux passthrough
4. What to look for: transparent window appearing, particles following cursor, combo overlay
5. Troubleshooting: tmux passthrough config, iTerm2 version requirements

---

## Implementation Todos

### PoC Pure Lua
1. **poc-lua-full** — Build the complete poc-pure-lua/ plugin in one pass: plugin scaffold + animation engine + particle system with floating window pool + combo counter with shake & exclamations + cursor glow + dynamic highlights + keystroke wiring. All features implemented together.

### PoC Low-Level Overlay
2. **poc-overlay-python** — Build Python overlay: transparent pyobjc NSWindow on macOS, pynvim RPC, particle physics with Core Graphics rendering, combo counter text overlay with shake, glow gradient, iTerm2 window tracking via AppleScript
3. **poc-overlay-swift** — Build Swift overlay: NSWindow transparent/click-through + CAEmitterLayer particles + Core Graphics combo/glow + JSON stdin reader. Compile with swiftc.
4. **poc-overlay-iterm2** — Build iTerm2 image protocol experiment: Python frame generator (Pillow) + Neovim Lua test scripts for OSC 1337 emission + animation speed test + tmux passthrough test
5. **poc-overlay-bridge** — Build Neovim-side Lua event bridge: jobstart overlay process, JSON line protocol for cursor/keystroke/combo events, :OverlayStart/:OverlayStop commands

### Documentation & Findings
6. **manual-testing-doc** — Create MANUAL_TESTING.md at repo root with exact setup + test instructions for both PoCs (runtimepath, pip install, build.sh, tmux config, what to look for)
7. **poc-findings** — Document results: what worked, what didn't, performance numbers, screenshots, recommendation for full build approach

## Dependencies
- `poc-overlay-bridge` runs in parallel with `poc-overlay-python` and `poc-overlay-swift` (bridge is needed by both but simple enough to build alongside)
- `poc-overlay-iterm2` is fully independent (can run in parallel with everything)
- `manual-testing-doc` depends on `poc-lua-full`, `poc-overlay-python`, `poc-overlay-swift`, `poc-overlay-iterm2`
- `poc-findings` depends on `manual-testing-doc` (after manual testing is done)

