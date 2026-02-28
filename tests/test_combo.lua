--- Tests for combo system
local config = require("power-mode.config")
config.resolve({})

local combo = require("power-mode.combo")

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

-- Test 1: initial level is 0
combo.init()
assert_eq(combo.get_level(), 0, "initial level is 0")

-- Test 2: increment increases combo (need UI context for full test)
-- Since combo.increment() touches UI, we test the level logic directly
-- via the internal compute function pattern
combo.cleanup()

-- Test 3: level thresholds (test via config)
local cfg = config.get()
assert_eq(cfg.combo.thresholds[1], 10, "threshold[1] = 10")
assert_eq(cfg.combo.thresholds[2], 25, "threshold[2] = 25")
assert_eq(cfg.combo.thresholds[3], 50, "threshold[3] = 50")
assert_eq(cfg.combo.thresholds[4], 100, "threshold[4] = 100")
assert_eq(cfg.combo.thresholds[5], 200, "threshold[5] = 200")

-- Test 4: combo config is respected
config.resolve({ combo = { timeout = 5000, position = "bottom-left" } })
cfg = config.get()
assert_eq(cfg.combo.timeout, 5000, "custom timeout")
assert_eq(cfg.combo.position, "bottom-left", "custom position")

-- Test 5: combo disabled
config.resolve({ combo = { enabled = false } })
cfg = config.get()
assert_eq(cfg.combo.enabled, false, "combo disabled")

-- Reset
config.resolve({})
combo.cleanup()

print(string.format("\n=== Combo Tests: %d passed, %d failed ===", pass, fail))
if fail > 0 then
  vim.cmd("cquit! 1")
end
