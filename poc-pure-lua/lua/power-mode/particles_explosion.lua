local utils = require("power-mode.utils")
local M = {}
local active = {}
local MAX_PARTICLES = 100

local chars_fast = { "✦", "⚡", "★", "✧", "◈" }
local chars_slow = { "◆", "●", "⬥", "◇", "○" }

function M.spawn(row, col)
  -- Fast sparks: strong upward bias, radial spread
  local fast_count = utils.random_int(6, 10)
  for _ = 1, fast_count do
    if #active >= MAX_PARTICLES then break end
    -- Angle: -130° to -50° (mostly upward, wide radial spread)
    local angle = utils.random(-2.27, -0.87)
    local speed = utils.random(6, 12)
    active[#active + 1] = {
      x = col,
      y = row,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed * 0.5,
      char = utils.random_choice(chars_fast),
      color_idx = utils.random_int(1, 8),
      lifetime = utils.random(250, 500),
      max_lifetime = 500,
    }
  end

  -- Slow embers: wider spread, slower, longer lasting
  local slow_count = utils.random_int(3, 5)
  for _ = 1, slow_count do
    if #active >= MAX_PARTICLES then break end
    -- Angle: -150° to -30° (very wide spread)
    local angle = utils.random(-2.62, -0.52)
    local speed = utils.random(2, 5)
    active[#active + 1] = {
      x = col,
      y = row,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed * 0.5,
      char = utils.random_choice(chars_slow),
      color_idx = utils.random_int(1, 8),
      lifetime = utils.random(400, 800),
      max_lifetime = 800,
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
    -- Gravity pulls particles into an arc after the initial burst
    p.vy = p.vy + 0.15 * dt * 60
    -- Light drag
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
