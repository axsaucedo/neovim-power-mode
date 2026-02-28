# PoC Learnings — Neovim Power Mode Plugin

## Project Goal

Replicate VS Code's "Power Mode" in Neovim: animated particle explosions, combo counter with shake, cyberpunk neon glow effects — all triggered on every keystroke. This is pushing terminal UI far beyond its normal capabilities.

## Reference Implementations Studied

- **activate-power-mode (Atom)** — `JoelBesada/activate-power-mode`: HTML canvas overlay with `requestAnimationFrame` at 60fps. 60px combo counter with CSS bump animation, level system with hue rotation, exclamation phrases, streak timeout bar. Screen shake via CSS `will-change: transform`. Modular architecture: `power-canvas`, `combo-mode`, `screen-shake`, `play-audio`.
- **VS Code Power Mode**: Same concepts via `TextEditorDecorations` API — particles, shake, combo, custom GIFs.
- **Existing Neovim plugins**: `power-mode.nvim`, `cellular-automaton.nvim`, `drop.nvim` — none achieved true Power Mode fidelity; limited to simple text-cell effects.

---

## Approaches Tested

### 1. Pure Lua Neovim Plugin (`poc-pure-lua/`)

**Technique**: Floating windows (`nvim_open_win`) as 1×1 character-sized particles, pre-allocated window pool, `vim.loop.new_timer()` for animation.

**Status**: Working — viable path for terminal-native approach.

#### What Works

- **Combo counter**: Floating window at top-right with streak bar (`████░░░░`), combo level colors (green → cyan → pink → purple → red), shake via `nvim_win_set_config` jitter, exclamation phrases ("UNSTOPPABLE!", "GODLIKE!") at milestones. Works well and feels good.
- **Particle modes**: Four modes implemented — shockwave (expanding rings), fountain (upward spray), disintegrate (buffer text shatters), explosion (radial upward burst). Selectable via `:PowerModeStyle`.
- **Floating window pool**: Pre-allocating 60 windows avoids create/destroy overhead. Moving unused windows to `row=-10, col=-10` hides them without closing.
- **Keystroke detection**: `InsertCharPre` autocmd → `vim.schedule()` works reliably.

#### What Doesn't Work / Lessons Learned

