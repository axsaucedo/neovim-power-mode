local utils = require("power-mode.utils")
local M = {}
local active = {}
local MAX_PARTICLES = 100

-- Arrow/chevron chars pointing right — unique to rightburst
local chars = { "→", "➜", "➤", "▸", "⊳", "›" }

function M.spawn(row, col)
  -- 80% rightward (-30° to +30°), 20% slight upward-right (-30° to -60°)
  local count = utils.random_int(5, 9)
  for _ = 1, count do
    if #active >= MAX_PARTICLES then break end
    local angle
    if math.random() < 0.8 then
      angle = utils.random(-0.52, 0.52)   -- -30° to +30° (rightward)
    else
      angle = utils.random(-1.05, -0.52)  -- -60° to -30° (upward-right)
    end
    local speed = utils.random(8, 15)
    active[#active + 1] = {
      x = col,
      y = row,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed * 0.5,
      char = utils.random_choice(chars),
      color_idx = utils.random_int(1, 8),
      lifetime = utils.random(350, 650),
      max_lifetime = 650,
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
    p.vy = p.vy + 0.03 * dt * 60  -- very low gravity — particles travel far right
    p.vx = p.vx * 0.98
    p.vy = p.vy * 0.98
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
