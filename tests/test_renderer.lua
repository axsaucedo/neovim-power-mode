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

power_mode.disable()

local function resources_restored(windows, buffers)
  return #vim.api.nvim_list_wins() == windows
    and #vim.api.nvim_list_bufs() == buffers
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
combo.increment()
fire_wall.spawn(2, 25)
fire_wall.update(0)
renderer.render({ {
  x = 20,
  y = 20,
  char = "*",
  lifetime = 100,
  max_lifetime = 200,
  color_idx = 1,
} })
local original_eventignore = vim.o.eventignore
local original_lazyredraw = vim.o.lazyredraw
vim.o.eventignore = "CursorHold"
vim.o.lazyredraw = false
power_mode.disable()

local all_particle_windows_parked = true
for _, win in ipairs(vim.api.nvim_list_wins()) do
  if win ~= vim.api.nvim_get_current_win() then
    local cfg = vim.api.nvim_win_get_config(win)
    if cfg.relative == "editor" and cfg.row ~= -10 then
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

print(string.format("\nRenderer tests: %d passed, %d failed", pass, fail))
if fail > 0 then vim.cmd("cquit! 1") end
