--- Fire preset: downward embers for backspace/delete
--- Characters: 🔥▓▒░•· (fire emoji + block fade)
local utils = require("power-mode.utils")
local config = require("power-mode.config")

local M = {}
local active = {}

local default_chars = { "🔥", "▓", "▒", "░", "•", "·" }

function M.spawn(row, col)
  local cfg = config.get()
  local bs = cfg.backspace
  local max_p = cfg.particles.max_particles
  local chars = bs.chars or default_chars
  local colors = bs.colors

  local count = utils.random_int(5, 9)
  for _ = 1, count do
    if #active >= max_p then break end
    -- Downward: +30° to +150° (below horizontal)
    local angle = utils.random(0.52, 2.62)
    local speed = utils.random(3, 6)
    active[#active + 1] = {
      x = col, y = row,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed * 0.4,
      char = utils.random_choice(chars),
      color_idx = utils.random_choice(colors),
      lifetime = utils.random(200, 500),
      max_lifetime = 500,
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
    p.vy = p.vy + 0.08 * dt * 60
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
