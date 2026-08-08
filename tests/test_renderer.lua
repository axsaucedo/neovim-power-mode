-- Tests for renderer teardown and disable cleanup
local pass, fail = 0, 0

local function assert_eq(actual, expected, name)
  if actual == expected then
    print("  PASS: " .. name)
    pass = pass + 1
  else
    print("  FAIL: " .. name .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
    fail = fail + 1
  end
end

local power_mode = require("power-mode")
local combo = require("power-mode.combo")
local fire_wall = require("power-mode.fire_wall")
local renderer = require("power-mode.renderer")
local shake = require("power-mode.shake")

power_mode.disable()

local function resources_restored(windows, buffers)
  return #vim.api.nvim_list_wins() == windows
    and #vim.api.nvim_list_bufs() == buffers
end

local function config_coord(value)
  if type(value) == "number" then return value end
  if type(value) ~= "table" then return nil end
  -- Neovim 0.9 represents API floats as {[false] = value, [true] = exponent}.
  if type(value[false]) == "number" then return value[false] end
  if type(value[1]) == "number" then return value[1] end
  return nil
end

-- Test 1: disable removes every plugin-created window and buffer.
local windows_before = #vim.api.nvim_list_wins()
local buffers_before = #vim.api.nvim_list_bufs()

power_mode.setup({
  auto_enable = false,
  particles = { pool_size = 10, avoid_cursor = false },
  combo = { enabled = true },
  fire_wall = { enabled = true },
})
power_mode.enable()

local pool_windows = {}
for _, win in ipairs(vim.api.nvim_list_wins()) do
  if win ~= vim.api.nvim_get_current_win() then
    local cfg = vim.api.nvim_win_get_config(win)
    if config_coord(cfg.row) == -10 and config_coord(cfg.col) == -10 then
      pool_windows[#pool_windows + 1] = win
    end
  end
end

renderer.render({ {
  x = 20,
  y = 20,
  char = "*",
  lifetime = 100,
  max_lifetime = 200,
  color_idx = 1,
} })

local visible_particle_windows = {}
for _, win in ipairs(pool_windows) do
  local cfg = vim.api.nvim_win_get_config(win)
  if config_coord(cfg.row) == 20 and config_coord(cfg.col) == 20 then
    visible_particle_windows[#visible_particle_windows + 1] = win
  end
end
assert_eq(#visible_particle_windows, 1, "captures the visible particle window")

combo.increment()
fire_wall.spawn(2, 25)
fire_wall.update(0)
local original_eventignore = vim.o.eventignore
local original_lazyredraw = vim.o.lazyredraw
vim.o.eventignore = "CursorHold"
vim.o.lazyredraw = false
power_mode.disable()

local all_particle_windows_parked = true
for _, win in ipairs(visible_particle_windows) do
  if vim.api.nvim_win_is_valid(win) then
    local cfg = vim.api.nvim_win_get_config(win)
    local row = config_coord(cfg.row)
    local col = config_coord(cfg.col)
    if row ~= -10 and not (row == nil and col == -10) then
      all_particle_windows_parked = false
    end
  end
end
assert_eq(all_particle_windows_parked, true, "disable parks visible particle windows")
assert_eq(vim.o.eventignore, "CursorHold", "disable restores eventignore")
assert_eq(vim.o.lazyredraw, false, "disable restores lazyredraw")
vim.wait(1000, function()
  return resources_restored(windows_before, buffers_before)
end)
assert_eq(#vim.api.nvim_list_wins(), windows_before, "disable restores window count")
assert_eq(#vim.api.nvim_list_bufs(), buffers_before, "disable restores buffer count")
assert_eq(vim.o.eventignore, "CursorHold", "deferred cleanup restores eventignore")
assert_eq(vim.o.lazyredraw, false, "deferred cleanup restores lazyredraw")
vim.o.eventignore = original_eventignore
vim.o.lazyredraw = original_lazyredraw

-- Test 2: deferred cleanup cannot destroy a fresh pool after rapid re-enable.
power_mode.enable()
power_mode.disable()
power_mode.enable()
vim.wait(100, function() return false end)
assert_eq(#vim.api.nvim_list_wins(), windows_before + 10, "rapid re-enable keeps fresh pool windows")
assert_eq(#vim.api.nvim_list_bufs(), buffers_before + 10, "rapid re-enable keeps fresh pool buffers")

power_mode.disable()
vim.wait(1000, function()
  return resources_restored(windows_before, buffers_before)
end)
assert_eq(#vim.api.nvim_list_wins(), windows_before, "final disable restores window count")
assert_eq(#vim.api.nvim_list_bufs(), buffers_before, "final disable restores buffer count")

-- Test 3: disable restores UI options and warns if guarded teardown fails.
power_mode.enable()
original_eventignore = vim.o.eventignore
original_lazyredraw = vim.o.lazyredraw
vim.o.eventignore = "CursorHold"
vim.o.lazyredraw = false
local original_shake_cleanup = shake.cleanup
local original_notify = vim.notify
local disable_warning = nil
shake.cleanup = function() error("forced disable cleanup failure") end
vim.notify = function(message, level)
  if level == vim.log.levels.WARN then disable_warning = message end
end

power_mode.disable()

shake.cleanup = original_shake_cleanup
vim.notify = original_notify
assert_eq(vim.o.eventignore, "CursorHold", "failed disable restores eventignore")
assert_eq(vim.o.lazyredraw, false, "failed disable restores lazyredraw")
assert_eq(disable_warning and disable_warning:match("^%[power%-mode%]") ~= nil, true,
  "failed disable emits prefixed warning")
vim.wait(1000, function()
  return resources_restored(windows_before, buffers_before)
end)
vim.o.eventignore = original_eventignore
vim.o.lazyredraw = original_lazyredraw

-- Test 4: renderer cleanup guard restores options and warns on failure.
original_eventignore = vim.o.eventignore
original_lazyredraw = vim.o.lazyredraw
vim.o.eventignore = "CursorHold"
vim.o.lazyredraw = false
local renderer_warning = nil
vim.notify = function(message, level)
  if level == vim.log.levels.WARN then renderer_warning = message end
end

local renderer_ok = renderer._with_ui_suppressed(function()
  error("forced renderer cleanup failure")
end)

vim.notify = original_notify
assert_eq(renderer_ok, false, "renderer guard reports failure")
assert_eq(vim.o.eventignore, "CursorHold", "failed renderer cleanup restores eventignore")
assert_eq(vim.o.lazyredraw, false, "failed renderer cleanup restores lazyredraw")
assert_eq(renderer_warning and renderer_warning:match("^%[power%-mode%]") ~= nil, true,
  "failed renderer cleanup emits prefixed warning")
vim.o.eventignore = original_eventignore
vim.o.lazyredraw = original_lazyredraw

print(string.format("\nRenderer tests: %d passed, %d failed", pass, fail))
if fail > 0 then vim.cmd("cquit! 1") end
