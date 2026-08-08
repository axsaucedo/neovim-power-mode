--- Math and utility helpers for neovim-power-mode
local M = {}

math.randomseed(os.time())

function M.random(min, max)
  return min + math.random() * (max - min)
end

function M.random_int(min, max)
  return math.random(min, max)
end

function M.clamp(value, min, max)
  if value < min then return min end
  if value > max then return max end
  return value
end

function M.lerp(a, b, t)
  return a + (b - a) * t
end

function M.random_choice(list)
  return list[math.random(#list)]
end

--- F9: run `fn` with autocmds and redraws suppressed, always restoring the
--- previous option values even if `fn` raises. Destroying the plugin's
--- floating UI otherwise fires a WinClosed/BufDelete cascade into every
--- subscribed third-party plugin and forces a redraw per window; leaving
--- eventignore="all" behind on an error would silently break the editor.
--- @param context string label used in the warning if `fn` fails
--- @param fn function
--- @return boolean ok
function M.with_ui_suppressed(context, fn)
  local eventignore = vim.o.eventignore
  local lazyredraw = vim.o.lazyredraw
  vim.o.eventignore = "all"
  vim.o.lazyredraw = true

  local ok, err = pcall(fn)

  vim.o.eventignore = eventignore
  vim.o.lazyredraw = lazyredraw
  if not ok then
    vim.notify("[power-mode] " .. context .. " failed: " .. tostring(err), vim.log.levels.WARN)
  end
  return ok
end

function M.get_editor_dimensions()
  return {
    width = vim.o.columns,
    height = vim.o.lines,
  }
end

return M
