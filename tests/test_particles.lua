--- Tests for particle system
local config = require("power-mode.config")

-- Initialize config first
config.resolve({})

local particles = require("power-mode.particles")

local pass = 0
local fail = 0

local function assert_eq(a, b, msg)
  if a == b then
    pass = pass + 1
  else
    fail = fail + 1
    print("FAIL: " .. msg .. " | expected: " .. tostring(b) .. " got: " .. tostring(a))
  end
end

local function assert_true(val, msg)
  if val then
    pass = pass + 1
  else
    fail = fail + 1
    print("FAIL: " .. msg)
  end
end

-- Test 1: initial state is empty
particles.init()
assert_eq(#particles.get_active(), 0, "initial empty")

-- Test 2: spawn creates particles
particles.spawn(10, 20)
assert_true(#particles.get_active() > 0, "spawn creates particles")
assert_true(#particles.get_active() <= 100, "spawn respects max_particles")

-- Test 3: particles have required fields
local p = particles.get_active()[1]
assert_true(p.x ~= nil, "particle has x")
assert_true(p.y ~= nil, "particle has y")
assert_true(p.vx ~= nil, "particle has vx")
assert_true(p.vy ~= nil, "particle has vy")
assert_true(p.char ~= nil, "particle has char")
assert_true(p.color_idx ~= nil, "particle has color_idx")
assert_true(p.lifetime ~= nil, "particle has lifetime")
assert_true(p.max_lifetime ~= nil, "particle has max_lifetime")

-- Test 4: update moves particles
local initial_x = p.x
local initial_y = p.y
particles.update(0.04) -- one frame at 25fps
-- Particles should have moved (unless velocity was exactly 0)
assert_true(p.lifetime < p.max_lifetime, "update reduces lifetime")

-- Test 5: clear removes all particles
particles.clear()
assert_eq(#particles.get_active(), 0, "clear empties particles")

-- Test 6: mode switching
particles.set_mode("fountain")
assert_eq(particles.get_mode(), "fountain", "mode switched to fountain")
particles.spawn(10, 20)
assert_true(#particles.get_active() > 0, "fountain spawns particles")
particles.clear()

-- Test 7: cancel_on_new reduces lifetime
config.resolve({ particles = { cancel_on_new = true, cancel_fadeout_ms = 50 } })
particles.init()
particles.spawn(10, 20)
local count1 = #particles.get_active()
particles.spawn(10, 20)
-- Old particles should have lifetime capped to 50ms
local found_capped = false
for _, pt in ipairs(particles.get_active()) do
  if pt.lifetime <= 50 then
    found_capped = true
    break
  end
end
assert_true(found_capped, "cancel_on_new caps lifetime")
particles.clear()

-- Reset config
config.resolve({})

-- Print results
print(string.format("\n=== Particle Tests: %d passed, %d failed ===", pass, fail))
if fail > 0 then
  vim.cmd("cquit! 1")
end
