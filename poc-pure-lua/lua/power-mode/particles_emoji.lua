local utils = require("power-mode.utils")
local M = {}
local active = {}
local MAX_PARTICLES = 60

-- Star/sparkle emojis — these are wider (2 cells) in most terminals
local emojis = { "⭐", "🌟", "✨", "💫", "🔥", "⚡", "💥", "🎆" }
-- Fallback single-width chars mixed in
local singles = { "★", "✦", "✧", "◆", "◈" }

function M.spawn(row, col)
  -- Mix of emojis and single-width chars
  local count = utils.random_int(4, 7)
  for _ = 1, count do
    if #active >= MAX_PARTICLES then break end
    -- Upward burst with slight right bias
    local angle = utils.random(-2.4, -0.5)
    local speed = utils.random(4, 9)
    local use_emoji = math.random() > 0.4
    active[#active + 1] = {
      x = col,
      y = row,
      vx = math.cos(angle) * speed + 0.5,  -- slight rightward nudge
      vy = math.sin(angle) * speed * 0.5,
      char = use_emoji and utils.random_choice(emojis) or utils.random_choice(singles),
      color_idx = utils.random_int(1, 8),
      lifetime = utils.random(350, 700),
      max_lifetime = 700,
      is_emoji = use_emoji,
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
    p.vy = p.vy + 0.12 * dt * 60
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
