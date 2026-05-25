--- Animation engine for neovim-power-mode
--- Manages the render loop timer at configurable FPS
local config = require("power-mode.config")

local M = {}

local timer = nil
local last_time = nil

-- Modules injected at runtime to avoid circular requires
local particles_mod = nil
local fire_mod = nil
local fire_wall_mod = nil
local renderer_mod = nil
local combo_mod = nil

-- Module-level scratch table reused every tick to hold the merged
-- particle list. Avoids allocating a fresh table 25-60 times per second
-- which dominated retained-memory growth in the perf eval suite
-- (REPORT.md R4 / IMPROVEMENTS.md O4). The table is only live between
-- the merge loop and the renderer.render call on the same scheduled
-- frame, so reuse is safe.
local scratch_all = {}

-- Portable LuaJIT-safe table clear: nil out from the tail. We can't
-- rely on `table.clear` (LuaJIT-only, missing on some embedded LuaJIT
-- forks) so we use the explicit loop everywhere.
local function clear_array(t)
  for i = #t, 1, -1 do t[i] = nil end
end

function M.set_modules(p, f, r, c, fw)
  particles_mod = p
  fire_mod = f
  renderer_mod = r
  combo_mod = c
  fire_wall_mod = fw
end

function M.start()
  if timer then return end
  local cfg = config.get()
  local interval = math.floor(1000 / cfg.engine.fps)

  last_time = vim.loop.now()
  timer = vim.loop.new_timer()
  timer:start(0, interval, function()
    local now = vim.loop.now()
    local dt = (now - last_time) / 1000
    last_time = now

    vim.schedule(function()
      -- Idle fast-path: when every subsystem reports nothing to do this
      -- tick we skip all .update() calls, the merge loop and the
      -- renderer.render() call. This keeps wakeups cheap when the user
      -- is not typing — measurements showed idle CPU sitting at ~4 % on
      -- a 25 fps tick because the body always ran. See REPORT.md R3 /
      -- IMPROVEMENTS.md O2.
      local p_idle = (not particles_mod) or particles_mod.is_idle()
      local f_idle = (not fire_mod) or fire_mod.is_idle()
      local fw_idle = (not fire_wall_mod) or fire_wall_mod.is_idle()
      local c_idle = (not combo_mod) or combo_mod.is_idle()
      if p_idle and f_idle and fw_idle and c_idle then return end

      if particles_mod then particles_mod.update(dt) end
      if fire_mod then fire_mod.update(dt) end
      if fire_wall_mod then fire_wall_mod.update(dt) end

      -- Merge particle lists for rendering (fire wall manages its own window)
      clear_array(scratch_all)
      local all = scratch_all
      if particles_mod then
        for _, p in ipairs(particles_mod.get_active()) do all[#all + 1] = p end
      end
      if fire_mod then
        for _, p in ipairs(fire_mod.get_active()) do all[#all + 1] = p end
      end
      if fire_wall_mod then
        for _, p in ipairs(fire_wall_mod.get_active()) do all[#all + 1] = p end
      end

      if renderer_mod then renderer_mod.render(all) end
      if combo_mod then combo_mod.update(dt) end
    end)
  end)
end

function M.stop()
  if timer then
    pcall(function()
      timer:stop()
      timer:close()
    end)
    timer = nil
  end
  last_time = nil
end

function M.is_running()
  return timer ~= nil
end

return M
