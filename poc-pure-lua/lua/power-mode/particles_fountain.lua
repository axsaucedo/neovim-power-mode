local utils = require("power-mode.utils")
local M = {}
local active = {}
local MAX_PARTICLES = 100

local chars_fast = { "✦", "⚡", "★", "✧" }  -- fast sparks
local chars_slow = { "◆", "●", "⬥", "△" }  -- slower embers

function M.spawn(row, col)
  -- Fast sparks: narrow cone UPWARD (±30 degrees from vertical)
  local fast_count = utils.random_int(4, 7)
  for _ = 1, fast_count do
    if #active >= MAX_PARTICLES then break end
    -- Angle: -90° is straight up, ±30° cone = -60° to -120°
    local angle = utils.random(-2.09, -1.05)  -- -120° to -60° in radians
    local speed = utils.random(5, 9)
    active[#active + 1] = {
      x = col,
      y = row,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed * 0.5,  -- squash for terminal aspect
      char = utils.random_choice(chars_fast),
      color_idx = utils.random_int(1, 8),
      lifetime = utils.random(300, 600),
      max_lifetime = 600,
    }
  end

  -- Slower embers: wider spread, slower, longer lasting
  local slow_count = utils.random_int(2, 4)
  for _ = 1, slow_count do
    if #active >= MAX_PARTICLES then break end
    local angle = utils.random(-2.4, -0.7)  -- wider cone
    local speed = utils.random(1.5, 3.5)
    active[#active + 1] = {
      x = col,
      y = row,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed * 0.5,
      char = utils.random_choice(chars_slow),
      color_idx = utils.random_int(1, 8),
      lifetime = utils.random(500, 900),
      max_lifetime = 900,
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
    -- Gravity pulls particles back down (fountain arc)
    p.vy = p.vy + 0.12 * dt * 60
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
