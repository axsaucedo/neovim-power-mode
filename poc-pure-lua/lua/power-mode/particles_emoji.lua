local utils = require("power-mode.utils")
local M = {}
local active = {}
local MAX_PARTICLES = 60

-- Emojis ONLY — unique to emoji mode (no single-width fallbacks)
local emojis = { "⭐", "🌟", "✨", "💫", "🔥", "💥", "🎆", "🎇" }

function M.spawn(row, col)
  -- Fewer particles since emojis are bigger; upward scatter with wide spread
  local count = utils.random_int(3, 5)
  for _ = 1, count do
    if #active >= MAX_PARTICLES then break end
    -- Angle: -150° to -30° = -2.62 to -0.52 (upward with wide scatter)
    local angle = utils.random(-2.62, -0.52)
    local speed = utils.random(3, 6)
    active[#active + 1] = {
      x = col,
      y = row,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed * 0.5,
      char = utils.random_choice(emojis),
      color_idx = utils.random_int(1, 8),
      lifetime = utils.random(400, 800),
      max_lifetime = 800,
      is_emoji = true,
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
    p.vy = p.vy + 0.12 * dt * 60
    p.vx = p.vx * 0.96
    p.vy = p.vy * 0.96
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
