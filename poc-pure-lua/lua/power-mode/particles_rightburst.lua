local utils = require("power-mode.utils")
local M = {}
local active = {}
local MAX_PARTICLES = 100

local chars_fast = { "✦", "⚡", "★", "✧", "◈", "⬦" }
local chars_slow = { "·", "•", "∘", "○" }

function M.spawn(row, col)
  -- Fast sparks: upward-right bias (angle -10° to -80° from horizontal = mostly up-right)
  local fast_count = utils.random_int(4, 8)
  for _ = 1, fast_count do
    if #active >= MAX_PARTICLES then break end
    -- Angles in radians: -0.17 to -1.40 (roughly -10° to -80°, biased up-right)
    local angle = utils.random(-1.40, -0.17)
    local speed = utils.random(5, 11)
    active[#active + 1] = {
      x = col,
      y = row,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed * 0.5,
      char = utils.random_choice(chars_fast),
      color_idx = utils.random_int(1, 8),
      lifetime = utils.random(250, 550),
      max_lifetime = 550,
    }
  end
  -- Slow trailing dots: same direction but slower
  local slow_count = utils.random_int(2, 4)
  for _ = 1, slow_count do
    if #active >= MAX_PARTICLES then break end
    local angle = utils.random(-1.2, -0.1)
    local speed = utils.random(1.5, 4)
    active[#active + 1] = {
      x = col,
      y = row,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed * 0.5,
      char = utils.random_choice(chars_slow),
      color_idx = utils.random_int(1, 8),
      lifetime = utils.random(350, 700),
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
    p.vy = p.vy + 0.10 * dt * 60  -- light gravity
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
