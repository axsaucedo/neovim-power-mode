--- Screen shake for neovim-power-mode
--- 3 modes: none, scroll (viewport jitter), applescript (iTerm2 window jitter)
local config = require("power-mode.config")
local utils = require("power-mode.utils")

local M = {}

local shake_timer = nil
local keystroke_count = 0

function M.trigger(level)
  local cfg = config.get()
  if cfg.shake.mode == "none" then return end

  keystroke_count = keystroke_count + 1
  if keystroke_count % cfg.shake.interval ~= 0 then return end

  if cfg.shake.mode == "scroll" then
    M._scroll_shake(level, cfg)
  elseif cfg.shake.mode == "applescript" then
    M._applescript_shake(level, cfg)
  end
end

function M._scroll_shake(level, cfg)
  local magnitude = cfg.shake.magnitude or math.min(1 + level, 3)
  local current_top = vim.fn.line("w0")
  local dir = math.random() > 0.5
  local new_top = dir and (current_top + magnitude) or (current_top - magnitude)
  new_top = math.max(1, new_top)

  pcall(vim.fn.winrestview, { topline = new_top })

  if shake_timer then
    pcall(function() shake_timer:stop() shake_timer:close() end)
  end
  shake_timer = vim.loop.new_timer()
  shake_timer:start(cfg.shake.restore_delay, 0, vim.schedule_wrap(function()
    pcall(vim.fn.winrestview, { topline = current_top })
    if shake_timer then
      pcall(function() shake_timer:stop() shake_timer:close() end)
      shake_timer = nil
    end
  end))
end

function M._applescript_shake(level, cfg)
  local magnitude = cfg.shake.magnitude or math.min(2 + level * 2, 10)
  local dx = utils.random_int(-magnitude, magnitude)
  local dy = utils.random_int(-magnitude, magnitude)

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
  keystroke_count = 0
end

return M
