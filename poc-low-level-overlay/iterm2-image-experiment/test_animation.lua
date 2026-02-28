-- Rapid animation test for iTerm2 inline images
-- Tests: How fast can we swap images? What's the visual quality?

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

-- Pre-load all frames into memory as base64
local function preload_frames()
  local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
  local frames = {}
  for i = 0, 19 do
    local path = string.format("%sframes/frame_%03d.png", script_dir, i)
    local f = io.open(path, "rb")
    if f then
      frames[i] = base64_encode(f:read("*all"))
      f:close()
    end
  end
  return frames
end

local frames = preload_frames()
local in_tmux = os.getenv("TMUX") ~= nil

local function emit_frame(b64, width, height)
  local seq
  if in_tmux then
    seq = string.format(
      "\x1bPtmux;\x1b\x1b]1337;File=inline=1;width=%s;height=%s:%s\a\x1b\\",
      width or "15", height or "4", b64
    )
  else
    seq = string.format(
      "\x1b]1337;File=inline=1;width=%s;height=%s:%s\a",
      width or "15", height or "4", b64
    )
  end
  io.write(seq)
  io.flush()
end

-- Test at different frame rates
local function test_fps(fps, label)
  print(string.format("\n--- Testing at %dfps (%s) ---", fps, label))
  local interval = math.floor(1000 / fps)
  local timer = vim.loop.new_timer()
  local idx = 0
  local start_time = vim.loop.now()
  
  timer:start(0, interval, function()
    vim.schedule(function()
      if frames[idx] then
        emit_frame(frames[idx])
      end
      idx = idx + 1
      if idx >= 20 then
        timer:stop()
        timer:close()
        local elapsed = vim.loop.now() - start_time
        print(string.format("  Completed: 20 frames in %dms (effective %.1ffps)", elapsed, 20000/elapsed))
      end
    end)
  end)
end

print("Pre-loaded " .. #frames + 1 .. " frames")
print("Starting frame rate tests...")

test_fps(5, "slow")
vim.defer_fn(function() test_fps(10, "medium") end, 5000)
vim.defer_fn(function() test_fps(20, "fast") end, 10000)
vim.defer_fn(function() test_fps(30, "very fast") end, 15000)
vim.defer_fn(function()
  print("\n=== ALL TESTS COMPLETE ===")
  print("Check visual output above for smoothness and artifacts")
end, 20000)
