--- Unit tests for fire_wall module
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

-- Test 2: spawn does nothing when mode is "none"
fw.spawn(0)
assert_eq("no particles in none mode", #fw.get_active(), 0)

-- Test 3: set_mode to ember_rise
fw.set_mode("ember_rise")
assert_eq("mode changed to ember_rise", fw.get_mode(), "ember_rise")

-- Test 4: spawn creates particles in ember_rise mode
fw.clear()
fw.spawn(0)
assert_true("ember_rise spawns particles", #fw.get_active() > 0)

-- Test 5: combo level increases particle count
fw.clear()
fw.spawn(0) -- combo level 0
local count_level0 = #fw.get_active()
fw.clear()
fw.spawn(4) -- combo level 4
local count_level4 = #fw.get_active()
assert_true("higher combo = more particles", count_level4 >= count_level0)

-- Test 6: set_mode to fire_columns
fw.set_mode("fire_columns")
assert_eq("mode changed to fire_columns", fw.get_mode(), "fire_columns")
fw.clear()
fw.spawn(2)
assert_true("fire_columns spawns particles", #fw.get_active() > 0)

-- Test 7: set_mode to inferno
fw.set_mode("inferno")
assert_eq("mode changed to inferno", fw.get_mode(), "inferno")
fw.clear()
fw.spawn(4)
local inferno_count = #fw.get_active()
assert_true("inferno spawns many particles", inferno_count > 5)

-- Test 8: particles spawn at bottom of editor
fw.clear()
fw.spawn(2)
local particles = fw.get_active()
local all_at_bottom = true
for _, p in ipairs(particles) do
  if p.y < vim.o.lines - 5 then
    all_at_bottom = false
    break
  end
end
assert_true("particles spawn near bottom", all_at_bottom)

-- Test 9: particles have upward velocity
local all_upward = true
for _, p in ipairs(particles) do
  if p.vy >= 0 then
    all_upward = false
    break
  end
end
assert_true("particles have upward velocity", all_upward)

-- Test 10: update removes expired particles
fw.clear()
fw.spawn(0)
-- Force all particles to expire
for _, p in ipairs(fw.get_active()) do
  p.lifetime = 0
end
fw.update(0.001)
assert_eq("expired particles removed", #fw.get_active(), 0)

-- Test 11: clear removes all particles
fw.spawn(4)
fw.spawn(4)
assert_true("has particles before clear", #fw.get_active() > 0)
fw.clear()
assert_eq("clear removes all", #fw.get_active(), 0)

-- Test 12: set_mode to "none" and back clears particles
fw.set_mode("inferno")
fw.spawn(4)
assert_true("has inferno particles", #fw.get_active() > 0)
fw.set_mode("none")
assert_eq("set to none clears particles", #fw.get_active(), 0)

-- Test 13: invalid mode rejected
fw.set_mode("banana")
assert_eq("invalid mode stays as none", fw.get_mode(), "none")

-- Test 14: particles have valid color_idx
fw.set_mode("fire_columns")
fw.clear()
fw.spawn(2)
local all_valid_colors = true
for _, p in ipairs(fw.get_active()) do
  if p.color_idx < 1 or p.color_idx > 8 then
    all_valid_colors = false
    break
  end
end
assert_true("all particles have valid color_idx", all_valid_colors)

-- Test 15: particles have valid chars
local all_have_chars = true
for _, p in ipairs(fw.get_active()) do
  if not p.char or #p.char == 0 then
    all_have_chars = false
    break
  end
end
assert_true("all particles have chars", all_have_chars)

-- Test 16: config override for fire_wall.colors
package.loaded["power-mode.config"] = nil
package.loaded["power-mode.fire_wall"] = nil
config = require("power-mode.config")
config.resolve({ fire_wall = { mode = "ember_rise", colors = { 3, 4 } } })
fw = require("power-mode.fire_wall")
fw.spawn(0)
local custom_colors_ok = true
for _, p in ipairs(fw.get_active()) do
  if p.color_idx ~= 3 and p.color_idx ~= 4 then
    custom_colors_ok = false
    break
  end
end
assert_true("custom colors config applied", custom_colors_ok)

print("")
print(string.format("=== Fire Wall Tests: %d passed, %d failed ===", pass, fail))
if fail > 0 then vim.cmd("cquit! 1") end
