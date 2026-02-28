local utils = require("power-mode.utils")
local M = {}

local mode = "none"  -- "none", "combo", "scroll", "applescript"
local shake_timer = nil

function M.set_mode(new_mode)
  mode = new_mode
  vim.notify("⚡ Shake mode: " .. mode, vim.log.levels.INFO)
end

function M.get_mode()
  return mode
end

function M.trigger(level)
  if mode == "none" then
    return
  elseif mode == "combo" then
    -- combo.lua already handles its own shake, nothing extra needed
    return
  elseif mode == "scroll" then
    M._scroll_shake(level)
  elseif mode == "applescript" then
    M._applescript_shake(level)
  end
end

-- Mode 2: Scroll shake — briefly shift viewport topline then restore
function M._scroll_shake(level)
  local magnitude = math.min(1 + level, 3)
  local current_top = vim.fn.line("w0")
  local dir = math.random() > 0.5
  local new_top = dir and (current_top + magnitude) or (current_top - magnitude)
  new_top = math.max(1, new_top)

  pcall(vim.fn.winrestview, { topline = new_top })

  -- Restore after short delay
  if shake_timer then
    pcall(function() shake_timer:stop() shake_timer:close() end)
  end
  shake_timer = vim.loop.new_timer()
  shake_timer:start(50, 0, vim.schedule_wrap(function()
    pcall(vim.fn.winrestview, { topline = current_top })
    if shake_timer then
      pcall(function() shake_timer:stop() shake_timer:close() end)
      shake_timer = nil
    end
  end))
end

-- Mode 3: AppleScript shake — jitter the iTerm2 window position (macOS only)
function M._applescript_shake(level)
  local magnitude = math.min(2 + level * 2, 10)
  local dx = utils.random_int(-magnitude, magnitude)
  local dy = utils.random_int(-magnitude, magnitude)

  -- Shift window, then restore
  vim.fn.jobstart({
    "osascript", "-e",
    string.format([[
tell application "iTerm2"
  set w to front window
  set b to bounds of w
  set x1 to (item 1 of b) + %d
  set y1 to (item 2 of b) + %d
  set x2 to (item 3 of b) + %d
  set y2 to (item 4 of b) + %d
  set bounds of w to {x1, y1, x2, y2}
  delay 0.05
  set bounds of w to b
end tell
]], dx, dy, dx, dy)
  }, { detach = true })
end

function M.cleanup()
  if shake_timer then
    pcall(function() shake_timer:stop() shake_timer:close() end)
    shake_timer = nil
  end
end

return M
