-- tests/perf/bench_latency.lua
--
-- Headless spawn-to-rendered latency. For each scenario, the bench:
--   1) clears all subsystems
--   2) records t0 = hrtime()
--   3) calls particles.spawn(row, col)
--   4) runs the standard frame body until renderer.render() observes
--      the spawned particle, recording t1 = hrtime()
--   5) latency_ms = (t1 - t0) / 1e6
--
-- This isolates the cost of "one new particle reaching first paint" in
-- headless. It is NOT a substitute for TUI-perceived latency (T4), but
-- it is the headless lower bound and is useful for trend detection.
--
-- Usage:
--   nvim --headless -u tests/minimal_init.lua -l tests/perf/bench_latency.lua

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
local ITERS         = tonumber(os.getenv("PM_PERF_ITERS"))  or 100
local WARMUP        = tonumber(os.getenv("PM_PERF_WARMUP")) or 20
local FPS           = 25
local DT            = 1 / FPS

local function git_sha()
  local f = io.popen("git rev-parse --short HEAD 2>./tmp/null")
  if not f then return "unknown" end
  local s = f:read("*l") or "unknown"; f:close(); return s
end
local function iso_now() return os.date("!%Y-%m-%dT%H:%M:%SZ") end
local function nvim_version()
  local v = vim.version()
  return string.format("%d.%d.%d", v.major, v.minor, v.patch)
end
local function machine()
  return {
    os = vim.loop.os_uname().sysname:lower(),
    arch = vim.loop.os_uname().machine,
    nvim = nvim_version(),
  }
end

local function percentile(s, p)
  if #s == 0 then return 0 end
  return s[math.max(1, math.min(#s, math.ceil(#s * p)))]
end
local function summarise_ns(ns)
  table.sort(ns)
  local n = #ns
  local sum = 0; for _,v in ipairs(ns) do sum = sum + v end
  local mean = n > 0 and sum / n or 0
  local var = 0; for _,v in ipairs(ns) do var = var + (v-mean)*(v-mean) end
  var = n > 1 and var / (n-1) or 0
  local ms = function(x) return x / 1e6 end
  return {
    n = n,
    p50_ms = ms(percentile(ns, 0.50)),
    p95_ms = ms(percentile(ns, 0.95)),
    p99_ms = ms(percentile(ns, 0.99)),
    max_ms = ms(ns[n] or 0),
    mean_ms = ms(mean),
    stddev_ms = ms(math.sqrt(var)),
  }
end

local function reset_plugin(overrides)
  pcall(engine.stop)
  pcall(particles.clear); pcall(fire.clear); pcall(fire_wall.clear)
  pcall(renderer.cleanup); pcall(combo.cleanup)
  pm.setup(overrides)
  engine.stop()
  renderer.init(); combo.init(); fire_wall.init()
end

local function build_all_lists()
  local all = {}
  for _, p in ipairs(particles.get_active()) do all[#all + 1] = p end
  for _, p in ipairs(fire.get_active())      do all[#all + 1] = p end
  for _, p in ipairs(fire_wall.get_active()) do all[#all + 1] = p end
  return all
end

-- Wrap renderer.render to detect when our marker particle has been drawn.
-- We tag particles by their initial (row, col) and watch for that pair to
-- appear in the list passed to renderer.render.
local saw_marker = false
local marker_row, marker_col = -1, -1
local orig_render = renderer.render
renderer.render = function(list)
  if not saw_marker then
    for _, p in ipairs(list) do
      if p and p.row == marker_row and p.col == marker_col then
        saw_marker = true
        break
      end
    end
  end
  return orig_render(list)
end

local function one_iteration()
  saw_marker = false
  marker_row = 7
  marker_col = 12

  local t0 = vim.loop.hrtime()
  particles.spawn(marker_row, marker_col)

  -- Drive frames until renderer.render sees the new particle.
  -- In headless this should happen on the very first tick.
  local guard = 0
  while not saw_marker and guard < 5 do
    particles.update(DT)
    fire.update(DT)
    fire_wall.update(DT)
    renderer.render(build_all_lists())
    combo.update(DT)
    guard = guard + 1
  end
  local t1 = vim.loop.hrtime()
  return t1 - t0
end

local scenarios = {}
local function add(id, overrides, setup)
  scenarios[#scenarios + 1] = { id = id, overrides = overrides, setup = setup }
end

add("cold_idle",
  {
    auto_enable = true,
    combo     = { enabled = false, shake = false },
    shake     = { mode = "none" },
    fire_wall = { enabled = false },
    particles = { preset = "explosion", cancel_on_new = false },
    engine    = { fps = FPS, stop_delay = 60000 },
  },
  function() end)

add("under_load",
  {
    auto_enable = true,
    combo     = { enabled = true, shake = false, timeout = 60000 },
    shake     = { mode = "none" },
    fire_wall = { enabled = true, max_rows = 5 },
    particles = { preset = "explosion", cancel_on_new = false },
    engine    = { fps = FPS, stop_delay = 60000 },
  },
  function()
    for _ = 1, 30 do combo.increment() end
    fire_wall.spawn(combo.get_level(), combo.get_streak())
    for i = 1, 60 do particles.spawn(5 + (i%20), 30 + (i%40)) end
  end)

local function run_one(sc)
  reset_plugin(sc.overrides)
  sc.setup()
  for _ = 1, WARMUP do one_iteration() end
  local samples = {}
  for i = 1, ITERS do samples[i] = one_iteration() end
  return {
    schema_version    = 1,
    tool              = "bench_latency.lua",
    git_sha           = git_sha(),
    timestamp         = iso_now(),
    machine           = machine(),
    scenario          = sc.id,
    config_overrides  = sc.overrides,
    iterations        = ITERS,
    warmup_iterations = WARMUP,
    stages = { spawn_to_render = summarise_ns(samples) },
    notes  = {
      "Headless lower-bound. Wraps renderer.render to detect first frame "
      .. "where the spawned (row, col) appears in the active list.",
      "Real-world latency includes vim.schedule defer + libuv timer phase, "
      .. "which is measured by the TUI bench (T4).",
    },
  }
end

local out = { schema_version = 1, results = {} }
for _, sc in ipairs(scenarios) do
  if (not ONLY_SCENARIO) or ONLY_SCENARIO == sc.id then
    io.stderr:write("[bench_latency] scenario: " .. sc.id .. "\n")
    table.insert(out.results, run_one(sc))
  end
end

local json = vim.json.encode(out)
if OUT_PATH and OUT_PATH ~= "" then
  local f = assert(io.open(OUT_PATH, "w"))
  f:write(json); f:close()
  io.stderr:write("[bench_latency] wrote " .. OUT_PATH .. "\n")
else
  io.write(json, "\n")
end

vim.cmd("qa!")
