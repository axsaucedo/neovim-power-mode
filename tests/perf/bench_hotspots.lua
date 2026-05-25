-- tests/perf/bench_hotspots.lua
--
-- Headless per-stage microbench. Drives each engine subsystem in
-- isolation, times it with vim.loop.hrtime(), and emits a JSON array
-- of scenario results conforming to schema_version=1 (see DESIGN.md §2).
--
-- Usage:
--   nvim --headless -u tests/minimal_init.lua -l tests/perf/bench_hotspots.lua
--
-- Env vars:
--   PM_PERF_OUT       Output file path (default: stdout).
--   PM_PERF_SCENARIO  Run only this scenario id (default: all).
--   PM_PERF_ITERS     Iterations per stage (default: 200).
--   PM_PERF_WARMUP    Warm-up iterations (default: 50).

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
local ITERS         = tonumber(os.getenv("PM_PERF_ITERS"))  or 200
local WARMUP        = tonumber(os.getenv("PM_PERF_WARMUP")) or 50
local DT            = 1 / 25

local function git_sha()
  local f = io.popen("git rev-parse --short HEAD 2>./tmp/null")
  if not f then return "unknown" end
  local s = f:read("*l") or "unknown"
  f:close()
  return s
end

local function iso_now()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

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

-- ---- stats ----------------------------------------------------------------

