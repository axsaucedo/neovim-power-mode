--- Unit tests for fire_wall module (cacafire heat-buffer)
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

-- Test 4: spawn + update creates particles in ember_rise mode
fw.clear()
fw.spawn(0)
fw.update(0.04)
assert_true("ember_rise has particles after update", #fw.get_active() > 0)

-- Test 5: combo level increases heat (more particles)
fw.clear()
fw.spawn(0)
fw.update(0.04)
local count_level0 = #fw.get_active()
fw.clear()
fw.spawn(4)
fw.update(0.04)
local count_level4 = #fw.get_active()
assert_true("higher combo = more particles", count_level4 >= count_level0)

-- Test 6: set_mode to fire_columns
fw.set_mode("fire_columns")
assert_eq("mode changed to fire_columns", fw.get_mode(), "fire_columns")
fw.clear()
fw.spawn(2)
fw.update(0.04)
assert_true("fire_columns has particles after update", #fw.get_active() > 0)

-- Test 7: set_mode to inferno
fw.set_mode("inferno")
assert_eq("mode changed to inferno", fw.get_mode(), "inferno")
fw.clear()
fw.spawn(4)
fw.update(0.04)
local inferno_count = #fw.get_active()
assert_true("inferno spawns many particles", inferno_count > 5)

-- Test 8: particles render near bottom of editor
fw.clear()
fw.spawn(2)
fw.update(0.04)
local particles = fw.get_active()
local all_at_bottom = true
for _, p in ipairs(particles) do
  if p.y < vim.o.lines * 0.5 then
    all_at_bottom = false
    break
  end
end
assert_true("particles near bottom of editor", all_at_bottom)

-- Test 9: particles have valid characters (heat-buffer chars)
local valid_chars = { ["█"] = true, ["▓"] = true, ["▒"] = true, ["░"] = true, ["·"] = true }
local all_valid_chars = true
for _, p in ipairs(particles) do
  if not valid_chars[p.char] then
    all_valid_chars = false
    break
  end
end
assert_true("all particles have heat-buffer chars", all_valid_chars)

-- Test 10: update with no spawn gradually cools (particles decrease)
fw.clear()
fw.spawn(4)
fw.update(0.04)
local initial_count = #fw.get_active()
-- Update multiple times without seeding
for _ = 1, 20 do
  fw.update(0.04)
end
local cooled_count = #fw.get_active()
assert_true("heat dissipates over time", cooled_count <= initial_count)

-- Test 11: clear removes all particles and resets grid
fw.spawn(4)
fw.update(0.04)
assert_true("has particles before clear", #fw.get_active() > 0)
fw.clear()
assert_eq("clear removes all", #fw.get_active(), 0)

-- Test 12: set_mode to "none" clears particles
fw.set_mode("inferno")
fw.spawn(4)
fw.update(0.04)
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
fw.update(0.04)
local all_valid_colors = true
for _, p in ipairs(fw.get_active()) do
  if p.color_idx < 1 or p.color_idx > 8 then
    all_valid_colors = false
    break
  end
end
assert_true("all particles have valid color_idx", all_valid_colors)

-- Test 15: particles have lifetime/max_lifetime for blend calculation
local all_have_lifetime = true
for _, p in ipairs(fw.get_active()) do
  if not p.lifetime or not p.max_lifetime then
    all_have_lifetime = false
    break
  end
end
assert_true("all particles have lifetime fields", all_have_lifetime)

-- Test 16: mode params differ between modes
fw.set_mode("ember_rise")
fw.clear()
fw.spawn(4)
fw.update(0.04)
local ember_count = #fw.get_active()
fw.set_mode("inferno")
fw.clear()
fw.spawn(4)
fw.update(0.04)
local inferno_count2 = #fw.get_active()
assert_true("inferno produces more particles than ember_rise", inferno_count2 >= ember_count)

print("")
print(string.format("=== Fire Wall Tests: %d passed, %d failed ===", pass, fail))
if fail > 0 then vim.cmd("cquit! 1") end
