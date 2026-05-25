--- Screen shake for neovim-power-mode
--- 3 modes: none, scroll (viewport jitter), applescript (iTerm2 window jitter)
local config = require("power-mode.config")
local utils = require("power-mode.utils")

local M = {}

-- F6: single module-scope uv_timer reused across every scroll-shake
-- event. Previously we allocated a new uv handle per shake event and
-- closed it from the restore callback — at interval=1 under heavy
-- typing that's 60+ open/close pairs per second of uv handle churn.
-- Now we keep one handle for the lifetime of the plugin; `cleanup()`
-- closes it when power-mode is disabled. We also coalesce overlapping
-- shakes: while a restore is already pending, drop the new shake
-- (prevents the visible "wobble" that compounding shakes produce and
-- removes start/stop churn under storm typing).
local shake_timer = nil
local shake_restore_topline = nil  -- topline to restore to (set on shake start)
local shake_pending = false        -- true while a restore is armed
local keystroke_count = 0

function M.trigger(level)
  local cfg = config.get()
  local mode = cfg.shake.mode
  if mode == "none" then return end

  keystroke_count = keystroke_count + 1
  if keystroke_count % cfg.shake.interval ~= 0 then return end

  if mode == "scroll" then
    M._scroll_shake(level, cfg)
  elseif mode == "applescript" then
    M._applescript_shake(level, cfg)
  end
end

function M._scroll_shake(_level, cfg)
  -- Coalesce: while a previous shake's restore is still pending, drop
  -- this event rather than restart the timer (would extend the visible
  -- displacement window indefinitely under storm typing).
  if shake_pending then return end

  local magnitude = cfg.shake.magnitude or 1

  -- Only manipulate topline — never touch cursor position
  local current_topline = vim.fn.winsaveview().topline
  local total_lines = vim.fn.line("$")
  local win_height = vim.fn.winheight(0)

  -- Skip shake if the file is too short to scroll
  if total_lines <= win_height then return end

  -- Pick direction: shift topline up or down
  local dir = math.random() > 0.5 and magnitude or -magnitude
  local new_top = current_topline + dir
  if new_top < 1 then new_top = 1 end
  local max_top = total_lines - win_height + 1
  if new_top > max_top then new_top = max_top end

  -- Only shake if the shift actually moves the viewport
  if new_top == current_topline then return end

  -- Shift viewport only (no cursor manipulation)
  pcall(vim.fn.winrestview, { topline = new_top })

  -- Lazily allocate the shared timer on first use.
  if not shake_timer then
    shake_timer = vim.loop.new_timer()
  end

  shake_restore_topline = current_topline
  shake_pending = true
  shake_timer:start(cfg.shake.restore_delay, 0, vim.schedule_wrap(function()
    local restore_to = shake_restore_topline
    shake_pending = false
    shake_restore_topline = nil
    if restore_to then
      pcall(vim.fn.winrestview, { topline = restore_to })
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
  shake_pending = false
  shake_restore_topline = nil
  keystroke_count = 0
end

return M
