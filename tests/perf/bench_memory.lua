-- tests/perf/bench_memory.lua
--
-- Headless allocation profiler. For each scenario, runs a fixed number
-- of simulated frames driving the engine subsystems and reports the
-- net Lua memory delta plus the allocation rate in KB per simulated
-- second of wall time.
--
-- This intentionally does NOT call collectgarbage() during the run;
-- it measures gross allocations between two collect() bookends, then
-- divides by simulated time to give KB/s.
--
-- Usage:
--   nvim --headless -u tests/minimal_init.lua -l tests/perf/bench_memory.lua
--
-- Env vars:
--   PM_PERF_OUT       Output file path (default: stdout).
--   PM_PERF_SCENARIO  Run only this scenario id (default: all).
--   PM_PERF_FRAMES    Frames per scenario (default: 750 ≈ 30s @ 25fps).

vim.opt.rtp:prepend(".")
vim.cmd("runtime plugin/power-mode.lua")

local pm        = require("power-mode")
local particles = require("power-mode.particles")
local fire      = require("power-mode.presets.fire")
local fire_wall = require("power-mode.fire_wall")
local renderer  = require("power-mode.renderer")
local combo     = require("power-mode.combo")
local engine    = require("power-mode.engine")

local OUT_PATH      = os.getenv("PM_PERF_OUT")
local ONLY_SCENARIO = os.getenv("PM_PERF_SCENARIO")
local FRAMES        = tonumber(os.getenv("PM_PERF_FRAMES")) or 750
local FPS           = 25
local DT            = 1 / FPS

local function git_sha()
  local f = io.popen("git rev-parse --short HEAD 2>./tmp/null")
  if not f then return "unknown" end
  local s = f:read("*l") or "unknown"
  f:close()
  return s
end

local function iso_now() return os.date("!%Y-%m-%dT%H:%M:%SZ") end

local function nvim_version()
  local v = vim.version()
  return string.format("%d.%d.%d", v.major, v.minor, v.patch)
end

local function machine()
  return {
    os   = vim.loop.os_uname().sysname:lower(),
    arch = vim.loop.os_uname().machine,
    nvim = nvim_version(),
  }
end

local function reset_plugin(overrides)
  pcall(engine.stop)
  pcall(particles.clear)
  pcall(fire.clear)
  pcall(fire_wall.clear)
  pcall(renderer.cleanup)
  pcall(combo.cleanup)
  pm.setup(overrides)
  engine.stop()
  renderer.init()
  combo.init()
  fire_wall.init()
end

