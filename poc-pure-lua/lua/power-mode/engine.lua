local particles = require("power-mode.particles")
local renderer = require("power-mode.renderer")
local combo = require("power-mode.combo")
local fire = require("power-mode.particles_fire")

local M = {}

local timer = nil
local last_time = nil
local FPS_INTERVAL = 40 -- ~25fps

function M.start()
  if timer then return end
  last_time = vim.loop.now()
  timer = vim.loop.new_timer()
  timer:start(0, FPS_INTERVAL, function()
    local now = vim.loop.now()
    local dt = (now - last_time) / 1000 -- seconds
    last_time = now

    vim.schedule(function()
      particles.update(dt)
      fire.update(dt)
      -- Merge both particle lists for rendering
      local all = {}
      for _, p in ipairs(particles.get_active()) do all[#all + 1] = p end
      for _, p in ipairs(fire.get_active()) do all[#all + 1] = p end
      renderer.render(all)
      combo.update(dt)
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
