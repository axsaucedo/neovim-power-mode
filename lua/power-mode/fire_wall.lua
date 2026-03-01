--- Fire wall module for neovim-power-mode (cacafire-inspired)
--- Renders rising fire/ember particles from the bottom of the editor
--- Four modes: none | ember_rise | fire_columns | inferno
--- Intensity scales with combo level
local config = require("power-mode.config")
local utils = require("power-mode.utils")

local M = {}
local active = {}

-- Character sets per mode
local chars_ember = { "·", "•", "░", "▒", "*" }
local chars_fire = { "█", "▓", "▒", "░", "▲", "^", "🔥" }
local chars_inferno = { "🔥", "█", "▓", "▒", "░", "▲", "^", "*", "✦" }

-- Mode-specific spawn parameters: { base_count, count_per_level, base_height, height_per_level, speed_range, lifetime_range }
local mode_params = {
  ember_rise = {
    base_count = 2,
    count_per_level = 1,
    speed = { 1, 3 },
    lifetime = { 400, 800 },
    chars = chars_ember,
  },
  fire_columns = {
    base_count = 5,
    count_per_level = 4,
    speed = { 2, 5 },
    lifetime = { 250, 600 },
    chars = chars_fire,
  },
  inferno = {
    base_count = 8,
    count_per_level = 6,
    speed = { 3, 7 },
    lifetime = { 200, 500 },
    chars = chars_inferno,
  },
}

function M.spawn(combo_level)
  local cfg = config.get()
  local fw = cfg.fire_wall
  if fw.mode == "none" then return end

  local params = mode_params[fw.mode]
  if not params then return end

  local dims = utils.get_editor_dimensions()
  local max_particles = cfg.particles.max_particles
  local level = math.min(combo_level or 0, 4)

  -- Scale count with combo level
  local count = params.base_count + level * params.count_per_level
  -- Scale max height with combo level
  local height = fw.base_height + math.floor(level / 4 * (fw.max_height - fw.base_height))

  local colors = fw.colors
  if not colors or #colors == 0 then
    colors = { 5, 6, 1 }
  end

  for _ = 1, count do
    if #active >= max_particles then break end

    -- Spawn along the bottom edge at random x positions
    local spawn_x = utils.random(0, dims.width - 1)
    local spawn_y = dims.height - 1

    -- Upward velocity with slight horizontal drift
    local speed = utils.random(params.speed[1], params.speed[2])
    local vx = utils.random(-0.5, 0.5)
    local vy = -speed  -- negative = upward

    active[#active + 1] = {
      x = spawn_x,
      y = spawn_y,
      vx = vx,
      vy = vy,
      char = utils.random_choice(params.chars),
      color_idx = utils.random_choice(colors),
      lifetime = utils.random(params.lifetime[1], params.lifetime[2]),
      max_lifetime = params.lifetime[2],
      max_rise = height,  -- how many rows above bottom it can reach
    }
  end
end

function M.update(dt)
  local dims = utils.get_editor_dimensions()
  local bottom = dims.height - 1
  local i = 1
  while i <= #active do
    local p = active[i]
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    p.vx = p.vx * 0.98  -- slight horizontal drag
    p.lifetime = p.lifetime - dt * 1000

    -- Remove if: expired, out of bounds, or risen too high
    local rows_risen = bottom - p.y
    if p.lifetime <= 0
      or p.x < 0 or p.x >= dims.width
      or p.y < 0 or p.y >= dims.height
      or rows_risen > p.max_rise then
      active[i] = active[#active]
      active[#active] = nil
    else
      i = i + 1
    end
  end
end

function M.get_active()
  return active
end

function M.clear()
  active = {}
end

function M.set_mode(mode)
  if mode ~= "none" and not mode_params[mode] then
    vim.notify("[power-mode] Unknown fire wall mode: " .. tostring(mode), vim.log.levels.ERROR)
    return
  end
  local cfg = config.get()
  cfg.fire_wall.mode = mode
  M.clear()
  vim.notify("⚡ Fire wall mode: " .. mode, vim.log.levels.INFO)
end

function M.get_mode()
  local cfg = config.get()
  return cfg.fire_wall.mode
end

return M
