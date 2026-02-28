local utils = require("power-mode.utils")

local M = {}

local active = {}
local MAX_PARTICLES = 100

local chars = { "✦", "✧", "⬥", "•", "·", "★", "⚡", "◆", "△" }

function M.spawn(row, col)
  local count = utils.random_int(3, 8)
  for _ = 1, count do
    if #active >= MAX_PARTICLES then break end
    local lifetime = utils.random(400, 800)
    active[#active + 1] = {
      x = col,
      y = row,
      vx = utils.random(-3, 3),
      vy = utils.random(-4, 1),
      char = utils.random_choice(chars),
      color_idx = utils.random_int(1, 8),
      lifetime = lifetime,
      max_lifetime = lifetime,
    }
  end
end

function M.update(dt)
  local i = 1
  local dims = utils.get_editor_dimensions()
  while i <= #active do
    local p = active[i]
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    p.vy = p.vy + 0.15 * dt * 60
    p.vx = p.vx * 0.95
    p.vy = p.vy * 0.95
    p.lifetime = p.lifetime - dt * 1000

    if p.lifetime <= 0 or p.x < 0 or p.x >= dims.width or p.y < 0 or p.y >= dims.height then
      active[i] = active[#active]
      active[#active] = nil
    else
      i = i + 1
    end
  end
end

function M.get_active()
  return active
end

function M.clear()
  active = {}
end

return M
