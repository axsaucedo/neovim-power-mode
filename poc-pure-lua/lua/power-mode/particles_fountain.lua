local utils = require("power-mode.utils")
local M = {}
local active = {}
local MAX_PARTICLES = 100

-- Vertical line segments — unique to fountain (like water streams)
local chars = { "│", "╎", "┃", "╏", "╵" }

function M.spawn(row, col)
  -- Geyser: VERY narrow upward cone (±10° from straight up)
  local count = utils.random_int(5, 9)
  for _ = 1, count do
    if #active >= MAX_PARTICLES then break end
    -- -90° is straight up; ±10° = -80° to -100° = -1.40 to -1.74 radians
    local angle = utils.random(-1.74, -1.40)
    local speed = utils.random(8, 14)
    active[#active + 1] = {
      x = col,
      y = row,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed * 0.5,  -- squash for terminal aspect
      char = utils.random_choice(chars),
      color_idx = utils.random_int(1, 8),
      lifetime = utils.random(400, 700),
      max_lifetime = 700,
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
    -- Strong gravity pulls particles back down (fountain arc)
    p.vy = p.vy + 0.20 * dt * 60
    -- Light drag
    p.vx = p.vx * 0.97
    p.vy = p.vy * 0.97
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
