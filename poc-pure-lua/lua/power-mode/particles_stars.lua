local utils = require("power-mode.utils")
local M = {}
local active = {}
local MAX_PARTICLES = 80

local star_chars = { "✦", "✧", "⋆", "✶", "✸", "✹", "✺", "⊹" }

function M.spawn(row, col)
  local count = utils.random_int(5, 10)
  for _ = 1, count do
    if #active >= MAX_PARTICLES then break end
    -- Stars appear scattered around cursor (±4 cols, ±2 rows)
    local ox = utils.random(-4, 4)
    local oy = utils.random(-2, 2)
    active[#active + 1] = {
      x = col + ox,
      y = row + oy,
      vx = utils.random(-0.3, 0.3),  -- almost stationary, gentle drift
      vy = utils.random(-0.5, -0.1),  -- very slow upward float
      char = utils.random_choice(star_chars),
      color_idx = utils.random_int(1, 8),
      lifetime = utils.random(300, 600),
      max_lifetime = 600,
      twinkle_phase = utils.random(0, 6.28),  -- random start phase
      twinkle_speed = utils.random(8, 15),  -- flicker speed
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
    p.lifetime = p.lifetime - dt * 1000
    -- Twinkle: modulate effective lifetime for winblend flicker
    p.twinkle_phase = p.twinkle_phase + p.twinkle_speed * dt
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