- **Cursor position calculation is tricky**: `nvim_win_get_position()` + `nvim_win_get_cursor()` does NOT account for number column, sign column, or fold column widths. Particles spawned far left of the actual cursor. **Fix**: Use `vim.fn.screenpos(win_getid(), row, col)` which returns exact screen coordinates including all gutter elements.
- **Custom themes/glow looks terrible**: Attempted multi-layer glow (floating windows with bright backgrounds + high blend). Just looks like ugly colored blocks — no blur, no gradient, no subtlety. Neovim's `winblend` is not the same as true alpha compositing. **Conclusion**: Don't try to fake glow with floating windows. Drop glow entirely in the Lua approach.
- **~25fps ceiling**: `vim.loop.new_timer()` at 40ms interval is the practical max. All UI updates must go through `vim.schedule()` since the timer fires from libuv, not the main thread. Good enough for particles, not for smooth 60fps animation.
- **Particle quality is inherently limited**: Text-cell resolution (each particle is 1 character) means you can't do smooth gradients, varying sizes, blur, or trails. Unicode characters (✦⚡★◆●) help but will always look like text, not graphics.
- **Colors require `termguicolors`**: Without `set termguicolors`, the neon hex colors (#00FFFF, #FF1493, etc.) fall back to 256-color approximation and look wrong. This is a hard requirement.
- **Background color on highlights helps**: Setting `bg` to a dark tinted version of the `fg` color (e.g., `fg=#00FFFF, bg=#002233`) makes particles pop against any colorscheme. `bg=NONE` caused particles to be invisible on some backgrounds.

#### Key APIs

| API | Purpose | Notes |
|-----|---------|-------|
| `nvim_open_win()` | Particle windows | `relative="editor"`, `style="minimal"`, `focusable=false`, `zindex=50` |
| `winblend` | Particle fade | 0=opaque → 100=transparent over particle lifetime |
| `vim.fn.screenpos()` | Cursor position | Correct method — accounts for all gutter elements |
| `nvim_win_set_config()` | Position update + shake | Fast enough for 25fps |
| `nvim_set_hl()` | Dynamic colors | Can update highlight groups per-frame |
| `InsertCharPre` | Keystroke detection | Must use `vim.schedule()` inside callback |

---

### 2. Python Overlay (`poc-low-level-overlay/python-overlay/`) — ABANDONED

**Technique**: pyobjc to create transparent NSWindow overlay on macOS.

**Status**: Removed after 3 failed iterations.

#### Why It Failed

1. **pyobjc `super()` incompatibility**: `ObjCSuperWarning: Objective-C subclass uses super(), but super is not objc.super`. Python's `super()` doesn't work for Objective-C subclasses — must use `objc.super()`. Even after fixing, `AttributeError: 'super' object has no attribute 'initWithFrame_'` persisted.
2. **AppleScript parsing bug**: AppleScript's `&` operator does list concatenation, not string concatenation. `(item 1 of b) & "," & (item 2 of b)` produces `0, ,, 35, ,, 1352, ,, 878` instead of `0,35,1352,878`. Fix: `(item 1 of b as text) & "," & ...`. This was discovered here and applied to Swift/Rust.
3. **Overlay just doesn't render**: Even after fixing both bugs above, piping JSON events to stdin produced no visible particles. The window was created but nothing was drawn on screen.
4. **pyobjc is fragile**: The bridge between Python and Objective-C runtime is brittle, poorly documented, and version-sensitive. Not worth the debugging effort for a PoC.

**Lesson**: Don't use pyobjc for real-time graphics. Use Swift or Rust with native Cocoa bindings.

---

### 3. Swift Overlay (`poc-low-level-overlay/swift-overlay/`)

**Technique**: Native macOS app via `swiftc` (no Xcode). NSWindow transparent overlay, CAEmitterLayer for GPU-accelerated particles, Core Graphics fallback.

**Status**: Working — good performance, decent visuals, small binary (~215KB).

#### What Works

- **Transparent click-through window**: `NSWindow` with `backgroundColor=.clear`, `isOpaque=false`, `ignoresMouseEvents=true`, `level=.floating` works perfectly on macOS.
- **CAEmitterLayer (GPU particles)**: macOS's built-in particle system. Zero-effort GPU acceleration, configurable via `CAEmitterCell` properties (birthRate, velocity, scale, lifetime, alphaSpeed). Emitter position can be moved to cursor location.
- **Core Graphics fallback**: Manual particle rendering with trails (3 trailing circles along negative velocity), bright cores, colored bodies. More control than CAEmitterLayer but CPU-bound.
- **Build with swiftc**: `swiftc -framework Cocoa -framework QuartzCore *.swift` — no Xcode project needed. Fast compile, small binary.

#### What Doesn't Work / Lessons Learned

- **AppleScript blocks the main thread**: Initial implementation used `Process().waitUntilExit()` on the main thread to query iTerm2 window bounds. This blocked the 60fps run loop for ~200ms each call (even with 2s cache interval). **Fix**: Move AppleScript to `DispatchQueue.global(qos: .utility).async` with NSLock-protected cached bounds.
- **CAEmitterLayer scale is unintuitive**: `cell.scale = 0.05` makes particles nearly invisible even with a 12×12 base image. Usable range is 0.15-0.3 with a 24×24 base image. `scaleRange` adds randomness. The interaction between image size and scale factor is not obvious.
- **Glow via Core Graphics gradients looks bad**: `CGGradient` radial gradient drawn behind particles looked like a blurry colored blob, not a subtle glow. The issue is that the overlay window has no backdrop blur — it's just painting onto a transparent surface, so gradients look flat and unnatural. **Conclusion**: Don't do glow in the overlay. Focus on particles only.
- **Cursor tracking has a delta**: AppleScript returns iTerm2 window bounds, but mapping terminal row/col to screen pixels requires knowing cell dimensions (`cell_w=8, cell_h=16`), tab bar offset (`y_offset=70`), and padding (`x_offset=4`). These are hardcoded approximations — they break with different font sizes, tab bar configs, or split panes. A better approach would be to query iTerm2's actual cell dimensions.

---

### 4. Rust Overlay (`poc-low-level-overlay/rust-overlay/`) — BEST APPROACH

**Technique**: Native macOS app using `cocoa`, `core-graphics`, `objc` crates. Custom NSView subclass via `ClassDecl`. JSON stdin protocol.

**Status**: Working — best-performing overlay, cursor tracking works, now has trail/glow/core rendering.

#### What Works

- **Performance is excellent**: Compiled Rust binary with `--release` + LTO. 60fps via `CFRunLoopTimer`. Handles 500 particles without lag.
- **Custom NSView via ClassDecl**: Register a custom Objective-C class from Rust, override `drawRect:` and `isOpaque`. Works with `objc` crate's runtime API. This is the key technique for drawing custom content.
- **4-layer particle rendering**: Each particle draws (1) outer glow (3x radius, 20% alpha), (2) comet trail (3 trailing circles), (3) main body, (4) white-hot core. Looks significantly better than single-circle "confetti".
- **Async AppleScript**: Bounds fetching runs on a separate thread with a `bounds_fetching` guard to prevent concurrent fetches. Non-blocking cursor tracking.
- **60% upward bias**: Particles are 60% likely to have an upward angle (45°–135°), 40% random. Creates a natural "explosion upward" look.
- **Small binary**: ~535KB release build (with `strip=true` and `lto=true` can be under 1MB).

#### What Doesn't Work / Lessons Learned

- **Binary size without strip is huge**: Without `strip = true` in `[profile.release]`, the Rust binary includes debug symbols and balloons to ~66MB. With `strip = true` + `codegen-units = 1` + `lto = true`, it drops to ~535KB-1MB. Always add `strip = true` for release builds.
- **`cocoa` crate is low-level and unsafe**: Every Cocoa call requires `unsafe {}` blocks and raw `msg_send!` macros. No type safety for Objective-C selectors. Easy to crash with wrong message signatures. But it works and produces tiny binaries.
- **Global mutable state for C callbacks**: `CFRunLoopTimer` and `drawRect:` callbacks need access to shared state. Solved with `static mut GLOBAL_STATE: *const Mutex<AppState>` — ugly but functional. The `Arc<Mutex<>>` pattern works across the stdin reader thread and main thread.
- **Same AppleScript `as text` bug**: The AppleScript `&` operator concatenation bug affected all overlays. Rust implementation had the fix from the start since it was built after discovering the bug in Python/Swift.
- **Core Graphics has no blur/shadow**: CG can draw filled ellipses but not blurred ones. The "glow" layer is just a larger semi-transparent circle — not a true gaussian blur. For real glow, you'd need Metal shaders or `CIFilter`. But the 4-layer approach (outer glow + trail + body + core) is good enough.

#### Key Dependencies

```toml
cocoa = "0.26"          # NSWindow, NSView, NSApplication
core-graphics = "0.24"  # CGContext, CGRect, drawing
core-foundation = "0.10" # CFRunLoop, CFRunLoopTimer
objc = "0.2"            # Runtime: ClassDecl, msg_send!
serde = "1"             # JSON deserialization
serde_json = "1"        # JSON parsing
```

---

### 5. iTerm2 Image Protocol (`poc-low-level-overlay/iterm2-image-experiment/`) — ABANDONED

**Technique**: iTerm2's inline image protocol (OSC 1337) to render pre-computed particle frame PNGs directly in the terminal.

**Status**: Removed after 3 failed iterations.

#### Why It Failed

1. **Module loading in Neovim is unreliable**: `luafile` discards the return value and doesn't set globals. Even after fixing with explicit `_G.TestIterm2Protocol = M`, subsequent `:lua TestIterm2Protocol.test_single_image()` calls failed with `attempt to index global 'TestIterm2Protocol' (a nil value)`.
2. **`script_dir` resolution fails**: `debug.getinfo(1, "S").source` returns different paths depending on how the script is loaded (`:luafile` vs `require()` vs inline `:lua`). Falls back to `nil` causing concatenation errors.
3. **Never validated end-to-end**: The protocol itself (OSC 1337 escape sequence) was never successfully tested because the Lua loading issues prevented reaching the actual image display code.
4. **Fundamental limitations**: Even if it worked, inline images in terminals are positioned at the cursor and scroll with content. You can't freely position them as an overlay. Animation would require rapidly re-emitting escape sequences, which would likely flicker and interfere with the terminal buffer.

**Lesson**: iTerm2 image protocol is designed for static inline images (plots, previews), not real-time animation overlays. The overlay window approach (Swift/Rust) is fundamentally better.

---

## Cross-Cutting Learnings

### AppleScript Is Dangerous

The AppleScript `&` operator performs **list concatenation**, not string concatenation. This produced malformed output (`0, ,, 35, ,, 1352, ,, 878`) that silently broke parsing in all three overlay implementations. Always use `as text` coercion: `(item 1 of b as text) & "," & (item 2 of b as text)`.

AppleScript is also slow (~200ms per call) and must never be called on the main/UI thread. Always use background threads with cached results.

### Neovim's `rtp+=` Doesn't Work Reliably

The standard `set rtp+=path/to/plugin` approach failed for users. The reliable approach is:

```lua
-- In init.lua or via lua << EOF in .vimrc:
vim.opt.rtp:prepend(vim.fn.expand("~/path/to/plugin"))
```

### Terminal Glow Is (Basically) Impossible

Both the Lua approach (floating windows with `winblend`) and the overlay approach (Core Graphics radial gradients) produced ugly results when trying to create glow effects. The fundamental issue is:

- **Lua**: `winblend` is not true alpha compositing — it's a blend over the terminal background color, not the content underneath.
- **Overlay**: Without backdrop blur (which requires Metal/compositor access), semi-transparent colored circles look flat and cheap.

**Recommendation**: Don't attempt glow. Focus on particles (which can look great) and combo counter (which works well in both approaches).

### Cursor-to-Screen Mapping

| Approach | Method | Accuracy |
|----------|--------|----------|
| Pure Lua | `vim.fn.screenpos(win_getid(), row, col)` | Exact — accounts for number/sign/fold columns |
| Pure Lua (wrong) | `nvim_win_get_position() + nvim_win_get_cursor()` | Off by gutter width |
| Overlay (macOS) | AppleScript bounds + hardcoded cell dimensions | Approximate — breaks with font/config changes |

### Performance Comparison

| Approach | Max FPS | Max Particles | Binary Size | Startup |
|----------|---------|---------------|-------------|---------|
| Pure Lua | ~25fps | ~60 (pool limit) | 0 (Lua) | Instant |
| Python (pyobjc) | N/A | N/A | N/A | Failed |
| Swift | 60fps | 300+ | ~215KB | <100ms |
| Rust | 60fps | 500+ | ~535KB | <100ms |
| iTerm2 protocol | N/A | N/A | N/A | Failed |

---

## Architecture Decisions Made

1. **Shake = combo window shake, NOT viewport**: Shaking the editor viewport would be disorienting and potentially break cursor position. Shaking only the combo counter floating window is safe and effective.
2. **macOS-only for overlay**: The NSWindow overlay approach is inherently macOS-specific. The Lua approach is cross-platform.
3. **JSON stdin protocol**: Overlays receive events as JSON lines on stdin (e.g., `{"event":"keystroke","row":10,"col":25,"combo":5,"level":1}`). Simpler and more debuggable than msgpack-rpc.
4. **Neovim bridge plugin**: A small Lua plugin (`power-overlay`) launches the overlay as a child process via `vim.fn.jobstart()` and sends events. This decouples the overlay implementation from Neovim.
5. **Pre-allocated window pool**: Creating/destroying floating windows on every particle is too slow. A pool of 60 pre-allocated 1×1 windows, moved on/offscreen as needed, is performant.

---

## Recommendations for Full Build

### Primary: Rust Overlay (macOS)
- Best visual quality (4-layer rendering, true pixel particles)
- Best performance (60fps, 500+ particles)
- Cursor tracking via AppleScript (async, cached)
- Needs: better cursor tracking (query iTerm2 cell dimensions instead of hardcoding 8×16), Metal shaders for true particle glow (optional), support for Alacritty/Kitty (not just iTerm2)

### Secondary: Pure Lua (Cross-Platform)
- Works everywhere Neovim runs
- Combo counter is already good
- Particles are decent with the explosion mode
- Hard ceiling on visual quality (text-cell resolution, ~25fps)
- Could be the "lite" mode that ships with the plugin, with the Rust overlay as the "premium" mode

### Dropped
- **Python overlay**: Too fragile (pyobjc), too slow, never worked
- **iTerm2 image protocol**: Wrong tool for the job (static images, not animation overlays)
- **Swift overlay**: Works but Rust matches it with more control and comparable binary size. No reason to maintain both. Keep Swift code as reference only.

---

## Environment Requirements

- **Neovim ≥ 0.9** (for `vim.fn.screenpos`, floating window features)
- **macOS** (for overlay — NSWindow, Core Graphics, AppleScript)
- **iTerm2** (for AppleScript window bounds tracking)
- **`set termguicolors`** (required for neon hex colors in Lua approach)
- **Rust toolchain** (for building overlay binary)
- **tmux**: `set -g allow-passthrough on` if using tmux (for overlay cursor tracking)
