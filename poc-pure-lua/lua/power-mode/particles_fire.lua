local utils = require("power-mode.utils")
local M = {}
local active = {}
local MAX_PARTICLES = 80

local chars = { "🔥", "▓", "▒", "░", "⚡", "✦", "•" }
local fire_colors = { 1, 5, 6 }  -- cyan(1), orange(5), gold(6) from highlights

function M.spawn(row, col)
  local count = utils.random_int(5, 9)
  for _ = 1, count do
    if #active >= MAX_PARTICLES then break end
    -- Fire spreads outward and slightly downward
    local angle = utils.random(-0.8, -2.35)  -- mostly upward but wider spread
    local speed = utils.random(3, 8)
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
  -- Add falling ember sparks
  for _ = 1, utils.random_int(2, 4) do
    if #active >= MAX_PARTICLES then break end
    active[#active + 1] = {
      x = col + utils.random(-1, 1),
      y = row,
      vx = utils.random(-1, 1),
      vy = utils.random(0.5, 2),  -- downward
      char = utils.random_choice({ "·", "•", "░" }),
      color_idx = utils.random_choice({ 5, 6 }),  -- orange, gold
      lifetime = utils.random(300, 600),
      max_lifetime = 600,
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