local function build_all_lists()
  local all = {}
  for _, p in ipairs(particles.get_active()) do all[#all + 1] = p end
  for _, p in ipairs(fire.get_active())      do all[#all + 1] = p end
  for _, p in ipairs(fire_wall.get_active()) do all[#all + 1] = p end
  return all
end

local function tick_frame()
  particles.update(DT)
  fire.update(DT)
  fire_wall.update(DT)
  renderer.render(build_all_lists())
  combo.update(DT)
end

local function spawn_n(n)
  for i = 1, n do
    particles.spawn(5 + (i % 20), 10 + (i % 50))
  end
end

local function drive_combo(streak)
  for _ = 1, streak do combo.increment() end
  fire_wall.spawn(combo.get_level(), combo.get_streak())
end

-- ---- scenarios (subset; same overrides as bench_hotspots) -----------------

local scenarios = {}
local function add(id, overrides, setup, respawn_each)
  scenarios[#scenarios + 1] = {
    id = id, overrides = overrides, setup = setup,
    respawn_each = respawn_each or 0,
  }
end

add("idle_baseline",
  {
    auto_enable = true,
    combo     = { enabled = false, shake = false },
    shake     = { mode = "none" },
    fire_wall = { enabled = false },
    particles = { preset = "explosion", max_particles = 10, count = { 0, 0 }, pool_size = 10 },
    engine    = { fps = FPS, stop_delay = 60000 },
  },
  function() end, 0)

add("particles_steady",
  {
    auto_enable = true,
    combo     = { enabled = false, shake = false },
    shake     = { mode = "none" },
    fire_wall = { enabled = false },
    particles = { preset = "explosion", cancel_on_new = false },
    engine    = { fps = FPS, stop_delay = 60000 },
  },
  function() spawn_n(60) end, 60)  -- respawn 60 every frame to mimic typing

add("full_load",
  {
    auto_enable = true,
    combo     = { enabled = true, shake = false, timeout = 60000 },
    shake     = { mode = "none" },
    fire_wall = { enabled = true, max_rows = 5 },
    particles = { preset = "explosion", cancel_on_new = false },
    engine    = { fps = FPS, stop_delay = 60000 },
  },
  function() drive_combo(30); spawn_n(60) end, 60)

add("long_session_60s",
  {
    auto_enable = true,
    combo     = { enabled = true, shake = false, timeout = 60000 },
    shake     = { mode = "none" },
    fire_wall = { enabled = true, max_rows = 5 },
    particles = { preset = "explosion", cancel_on_new = false },
    engine    = { fps = FPS, stop_delay = 60000 },
  },
  function() drive_combo(20); spawn_n(40) end, 40)

-- ---- run ------------------------------------------------------------------

local function run_one(sc, frames)
  reset_plugin(sc.overrides)
  sc.setup()

  -- Warm-up: a few frames to let pools / extmark caches stabilise.
  for _ = 1, 25 do tick_frame() end

  collectgarbage("collect")
  collectgarbage("collect")
  local kb_before = collectgarbage("count")
  collectgarbage("stop")

  local t0 = vim.loop.hrtime()
  for f = 1, frames do
    if sc.respawn_each > 0 and (f % 5) == 0 then
      spawn_n(sc.respawn_each)
    end
    tick_frame()
  end
  local elapsed_ns = vim.loop.hrtime() - t0

  local kb_after_no_gc = collectgarbage("count")
  collectgarbage("restart")
  collectgarbage("collect")
  collectgarbage("collect")
  local kb_after_gc = collectgarbage("count")

  local simulated_s = frames / FPS
  return {
    schema_version    = 1,
    tool              = "bench_memory.lua",
    git_sha           = git_sha(),
    timestamp         = iso_now(),
    machine           = machine(),
    scenario          = sc.id,
    config_overrides  = sc.overrides,
    iterations        = frames,
    warmup_iterations = 25,
    stages = {
      memory = {
        n               = frames,
        frames          = frames,
        simulated_s     = simulated_s,
        wall_ns         = elapsed_ns,
        wall_ms_total   = elapsed_ns / 1e6,
        kb_before       = kb_before,
        kb_after_no_gc  = kb_after_no_gc,
        kb_after_gc     = kb_after_gc,
        gross_alloc_kb  = kb_after_no_gc - kb_before,
        retained_kb     = kb_after_gc - kb_before,
        gross_kb_per_s  = (kb_after_no_gc - kb_before) / simulated_s,
        retained_kb_per_s = (kb_after_gc - kb_before) / simulated_s,
      },
    },
    notes = {
      "GC stopped during the measured window; restarted before final count.",
      "gross_kb_per_s = pre-GC delta / simulated_s",
      "retained_kb_per_s = post-GC delta / simulated_s (potential leak indicator)",
    },
  }
end

local out = { schema_version = 1, results = {} }
for _, sc in ipairs(scenarios) do
  if (not ONLY_SCENARIO) or ONLY_SCENARIO == sc.id then
    io.stderr:write("[bench_memory] scenario: " .. sc.id .. "\n")
    table.insert(out.results, run_one(sc, FRAMES))
  end
end

local json = vim.json.encode(out)
if OUT_PATH and OUT_PATH ~= "" then
  local f = assert(io.open(OUT_PATH, "w"))
  f:write(json); f:close()
  io.stderr:write("[bench_memory] wrote " .. OUT_PATH .. "\n")
else
  io.write(json, "\n")
end

vim.cmd("qa!")
