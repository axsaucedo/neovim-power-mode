--- Shockwave preset: expanding ring of block characters
--- Characters: ░▒▓█ (block gradient, cycles as ring ages)
local utils = require("power-mode.utils")
local config = require("power-mode.config")

local M = {}
local active = {}

local default_chars = { "░", "▒", "▓", "█" }

function M.spawn(row, col)
  local cfg = config.get()
  local max_p = cfg.particles.max_particles

  -- Ring of 12-16 particles expanding outward
  local count = utils.random_int(12, 16)
  local speed = utils.random(2.5, 5.0)
  for i = 1, count do
    if #active >= max_p then break end
    local angle = (i / count) * 2 * math.pi + utils.random(-0.2, 0.2)
    active[#active + 1] = {
      x = col, y = row,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed * 0.5,
      char = default_chars[1],
      char_idx = 1,
      color_idx = utils.random_int(1, 8),
      lifetime = utils.random(250, 400),
      max_lifetime = 400,
    }
  end
end

function M.update(dt)
  local dims = utils.get_editor_dimensions()
  local chars = default_chars
  local i = 1
  while i <= #active do
    local p = active[i]
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    p.vx = p.vx * 0.98
    p.vy = p.vy * 0.98
    p.lifetime = p.lifetime - dt * 1000
    -- Cycle chars: heavy → light as particle ages
    local age_ratio = 1 - (p.lifetime / p.max_lifetime)
    p.char_idx = math.min(#chars, math.floor(age_ratio * #chars) + 1)
    p.char = chars[p.char_idx]
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
