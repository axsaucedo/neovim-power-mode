--- Fountain preset: narrow upward geyser
--- Characters: │╎┃╏╵ (vertical line segments)
local utils = require("power-mode.utils")
local config = require("power-mode.config")

local M = {}
local active = {}

local default_chars = { "│", "╎", "┃", "╏", "╵" }

function M.spawn(row, col)
  local cfg = config.get()
  local p = cfg.particles
  local max_p = p.max_particles
  local chars = p.chars or default_chars

  local count = utils.random_int(p.count[1], p.count[2])
  for _ = 1, count do
    if #active >= max_p then break end
    -- Narrow upward cone: -90° ±10° = -1.74 to -1.40 radians
    local angle = utils.random(-1.74, -1.40)
    local speed = utils.random(8, 14)
    active[#active + 1] = {
      x = col, y = row,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed * 0.5,
      char = utils.random_choice(chars),
      color_idx = utils.random_int(1, 8),
      lifetime = utils.random(400, 700),
      max_lifetime = 700,
    }
  end
end

function M.update(dt)
  local dims = utils.get_editor_dimensions()
  local i = 1
  while i <= #active do
    local p = active[i]
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    -- Strong gravity for fountain arc
    p.vy = p.vy + 0.20 * dt * 60
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
