--- Tests for config.lua
local config = require("power-mode.config")

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

-- Test 1: defaults load correctly
local defaults = config.get_defaults()
assert_eq(defaults.auto_enable, true, "default auto_enable")
assert_eq(defaults.particles.preset, "rightburst", "default preset")
assert_eq(defaults.particles.cancel_on_new, true, "default cancel_on_new")
assert_eq(defaults.particles.pool_size, 60, "default pool_size")
assert_eq(defaults.engine.fps, 25, "default fps")
assert_eq(defaults.shake.mode, "none", "default shake mode")
assert_eq(defaults.combo.enabled, true, "default combo enabled")
assert_eq(defaults.combo.position, "top-right", "default combo position")
assert_eq(defaults.combo.timeout, 3000, "default combo timeout")
assert_eq(defaults.backspace.enabled, true, "default backspace enabled")

-- Test 2: resolve with empty opts returns defaults
config.resolve({})
local cfg = config.get()
assert_eq(cfg.particles.preset, "rightburst", "resolve empty → preset")
assert_eq(cfg.engine.fps, 25, "resolve empty → fps")

-- Test 3: resolve merges user opts
config.resolve({ particles = { preset = "fountain" }, engine = { fps = 30 } })
cfg = config.get()
assert_eq(cfg.particles.preset, "fountain", "merge preset override")
assert_eq(cfg.engine.fps, 30, "merge fps override")
-- Other defaults still intact
assert_eq(cfg.particles.pool_size, 60, "merge preserves pool_size")
assert_eq(cfg.combo.enabled, true, "merge preserves combo")

-- Test 4: deep merge preserves nested defaults
config.resolve({ combo = { position = "bottom-left" } })
cfg = config.get()
assert_eq(cfg.combo.position, "bottom-left", "deep merge combo position")
assert_eq(cfg.combo.timeout, 3000, "deep merge preserves timeout")
assert_eq(cfg.combo.shake, true, "deep merge preserves shake")

-- Test 5: validation clamps invalid values
config.resolve({ engine = { fps = 999 } })
cfg = config.get()
assert_eq(cfg.engine.fps, 25, "validation clamps fps > 60")

config.resolve({ shake = { mode = "invalid" } })
cfg = config.get()
assert_eq(cfg.shake.mode, "none", "validation rejects invalid shake mode")

config.resolve({ combo = { position = "center" } })
cfg = config.get()
assert_eq(cfg.combo.position, "top-right", "validation rejects invalid combo position")

-- Test 6: vim globals override
vim.g.power_mode_particle_preset = "stars"
config.resolve({})
cfg = config.get()
assert_eq(cfg.particles.preset, "stars", "vim global preset override")
vim.g.power_mode_particle_preset = nil  -- cleanup

-- Test 7: setup opts override vim globals
vim.g.power_mode_particle_preset = "stars"
config.resolve({ particles = { preset = "emoji" } })
cfg = config.get()
assert_eq(cfg.particles.preset, "emoji", "setup opts beat vim globals")
vim.g.power_mode_particle_preset = nil  -- cleanup

-- Test 8: color overrides
config.resolve({ colors = { color_1 = { "#FF0000", "#110000", 196, 52 } } })
cfg = config.get()
assert_eq(cfg.colors.color_1[1], "#FF0000", "color override fg")
assert_eq(cfg.colors.color_2[1], "#FF1493", "color_2 preserved")

-- Print results
print(string.format("\n=== Config Tests: %d passed, %d failed ===", pass, fail))
if fail > 0 then
  vim.cmd("cquit! 1")
end