local function percentile(sorted, p)
  if #sorted == 0 then return 0 end
  local idx = math.max(1, math.min(#sorted, math.ceil(#sorted * p)))
  return sorted[idx]
end

local function summarise_ns(samples_ns)
  table.sort(samples_ns)
  local n = #samples_ns
  local sum = 0
  for _, v in ipairs(samples_ns) do sum = sum + v end
  local mean = n > 0 and sum / n or 0
  local var = 0
  for _, v in ipairs(samples_ns) do var = var + (v - mean) * (v - mean) end
  var = n > 1 and var / (n - 1) or 0
  local function ms(x) return x / 1e6 end
  return {
    n = n,
    p50_ms = ms(percentile(samples_ns, 0.50)),
    p95_ms = ms(percentile(samples_ns, 0.95)),
    p99_ms = ms(percentile(samples_ns, 0.99)),
    max_ms = ms(samples_ns[n] or 0),
    mean_ms = ms(mean),
    stddev_ms = ms(math.sqrt(var)),
  }
end

local function time_stage(fn, iters, warmup)
  for _ = 1, warmup do fn() end
  collectgarbage("collect")
  local samples = {}
  for i = 1, iters do
    local t0 = vim.loop.hrtime()
    fn()
    samples[i] = vim.loop.hrtime() - t0
  end
  return summarise_ns(samples)
end

-- ---- scenario helpers -----------------------------------------------------

local function reset_plugin(overrides)
  pcall(engine.stop)
  pcall(particles.clear)
  pcall(fire.clear)
  pcall(fire_wall.clear)
  pcall(renderer.cleanup)
  pcall(combo.cleanup)
  pm.setup(overrides)
  -- Stop the real timer; we drive ticks manually.
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

-- Returns the per-stage table. Active list shapes are set up by `setup_state`
-- which is scenario-specific.
local function measure_full_frame(setup_state)
  setup_state()
  local stages = {}

  stages["particles.update"] = time_stage(function() particles.update(DT) end, ITERS, WARMUP)
  stages["fire.update"]      = time_stage(function() fire.update(DT) end,      ITERS, WARMUP)
  stages["fire_wall.update"] = time_stage(function() fire_wall.update(DT) end, ITERS, WARMUP)
  stages["merge_lists"]      = time_stage(function() local _ = build_all_lists() end, ITERS, WARMUP)
  stages["renderer.render"]  = time_stage(function() renderer.render(build_all_lists()) end, ITERS, WARMUP)
  stages["combo.update"]     = time_stage(function() combo.update(DT) end, ITERS, WARMUP)

  -- Full-frame: everything the engine schedules per tick.
  stages["FULL_frame"] = time_stage(function()
    particles.update(DT)
    fire.update(DT)
    fire_wall.update(DT)
    renderer.render(build_all_lists())
    combo.update(DT)
  end, ITERS, WARMUP)

  return stages
end

-- ---- scenarios ------------------------------------------------------------

local PRESETS = { "explosion", "fountain", "rightburst", "shockwave",
                  "emoji", "stars", "disintegrate" }

local function spawn_n(n)
  for i = 1, n do
    particles.spawn(5 + (i % 20), 10 + (i % 50))
  end
end

local function drive_combo(level_target_streak)
  for _ = 1, level_target_streak do combo.increment() end
  fire_wall.spawn(combo.get_level(), combo.get_streak())
end

local scenarios = {}

local function add_scenario(id, overrides, setup_state)
  scenarios[#scenarios + 1] = { id = id, overrides = overrides, setup_state = setup_state }
end

-- baseline: all off
add_scenario("baseline",
  {
    auto_enable = true,
    combo     = { enabled = false, shake = false },
    shake     = { mode = "none" },
    fire_wall = { enabled = false },
    particles = { preset = "explosion", max_particles = 10, count = { 0, 0 }, pool_size = 10, cancel_on_new = false },
    engine    = { fps = 25, stop_delay = 60000 },
  },
  function() end)

-- per-preset particles (no combo, no fire_wall)
for _, preset in ipairs(PRESETS) do
  add_scenario("particles." .. preset,
    {
      auto_enable = true,
      combo     = { enabled = false, shake = false },
      shake     = { mode = "none" },
      fire_wall = { enabled = false },
      particles = { preset = preset, cancel_on_new = false },
      engine    = { fps = 25, stop_delay = 60000 },
    },
    function() spawn_n(60) end)
end

add_scenario("particles+combo",
  {
    auto_enable = true,
    combo     = { enabled = true, shake = false, timeout = 60000 },
    shake     = { mode = "none" },
    fire_wall = { enabled = false },
    particles = { preset = "explosion", cancel_on_new = false },
    engine    = { fps = 25, stop_delay = 60000 },
  },
  function() spawn_n(60); drive_combo(20) end)

add_scenario("particles+combo+fire_wall",
  {
    auto_enable = true,
    combo     = { enabled = true, shake = false, timeout = 60000 },
    shake     = { mode = "none" },
    fire_wall = { enabled = true, max_rows = 5 },
    particles = { preset = "explosion", cancel_on_new = false },
    engine    = { fps = 25, stop_delay = 60000 },
  },
  function() spawn_n(60); drive_combo(30) end)

add_scenario("fire_wall_only",
  {
    auto_enable = true,
    combo     = { enabled = true, shake = false, timeout = 60000 },
    shake     = { mode = "none" },
    fire_wall = { enabled = true, max_rows = 5 },
    particles = { preset = "explosion", max_particles = 10, count = { 0, 0 }, pool_size = 10 },
    engine    = { fps = 25, stop_delay = 60000 },
  },
  function() drive_combo(50) end)

add_scenario("renderer_stress",
  {
    auto_enable = true,
    combo     = { enabled = false, shake = false },
    shake     = { mode = "none" },
    fire_wall = { enabled = false },
    particles = {
      preset = "explosion", max_particles = 300, pool_size = 200,
      count = { 20, 30 }, cancel_on_new = false,
    },
    engine    = { fps = 25, stop_delay = 60000 },
  },
  function() spawn_n(280) end)

add_scenario("high_fps",
  {
    auto_enable = true,
    combo     = { enabled = true, shake = false, timeout = 60000 },
    shake     = { mode = "none" },
    fire_wall = { enabled = true, max_rows = 5 },
    particles = { preset = "explosion", cancel_on_new = false },
    engine    = { fps = 60, stop_delay = 60000 },
  },
  function() spawn_n(60); drive_combo(30) end)

add_scenario("large_editor",
  {
    auto_enable = true,
    combo     = { enabled = true, shake = false, timeout = 60000 },
    shake     = { mode = "none" },
    fire_wall = { enabled = true, max_rows = 5 },
    particles = { preset = "explosion", cancel_on_new = false },
    engine    = { fps = 25, stop_delay = 60000 },
  },
  function()
    vim.o.columns = 300
    vim.o.lines   = 80
    spawn_n(60); drive_combo(30)
  end)

add_scenario("small_editor",
  {
    auto_enable = true,
    combo     = { enabled = true, shake = false, timeout = 60000 },
    shake     = { mode = "none" },
    fire_wall = { enabled = true, max_rows = 5 },
    particles = { preset = "explosion", cancel_on_new = false },
    engine    = { fps = 25, stop_delay = 60000 },
  },
  function()
    vim.o.columns = 80
    vim.o.lines   = 24
    spawn_n(40); drive_combo(30)
  end)

-- ---- per-API primitive cost table -----------------------------------------

local function primitive_table()
  local PRIM_ITERS = 10000

  local buf = vim.api.nvim_create_buf(false, true)
  local ok, win = pcall(vim.api.nvim_open_win, buf, false, {
    relative = "editor", row = 5, col = 5, width = 1, height = 1,
    style = "minimal", focusable = false, noautocmd = true,
  })
  if not ok then return {} end

  local prims = {}
  prims["nvim_win_set_config"] = time_stage(function()
    pcall(vim.api.nvim_win_set_config, win, {
      relative = "editor", row = 6, col = 6, width = 1, height = 1,
    })
  end, PRIM_ITERS, 100)

  prims["nvim_win_set_option_winblend"] = time_stage(function()
    pcall(vim.api.nvim_win_set_option, win, "winblend", 50)
  end, PRIM_ITERS, 100)

  prims["nvim_win_set_option_winhighlight"] = time_stage(function()
    pcall(vim.api.nvim_win_set_option, win, "winhighlight", "Normal:PowerModeParticle1")
  end, PRIM_ITERS, 100)

  prims["nvim_buf_set_lines"] = time_stage(function()
    pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, { "x" })
  end, PRIM_ITERS, 100)

  prims["nvim_buf_add_highlight"] = time_stage(function()
    pcall(vim.api.nvim_buf_add_highlight, buf, -1, "PowerModeFire1", 0, 0, 1)
  end, PRIM_ITERS, 100)

  prims["vim_fn_strdisplaywidth"] = time_stage(function()
    vim.fn.strdisplaywidth("◆")
  end, PRIM_ITERS, 100)

  prims["vim_fn_screenpos"] = time_stage(function()
    local id = vim.fn.win_getid()
    vim.fn.screenpos(id, 1, 1)
  end, PRIM_ITERS, 100)

  pcall(vim.api.nvim_win_close, win, true)
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  return prims
end

-- ---- main -----------------------------------------------------------------

local function run_one(scenario)
  reset_plugin(scenario.overrides)
  local stages = measure_full_frame(scenario.setup_state)
  return {
    schema_version    = 1,
    tool              = "bench_hotspots.lua",
    git_sha           = git_sha(),
    timestamp         = iso_now(),
    machine           = machine(),
    scenario          = scenario.id,
    config_overrides  = scenario.overrides,
    iterations        = ITERS,
    warmup_iterations = WARMUP,
    stages            = stages,
    notes             = {},
  }
end

local results = { schema_version = 1, results = {}, primitives = {} }

for _, sc in ipairs(scenarios) do
  if (not ONLY_SCENARIO) or ONLY_SCENARIO == sc.id then
    io.stderr:write("[bench_hotspots] scenario: " .. sc.id .. "\n")
    table.insert(results.results, run_one(sc))
  end
end

io.stderr:write("[bench_hotspots] per-API primitive table (N=10000)\n")
results.primitives = {
  schema_version = 1,
  tool           = "bench_hotspots.lua/primitives",
  git_sha        = git_sha(),
  timestamp      = iso_now(),
  machine        = machine(),
  iterations     = 10000,
  stages         = primitive_table(),
}

local json = vim.json.encode(results)
if OUT_PATH and OUT_PATH ~= "" then
  local f = assert(io.open(OUT_PATH, "w"))
  f:write(json)
  f:close()
  io.stderr:write("[bench_hotspots] wrote " .. OUT_PATH .. "\n")
else
  io.write(json, "\n")
end

vim.cmd("qa!")
