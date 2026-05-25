-- tests/perf/_validate_overhead.lua
-- Measures instrumentation overhead: runs the standard FULL_frame body
-- N times with and without per-iter hrtime() bookends, asserts the
-- difference is <PM_OVERHEAD_BAND (default 10%).

vim.opt.rtp:prepend(".")
vim.cmd("runtime plugin/power-mode.lua")

local BAND = tonumber(os.getenv("PM_OVERHEAD_BAND") or "0.10")
local N    = tonumber(os.getenv("PM_OVERHEAD_N")    or "200")

local pm        = require("power-mode")
local particles = require("power-mode.particles")
local fire      = require("power-mode.presets.fire")
local fire_wall = require("power-mode.fire_wall")
local renderer  = require("power-mode.renderer")
local combo     = require("power-mode.combo")
local engine    = require("power-mode.engine")

pm.setup({
  auto_enable = true,
  combo     = { enabled = true, shake = false, timeout = 60000 },
  shake     = { mode = "none" },
  fire_wall = { enabled = true, max_rows = 5 },
  particles = { preset = "explosion", cancel_on_new = false },
  engine    = { fps = 25, stop_delay = 60000 },
})
engine.stop()
renderer.init(); combo.init(); fire_wall.init()
for i = 1, 60 do particles.spawn(5 + (i % 20), 10 + (i % 50)) end
for _ = 1, 30 do combo.increment() end
fire_wall.spawn(combo.get_level(), combo.get_streak())

local DT = 1 / 25
local function build_all()
  local all = {}
  for _, p in ipairs(particles.get_active()) do all[#all + 1] = p end
  for _, p in ipairs(fire.get_active())      do all[#all + 1] = p end
  for _, p in ipairs(fire_wall.get_active()) do all[#all + 1] = p end
  return all
end
local function one_frame()
  particles.update(DT); fire.update(DT); fire_wall.update(DT)
  renderer.render(build_all()); combo.update(DT)
end

for _ = 1, 50 do one_frame() end
collectgarbage("collect")

-- Run baseline and instrumented multiple times, take the median of each
-- to dampen scheduler jitter.
local function trial_baseline()
  local t0 = vim.loop.hrtime()
  for _ = 1, N do one_frame() end
  return (vim.loop.hrtime() - t0) / N
end
local function trial_instrumented()
  local samples = {}
  for i = 1, N do
    local s = vim.loop.hrtime()
    one_frame()
    samples[i] = vim.loop.hrtime() - s
  end
  local sum = 0; for _, v in ipairs(samples) do sum = sum + v end
  return sum / N
end

local function median(xs)
  table.sort(xs); return xs[math.ceil(#xs / 2)]
end

local b_trials, i_trials = {}, {}
for _ = 1, 5 do
  b_trials[#b_trials + 1] = trial_baseline()
  i_trials[#i_trials + 1] = trial_instrumented()
end
local baseline_ns     = median(b_trials)
local instrumented_ns = median(i_trials)
local overhead = (instrumented_ns - baseline_ns) / baseline_ns
io.stdout:write(string.format(
  "baseline_ms=%.4f instrumented_ms=%.4f overhead=%+.3f band=%.2f\n",
  baseline_ns / 1e6, instrumented_ns / 1e6, overhead, BAND))
if math.abs(overhead) <= BAND then
  io.stdout:write("PASS\n")
  vim.cmd("qa!")
else
  io.stdout:write("FAIL overhead band exceeded\n")
  os.exit(1)
end
