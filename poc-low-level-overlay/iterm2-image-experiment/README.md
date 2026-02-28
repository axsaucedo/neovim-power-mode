# iTerm2 Inline Image Protocol Experiment

## Goal
Test whether we can render pixel-based particle animations directly inside the terminal
using iTerm2's OSC 1337 inline image protocol — no external overlay window needed.

## Prerequisites
- macOS with iTerm2
- Python 3 with Pillow: `pip3 install Pillow`
- Neovim
- If using tmux: `set -g allow-passthrough on` in `~/.tmux.conf`

## Steps

### 1. Generate particle frames
```bash
cd poc-low-level-overlay/iterm2-image-experiment/
python3 generate_frames.py
```
This creates 20 PNG frames in `frames/` and base64 versions in `frames_b64/`.

### 2. Test single image display
Open Neovim in iTerm2 and run:
```vim
:luafile path/to/test_protocol.lua
```

### 3. Test animation speed
```vim
:luafile path/to/test_animation.lua
```

## What to observe
- Do images display inline in the terminal?
- Is transparency preserved (can you see text behind)?
- How fast can frames update? (5fps? 10fps? 30fps?)
- Does it work inside tmux with passthrough enabled?
- Is there visual flicker or artifacts?
- Can we position images at specific cursor locations?

## Results
(Fill in after testing)

### Image Display: 
### Transparency: 
### Max Smooth FPS: 
### tmux Passthrough: 
### Positioning: 
### Overall Verdict: 
