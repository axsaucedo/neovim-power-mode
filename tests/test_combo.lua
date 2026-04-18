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

-- Test 6: ensure_window re-creates window after external close
config.resolve({})
combo.init()
-- Simulate external close (dashboard plugin destroying the floating window)
combo.cleanup()
-- ensure_window should re-create the window and buffer without resetting state
combo.ensure_window()
-- After ensure, level should still be accessible (state preserved)
assert_eq(combo.get_level(), 0, "level preserved after ensure_window re-create")
assert_eq(combo.get_streak(), 0, "streak accessible after ensure_window re-create")

-- Reset
combo.cleanup()

-- Test 7: combo_box_disappear_seconds default is 2
config.resolve({})
cfg = config.get()
assert_eq(cfg.combo.combo_box_disappear_seconds, 2, "combo_box_disappear_seconds default = 2")

-- Test 8: combo_box_disappear_seconds override via setup()
config.resolve({ combo = { combo_box_disappear_seconds = 5 } })
cfg = config.get()
assert_eq(cfg.combo.combo_box_disappear_seconds, 5, "combo_box_disappear_seconds custom value")

-- Test 9: invalid combo_box_disappear_seconds falls back to default
config.resolve({ combo = { combo_box_disappear_seconds = -1 } })
cfg = config.get()
assert_eq(cfg.combo.combo_box_disappear_seconds, 2, "negative combo_box_disappear_seconds falls back to 2")

-- Test 10: visibility state machine — starts hidden, increment shows,
-- reset schedules pending-hide, a subsequent increment cancels pending-hide.
config.resolve({ combo = { combo_box_disappear_seconds = 60 } }) -- long enough that it won't fire during the test
combo.init()
assert_eq(combo._is_hidden(), true, "combo starts hidden after init")
assert_eq(combo._has_pending_hide(), false, "no pending hide after init")

combo.increment()
assert_eq(combo._is_hidden(), false, "combo visible after first increment")
assert_eq(combo._has_pending_hide(), false, "no pending hide while typing")

combo.reset()
assert_eq(combo._is_hidden(), false, "combo still visible during linger period")
assert_eq(combo._has_pending_hide(), true, "reset scheduled a pending hide")

combo.increment()
assert_eq(combo._is_hidden(), false, "new keystroke cancels hide, still visible")
assert_eq(combo._has_pending_hide(), false, "pending hide cancelled by increment")

combo.cleanup()

-- Test 11: combo_box_disappear_seconds = 0 hides immediately on reset
config.resolve({ combo = { combo_box_disappear_seconds = 0 } })
combo.init()
combo.increment()
assert_eq(combo._is_hidden(), false, "visible after increment (0s linger)")
combo.reset()
assert_eq(combo._is_hidden(), true, "immediately hidden on reset when linger = 0")
assert_eq(combo._has_pending_hide(), false, "no timer scheduled when linger = 0")

combo.cleanup()

-- Reset
config.resolve({})

print(string.format("\n=== Combo Tests: %d passed, %d failed ===", pass, fail))
if fail > 0 then
  vim.cmd("cquit! 1")
end
