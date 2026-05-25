-- tests/perf/_summarise_tui.lua
--
-- Reads a JSONL produced by bench_tui_frame.lua plus a CPU CSV from
-- bench_tui.sh, and writes a schema_version=1 JSON result combining
-- per-stage hrtime statistics, reconstructed FULL_frame totals and a
-- CPU trace.
--
-- Driven by env vars set in bench_tui.sh; not intended to be invoked
-- directly.

local function env(k, default) return os.getenv(k) or default end

local IN_PATH  = assert(env("PM_INPUT"), "PM_INPUT not set")
local CPU_PATH = env("PM_CPU", "")
local OUT_PATH = assert(env("PM_OUT"), "PM_OUT not set")

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

local by_stage = {}
local frames = {}  -- list of accumulated ns between FRAME_MARK boundaries
local cur_frame_ns = 0
local frame_open = false

local f = assert(io.open(IN_PATH, "r"))
for line in f:lines() do
  local ok, obj = pcall(vim.json.decode, line)
  if ok and type(obj) == "table" then
    if obj.stage == "FRAME_MARK" then
      if frame_open and cur_frame_ns > 0 then
        frames[#frames + 1] = cur_frame_ns
      end
      cur_frame_ns = 0
      frame_open = true
    elseif obj.stage and obj.ns then
      by_stage[obj.stage] = by_stage[obj.stage] or {}
      table.insert(by_stage[obj.stage], obj.ns)
      cur_frame_ns = cur_frame_ns + obj.ns
    end
  end
end
f:close()
if frame_open and cur_frame_ns > 0 then frames[#frames + 1] = cur_frame_ns end

local stages = {}
for k, v in pairs(by_stage) do stages[k] = summarise_ns(v) end
if #frames > 0 then stages["FULL_frame_reconstructed"] = summarise_ns(frames) end

-- CPU trace
local cpu_samples = {}
local cpu_summary = nil
if CPU_PATH ~= "" then
  local cf = io.open(CPU_PATH, "r")
  if cf then
    for line in cf:lines() do
      local t_ns, pct = line:match("^(%d+),([%d%.]+)$")
      if t_ns and pct then
        cpu_samples[#cpu_samples + 1] = { t_ns = tonumber(t_ns), cpu_pct = tonumber(pct) }
      end
    end
    cf:close()
    if #cpu_samples > 0 then
      local pcts = {}
      for _, s in ipairs(cpu_samples) do pcts[#pcts + 1] = s.cpu_pct end
      table.sort(pcts)
      local sum = 0; for _,v in ipairs(pcts) do sum = sum + v end
      cpu_summary = {
        n        = #pcts,
        mean_pct = sum / #pcts,
        p50_pct  = pcts[math.ceil(#pcts * 0.50)],
        p95_pct  = pcts[math.ceil(#pcts * 0.95)],
        max_pct  = pcts[#pcts],
      }
    end
  end
end

local result = {
  schema_version    = 1,
  tool              = "bench_tui.sh + bench_tui_frame.lua",
  git_sha           = env("PM_SHA", "unknown"),
  timestamp         = env("PM_TS",  ""),
  machine = {
    os = env("PM_OS", ""), arch = env("PM_ARCH", ""), nvim = env("PM_NVIM", ""),
    tmux = (io.popen("tmux -V 2>./tmp/null"):read("*l") or "")
  },
  scenario          = env("PM_SID", "unknown"),
  config_overrides  = {
    fire_wall_enabled = env("PM_FW", "0") == "1",
    fps               = tonumber(env("PM_FPS", "25")),
    duration_s        = tonumber(env("PM_DUR", "0")),
  },
  iterations        = #frames,
  warmup_iterations = 0,
  stages            = stages,
  cpu_trace         = cpu_samples,
  cpu_summary       = cpu_summary,
  notes             = {
    "FULL_frame_reconstructed = sum of inner stage ns between FRAME_MARKs.",
    "CPU sampled via `ps -o %cpu=` at ~0.5s cadence; mean_pct is the steady-state cost.",
  },
}

local fo = assert(io.open(OUT_PATH, "w"))
fo:write(vim.json.encode(result))
fo:close()
io.stderr:write("[_summarise_tui] wrote " .. OUT_PATH .. "\n")
vim.cmd("qa!")
