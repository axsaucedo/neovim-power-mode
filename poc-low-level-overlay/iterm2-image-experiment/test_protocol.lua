-- Test iTerm2 OSC 1337 inline image protocol from Neovim
-- Usage: Open this file in Neovim inside iTerm2 and run :luafile %
-- Make sure tmux has: set -g allow-passthrough on

-- Resolve script directory robustly (handles :luafile from same directory)
local _script_source = debug.getinfo(1, "S").source:sub(2)
local script_dir = _script_source:match("(.*/)")
if not script_dir then
  script_dir = vim.fn.fnamemodify(_script_source, ":p:h") .. "/"
end

local M = {}

-- Base64 encode helper
local function base64_encode(data)
  local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  return ((data:gsub('.', function(x)
    local r, b_val = '', x:byte()
    for i = 8, 1, -1 do
      r = r .. (b_val % 2 ^ i - b_val % 2 ^ (i - 1) > 0 and '1' or '0')
    end
    return r
  end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
    if #x < 6 then return '' end
    local c = 0
    for i = 1, 6 do
      c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0)
    end
    return b:sub(c + 1, c + 1)
  end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

-- Read a file as binary
local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*all")
  f:close()
  return data
end

-- Send an inline image via iTerm2 protocol
-- For tmux, we need to wrap in DCS passthrough
function M.display_image(path, opts)
  opts = opts or {}
  local width = opts.width or "auto"
  local height = opts.height or "auto"
  local preserve = opts.preserveAspectRatio and "1" or "0"
  
  local data = read_file(path)
  if not data then
    print("ERROR: Could not read file: " .. path)
    return false
  end
  
  local b64 = base64_encode(data)
  
  -- Check if inside tmux
  local in_tmux = os.getenv("TMUX") ~= nil
  
  local seq
  if in_tmux then
    -- Wrap in DCS passthrough for tmux
    seq = string.format(
      "\x1bPtmux;\x1b\x1b]1337;File=inline=1;width=%s;height=%s;preserveAspectRatio=%s:%s\a\x1b\\",
      width, height, preserve, b64
    )
  else
    seq = string.format(
      "\x1b]1337;File=inline=1;width=%s;height=%s;preserveAspectRatio=%s:%s\a",
      width, height, preserve, b64
    )
  end
  
  -- Write to terminal (channel 2 = stderr, which goes to terminal)
  io.write(seq)
  io.flush()
  
  return true
end

-- Test 1: Display a single frame
function M.test_single_frame()
  local frame_path = script_dir .. "frames/frame_000.png"
  
  print("Test 1: Single frame display")
  print("Attempting to display: " .. frame_path)
  
  if M.display_image(frame_path, { width = "15", height = "4" }) then
    print("SUCCESS: Image sent to terminal")
  else
    print("FAILED: Could not send image")
  end
end

-- Test 2: Animate frames rapidly
function M.test_animation()
  local frames_dir = script_dir .. "frames/"
  
  print("Test 2: Animation test (20 frames at ~10fps)")
  
  local timer = vim.loop.new_timer()
  local frame_idx = 0
  local max_frames = 20
  
  timer:start(0, 100, function()  -- 100ms = 10fps
    vim.schedule(function()
      local path = string.format("%sframe_%03d.png", frames_dir, frame_idx)
      -- Move cursor to a fixed position first
      vim.cmd("normal! 10G20|")
      M.display_image(path, { width = "15", height = "4" })
      
      frame_idx = frame_idx + 1
      if frame_idx >= max_frames then
        timer:stop()
        timer:close()
        print("\nAnimation complete!")
        print("RESULT: Check if frames displayed smoothly")
      end
    end)
  end)
end

-- Test 3: Display glow image
function M.test_glow()
  local glow_path = script_dir .. "frames/glow.png"
  
  print("Test 3: Glow image display")
  M.display_image(glow_path, { width = "5", height = "3" })
end

-- Run all tests
function M.run_all()
  print("=" .. string.rep("=", 50))
  print("iTerm2 Inline Image Protocol Test Suite")
  print("=" .. string.rep("=", 50))
  print("")
  print("Prerequisites:")
  print("  - Running in iTerm2")
  print("  - If in tmux: set -g allow-passthrough on")
  print("  - Generated frames: python3 generate_frames.py")
  print("")
  
  M.test_single_frame()
  print("")
  
  -- Wait a bit then test animation
  vim.defer_fn(function()
    M.test_animation()
  end, 2000)
  
  -- Test glow after animation
  vim.defer_fn(function()
    M.test_glow()
  end, 5000)
end

-- Auto-run when sourced
print("iTerm2 Image Protocol Experiment loaded.")
print("Run :lua require('test_protocol_module').run_all() or just :luafile %")
M.run_all()

return M
