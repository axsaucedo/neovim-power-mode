--- Animation engine for neovim-power-mode
--- Manages the render loop timer at configurable FPS
local config = require("power-mode.config")

local M = {}

local timer = nil
local last_time = nil

-- Modules injected at runtime to avoid circular requires
local particles_mod = nil
local fire_mod = nil
local renderer_mod = nil
local combo_mod = nil

function M.set_modules(p, f, r, c)
  particles_mod = p
  fire_mod = f
  renderer_mod = r
  combo_mod = c
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
      if particles_mod then particles_mod.update(dt) end
      if fire_mod then fire_mod.update(dt) end

      -- Merge both particle lists for rendering
      local all = {}
      if particles_mod then
        for _, p in ipairs(particles_mod.get_active()) do all[#all + 1] = p end
      end
      if fire_mod then
        for _, p in ipairs(fire_mod.get_active()) do all[#all + 1] = p end
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
