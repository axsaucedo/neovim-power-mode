--- Explosion preset: radial burst with upward bias
--- Characters: ◆◇▲▼◈ (diamond/triangle geometric shapes)
local utils = require("power-mode.utils")
local config = require("power-mode.config")

local M = {}
local active = {}

local default_chars_fast = { "◆", "▲", "◈" }
local default_chars_slow = { "◇", "▼" }

function M.spawn(row, col)
  local cfg = config.get()
  local p = cfg.particles
  local max_p = p.max_particles
  local chars = p.chars

  -- Fast sparks: radial burst with upward bias
  local count = utils.random_int(p.count[1], p.count[2])
  for _ = 1, count do
    if #active >= max_p then break end
    local angle
    if math.random() < p.upward_bias then
      angle = utils.random(p.spread[1], p.spread[2])
    else
      angle = utils.random(-math.pi, math.pi)
    end
    local speed = utils.random(p.speed[1], p.speed[2])
    local c = chars and utils.random_choice(chars) or utils.random_choice(default_chars_fast)
    active[#active + 1] = {
      x = col, y = row,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed * 0.5,
      char = c,
      color_idx = utils.random_int(1, 8),
      lifetime = utils.random(p.lifetime[1], math.min(p.lifetime[2], 350)),
      max_lifetime = 350,
    }
  end

  -- Slow embers
  local slow_count = utils.random_int(3, 5)
  for _ = 1, slow_count do
    if #active >= max_p then break end
    local angle = utils.random(-math.pi, math.pi)
    local speed = utils.random(3, 6)
    local c = chars and utils.random_choice(chars) or utils.random_choice(default_chars_slow)
    active[#active + 1] = {
      x = col, y = row,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed * 0.5,
      char = c,
      color_idx = utils.random_int(1, 8),
      lifetime = utils.random(300, 450),
      max_lifetime = 450,
    }
  end
end

function M.update(dt)
  local cfg = config.get()
  local p = cfg.particles
  local dims = utils.get_editor_dimensions()
  local i = 1
  while i <= #active do
    local pt = active[i]
    pt.x = pt.x + pt.vx * dt
    pt.y = pt.y + pt.vy * dt
    pt.vy = pt.vy + p.gravity * dt * 60
    pt.vx = pt.vx * p.drag
    pt.vy = pt.vy * p.drag
    pt.lifetime = pt.lifetime - dt * 1000
    if pt.lifetime <= 0 or pt.x < 0 or pt.x >= dims.width or pt.y < 0 or pt.y >= dims.height then
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
