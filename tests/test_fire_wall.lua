--- Unit tests for fire_wall module (cacafire heat-buffer, self-managed window)
local pass, fail = 0, 0
local function assert_eq(name, got, expected)
  if got == expected then
    pass = pass + 1
  else
    fail = fail + 1
    print("FAIL: " .. name .. " | got: " .. tostring(got) .. " | expected: " .. tostring(expected))
  end
end
local function assert_true(name, val)
  if val then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

-- Reset modules to clean state
package.loaded["power-mode.config"] = nil
package.loaded["power-mode.fire_wall"] = nil

local config = require("power-mode.config")
config.resolve({})

local fw = require("power-mode.fire_wall")

-- Test 1: default is disabled
assert_eq("default is disabled", fw.is_enabled(), false)

-- Test 2: get_mode returns "none" when disabled
assert_eq("get_mode when disabled", fw.get_mode(), "none")

-- Test 3: get_active returns empty (fire wall manages its own window)
fw.spawn(0)
assert_eq("get_active always empty", #fw.get_active(), 0)

-- Test 4: set_enabled(true)
fw.set_enabled(true)
assert_eq("enabled after set_enabled(true)", fw.is_enabled(), true)
assert_eq("get_mode when enabled", fw.get_mode(), "on")

-- Test 5: set_enabled(false)
fw.set_enabled(false)
assert_eq("disabled after set_enabled(false)", fw.is_enabled(), false)

-- Test 6: legacy set_mode("fire_columns") enables
fw.set_mode("fire_columns")
assert_eq("legacy fire_columns enables", fw.is_enabled(), true)

-- Test 7: legacy set_mode("none") disables
fw.set_mode("none")
assert_eq("legacy none disables", fw.is_enabled(), false)

-- Test 8: set_mode("on") enables
fw.set_mode("on")
assert_eq("set_mode on enables", fw.is_enabled(), true)

-- Test 9: set_mode("off") disables
fw.set_mode("off")
assert_eq("set_mode off disables", fw.is_enabled(), false)

-- Test 10: invalid mode rejected
fw.set_mode("banana")
assert_eq("invalid mode stays disabled", fw.is_enabled(), false)

-- Test 11: spawn no error when enabled
fw.set_enabled(true)
local ok = pcall(fw.spawn, 0)
assert_true("spawn level 0 no error", ok)

-- Test 12: spawn with high combo no error
ok = pcall(fw.spawn, 4)
assert_true("spawn level 4 no error", ok)

-- Test 13: update runs without error
ok = pcall(fw.update, 0.04)
assert_true("update no error", ok)

-- Test 14: cool_down runs without error
ok = pcall(fw.cool_down)
assert_true("cool_down no error", ok)

-- Test 15: clear runs without error
ok = pcall(fw.clear)
assert_true("clear no error", ok)
assert_eq("still enabled after clear", fw.is_enabled(), true)

-- Test 16: init creates fire highlight groups
fw.init()
local hl = vim.api.nvim_get_hl(0, { name = "PowerModeFire1" })
assert_true("PowerModeFire1 exists after init", hl.fg ~= nil or hl.ctermfg ~= nil)

-- Test 17: PowerModeFire2 exists
hl = vim.api.nvim_get_hl(0, { name = "PowerModeFire2" })
assert_true("PowerModeFire2 exists", hl.fg ~= nil or hl.ctermfg ~= nil)

-- Test 18: PowerModeFireBg exists
hl = vim.api.nvim_get_hl(0, { name = "PowerModeFireBg" })
assert_true("PowerModeFireBg exists", hl ~= nil)

-- Test 19: get_active empty when enabled
fw.spawn(4)
fw.update(0.04)
assert_eq("get_active empty when enabled", #fw.get_active(), 0)

-- Test 20: legacy config compat (fire_wall.mode → enabled)
package.loaded["power-mode.config"] = nil
local config2 = require("power-mode.config")
config2.resolve({ fire_wall = { mode = "fire_columns" } })
assert_eq("legacy mode converted to enabled", config2.get().fire_wall.enabled, true)

print("")
print(string.format("=== Fire Wall Tests: %d passed, %d failed ===", pass, fail))
if fail > 0 then vim.cmd("cquit! 1") end
