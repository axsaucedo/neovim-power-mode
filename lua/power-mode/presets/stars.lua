--- Stars preset: twinkling stars scattered around cursor
--- Characters: ✦✧⋆✶✸✹✺⊹ (star symbols)
local utils = require("power-mode.utils")
local config = require("power-mode.config")

local M = {}
local active = {}

local default_chars = { "✦", "✧", "⋆", "✶", "✸", "✹", "✺", "⊹" }

function M.spawn(row, col)
  local cfg = config.get()
  local p = cfg.particles
  local max_p = p.max_particles
  local chars = p.chars or default_chars

  local count = utils.random_int(5, 10)
  for _ = 1, count do
    if #active >= max_p then break end
    local ox = utils.random(-5, 5)
    local oy = utils.random(-3, 3)
    active[#active + 1] = {
      x = col + ox, y = row + oy,
      vx = utils.random(-0.1, 0.1),
      vy = utils.random(-0.3, -0.1),
      char = utils.random_choice(chars),
      color_idx = utils.random_int(1, 8),
      lifetime = utils.random(200, 400),
      max_lifetime = 400,
      twinkle_phase = utils.random(0, 6.28),
      twinkle_speed = utils.random(8, 15),
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
    p.lifetime = p.lifetime - dt * 1000
    p.twinkle_phase = (p.twinkle_phase or 0) + (p.twinkle_speed or 10) * dt
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
