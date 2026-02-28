local utils = require("power-mode.utils")
local M = {}
local active = {}
local MAX_PARTICLES = 80

-- Fire emoji + block fade — unique to fire (backspace effect)
local chars = { "🔥", "▓", "▒", "░", "•", "·" }
local fire_colors = { 5, 6 }  -- only orange(5) and gold(6)

function M.spawn(row, col)
  -- DOWNWARD: embers falling from where text was deleted
  local count = utils.random_int(5, 9)
  for _ = 1, count do
    if #active >= MAX_PARTICLES then break end
    -- Angle: +30° to +150° (below horizontal) = 0.52 to 2.62 radians
    local angle = utils.random(0.52, 2.62)
    local speed = utils.random(3, 6)
    active[#active + 1] = {
      x = col,
      y = row,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed * 0.4,
      char = utils.random_choice(chars),
      color_idx = utils.random_choice(fire_colors),
      lifetime = utils.random(200, 500),
      max_lifetime = 500,
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
    p.vy = p.vy + 0.08 * dt * 60  -- gentle gravity
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

function M.get_active() return active end
function M.clear() active = {} end
return M
