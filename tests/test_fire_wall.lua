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

-- Test 1: default mode is "none"
assert_eq("default mode is none", fw.get_mode(), "none")

-- Test 2: get_active returns empty (fire wall manages its own window)
fw.spawn(0)
assert_eq("get_active always empty", #fw.get_active(), 0)

-- Test 3: set_mode to ember_rise
fw.set_mode("ember_rise")
assert_eq("mode changed to ember_rise", fw.get_mode(), "ember_rise")

-- Test 4: set_mode to fire_columns
fw.set_mode("fire_columns")
assert_eq("mode changed to fire_columns", fw.get_mode(), "fire_columns")

-- Test 5: set_mode to inferno
fw.set_mode("inferno")
assert_eq("mode changed to inferno", fw.get_mode(), "inferno")

-- Test 6: set_mode to "none" clears state
fw.set_mode("none")
assert_eq("set to none", fw.get_mode(), "none")

-- Test 7: invalid mode rejected
fw.set_mode("banana")
assert_eq("invalid mode stays as none", fw.get_mode(), "none")

-- Test 8: spawn sets combo level without error
fw.set_mode("fire_columns")
local ok = pcall(fw.spawn, 0)
assert_true("spawn level 0 no error", ok)

-- Test 9: spawn with high combo no error
ok = pcall(fw.spawn, 4)
assert_true("spawn level 4 no error", ok)

-- Test 10: update runs without error
ok = pcall(fw.update, 0.04)
assert_true("update no error", ok)

-- Test 11: clear runs without error
ok = pcall(fw.clear)
assert_true("clear no error", ok)
assert_eq("mode unchanged after clear", fw.get_mode(), "fire_columns")

-- Test 12: init creates fire highlight groups
fw.init()
local hl = vim.api.nvim_get_hl(0, { name = "PowerModeFire1" })
assert_true("PowerModeFire1 exists after init", hl.fg ~= nil or hl.ctermfg ~= nil)

-- Test 13: PowerModeFire2 exists
hl = vim.api.nvim_get_hl(0, { name = "PowerModeFire2" })
assert_true("PowerModeFire2 exists", hl.fg ~= nil or hl.ctermfg ~= nil)

-- Test 14: PowerModeFire3 exists
hl = vim.api.nvim_get_hl(0, { name = "PowerModeFire3" })
assert_true("PowerModeFire3 exists", hl.fg ~= nil or hl.ctermfg ~= nil)

-- Test 15: PowerModeFireBg exists
hl = vim.api.nvim_get_hl(0, { name = "PowerModeFireBg" })
assert_true("PowerModeFireBg exists", hl ~= nil)

-- Test 16: get_active is always empty (self-managed window)
fw.set_mode("inferno")
fw.spawn(4)
fw.update(0.04)
assert_eq("get_active empty for inferno", #fw.get_active(), 0)

print("")
print(string.format("=== Fire Wall Tests: %d passed, %d failed ===", pass, fail))
if fail > 0 then vim.cmd("cquit! 1") end
