local particles = require("power-mode.particles")
local renderer = require("power-mode.renderer")
local combo = require("power-mode.combo")

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
      renderer.render(particles.get_active())
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
