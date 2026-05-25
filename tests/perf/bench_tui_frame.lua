-- tests/perf/bench_tui_frame.lua
--
-- Used as the -u init for the TUI bench (driven by bench_tui.sh).
-- After pm.setup() runs, this script monkey-patches the .update and
-- .render functions of each engine subsystem to record per-stage
-- hrtime deltas to a JSONL file in ./tmp/. The engine module holds
-- references to the SAME module tables we patch here (Lua function
-- lookup via `t.k` is dynamic), so the engine's scheduled body picks
-- up the wrappers without modifying any plugin source.
--
-- The bench driver (bench_tui.sh) feeds typing via `tmux send-keys`,
-- then quits Neovim cleanly; VimLeavePre flushes a sentinel and the
-- post-processor in bench_tui.sh summarises the JSONL into the
-- standard schema_version=1 JSON result.
--
-- Env vars (set by bench_tui.sh):
--   PM_PERF_SCENARIO   Scenario id, used in the output filename.
--   PM_PERF_OUT        Absolute path to JSONL output file.
--   PM_PERF_FPS        FPS override (default: 25).
--   PM_PERF_FIRE_WALL  "1" to enable fire_wall.

vim.opt.rtp:prepend(".")
vim.cmd("runtime plugin/power-mode.lua")

local SCENARIO = os.getenv("PM_PERF_SCENARIO") or "default"
local OUT      = os.getenv("PM_PERF_OUT")      or ("./tmp/pm_tui_" .. SCENARIO .. ".jsonl")
local FPS      = tonumber(os.getenv("PM_PERF_FPS")) or 25
local FW       = os.getenv("PM_PERF_FIRE_WALL") == "1"

-- Open the JSONL output. We append one record per stage call. Buffered
-- writes are flushed by close on VimLeavePre.
local fh = io.open(OUT, "w")
assert(fh, "could not open " .. OUT)
fh:write(string.format(
  '{"event":"start","scenario":"%s","fps":%d,"fire_wall":%s}\n',
  SCENARIO, FPS, tostring(FW)))

local function write_record(stage, ns)
  fh:write(string.format('{"stage":"%s","ns":%d}\n', stage, ns))
end

local function wrap(tbl, key, stage)
  local orig = tbl[key]
  if type(orig) ~= "function" then return end
  tbl[key] = function(...)
    local t0 = vim.loop.hrtime()
    local a, b, c = orig(...)
    write_record(stage, vim.loop.hrtime() - t0)
    return a, b, c
  end
end

-- Configure the plugin. Disable shake (terminal escape spam is noisy on
-- macOS Terminal/Ghostty under tmux and isn't part of the engine cost).
require("power-mode").setup({
  auto_enable = true,
  combo     = { enabled = true, shake = false, timeout = 60000 },
  shake     = { mode = "none" },
  fire_wall = { enabled = FW, max_rows = 5 },
  particles = { preset = "explosion" },
  engine    = { fps = FPS, stop_delay = 60000 },
})

-- Monkey-patch AFTER setup so engine.set_modules has already injected
-- the real references; the engine's locals point to the same tables.
wrap(require("power-mode.particles"),     "update", "particles.update")
wrap(require("power-mode.presets.fire"),  "update", "fire.update")
wrap(require("power-mode.fire_wall"),     "update", "fire_wall.update")
wrap(require("power-mode.renderer"),      "render", "renderer.render")
wrap(require("power-mode.combo"),         "update", "combo.update")

-- Also wrap the engine's scheduled body to measure FULL_frame. The
-- engine creates its closure at start-time and calls vim.schedule with
-- a wrapper of its own; we can't reach inside that closure. Instead,
-- approximate FULL_frame by recording timestamps around the longest
-- stage: emit a "frame_marker" record per particles.update entry.
-- The post-processor reconstructs frame totals by summing the inner
-- stages between consecutive frame_markers.
do
  local particles = require("power-mode.particles")
  local orig = particles.update
  particles.update = function(...)
    fh:write('{"stage":"FRAME_MARK","ns":0}\n')
    return orig(...)
  end
end

-- Open a scratch buffer to receive keystrokes.
vim.cmd("enew")
vim.bo.buftype = "nofile"
vim.bo.bufhidden = "hide"
vim.bo.swapfile = false
vim.cmd("startinsert")

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    fh:write('{"event":"end"}\n')
    fh:close()
  end,
})
