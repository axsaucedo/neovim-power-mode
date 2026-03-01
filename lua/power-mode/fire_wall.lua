--- Fire wall module for neovim-power-mode (cacafire heat-buffer algorithm)
--- Classic 2D heat buffer: seed bottom → propagate upward with cooling → render
--- Four modes: none | ember_rise | fire_columns | inferno
--- Intensity scales with combo level
local config = require("power-mode.config")
local utils = require("power-mode.utils")

local M = {}

-- Heat buffer: grid[y][x] = heat value 0-255
local grid = {}
local grid_w = 0
local grid_h = 0

-- Active particles for the renderer (rebuilt each frame from heat buffer)
local active = {}

-- Heat-to-character mapping (hottest → coldest)
local heat_chars = {
  { threshold = 200, char = "█" },
  { threshold = 150, char = "▓" },
  { threshold = 100, char = "▒" },
  { threshold = 50,  char = "░" },
  { threshold = 15,  char = "·" },
}

-- Heat-to-color mapping (hottest → coldest)
-- Uses config color indices: 5=orange, 6=gold, 1=cyan, 4=green
local heat_colors = {
  { threshold = 200, color = 5 },  -- orange (hottest)
  { threshold = 150, color = 6 },  -- gold
  { threshold = 80,  color = 1 },  -- cyan
  { threshold = 30,  color = 4 },  -- green (coolest visible)
}

-- Mode parameters: base_heat, heat_per_level, cooling, seed_density
local mode_params = {
  ember_rise = {
    base_heat = 80,
    heat_per_level = 30,
    cooling = 12,
    seed_density = 0.3,   -- fraction of bottom row seeded
    max_height_frac = 0.15, -- fraction of editor height
  },
  fire_columns = {
    base_heat = 160,
    heat_per_level = 20,
    cooling = 6,
    seed_density = 0.7,
    max_height_frac = 0.25,
  },
  inferno = {
    base_heat = 220,
    heat_per_level = 8,
    cooling = 3,
    seed_density = 0.9,
    max_height_frac = 0.4,
  },
}

local function ensure_grid(w, h)
  if w == grid_w and h == grid_h then return end
  grid_w = w
  grid_h = h
  grid = {}
  for y = 1, h do
    grid[y] = {}
    for x = 1, w do
      grid[y][x] = 0
    end
  end
end

local function heat_to_char(heat)
  for _, entry in ipairs(heat_chars) do
    if heat >= entry.threshold then return entry.char end
  end
  return nil  -- too cold to render
end

local function heat_to_color(heat)
  for _, entry in ipairs(heat_colors) do
    if heat >= entry.threshold then return entry.color end
  end
  return 4
end

--- Seed the bottom row with random heat and cold spots
function M.seed_bottom(combo_level)
  local cfg = config.get()
  local fw = cfg.fire_wall
  if fw.mode == "none" then return end

  local params = mode_params[fw.mode]
  if not params then return end

  local level = math.min(combo_level or 0, 4)
  local max_heat = math.min(255, params.base_heat + level * params.heat_per_level)

  local dims = utils.get_editor_dimensions()
  local w = dims.width
  local fire_h = math.max(3, math.floor(dims.height * params.max_height_frac))
  ensure_grid(w, fire_h)

  -- Seed bottom row
  for x = 1, grid_w do
    if math.random() < params.seed_density then
      grid[grid_h][x] = utils.random_int(math.floor(max_heat * 0.6), max_heat)
    else
      grid[grid_h][x] = utils.random_int(0, math.floor(max_heat * 0.2))
    end
  end
end

--- Propagate heat upward with cooling (called each frame by engine)
function M.update(_dt)
  local cfg = config.get()
  local fw = cfg.fire_wall
  if fw.mode == "none" then
    active = {}
    return
  end

  local params = mode_params[fw.mode]
  if not params or grid_h == 0 then
    active = {}
    return
  end

  -- Propagate: each cell averages 3 below + random cooling
  for y = 1, grid_h - 1 do
    for x = 1, grid_w do
      local below = grid[y + 1][x]
      local left = grid[y + 1][math.max(1, x - 1)]
      local right = grid[y + 1][math.min(grid_w, x + 1)]
      local avg = (below + left + right) / 3
      local cool = utils.random_int(0, params.cooling)
      grid[y][x] = math.max(0, math.floor(avg - cool))
    end
  end

  -- Cool the bottom row slightly to create flicker
  for x = 1, grid_w do
    local cool = utils.random_int(0, math.floor(params.cooling * 0.5))
    grid[grid_h][x] = math.max(0, grid[grid_h][x] - cool)
  end

  -- Build particle list from heat buffer for the renderer
  active = {}
  local dims = utils.get_editor_dimensions()
  local editor_h = dims.height
  local max_p = cfg.particles.max_particles

  -- Render fire starting from the bottom of the editor
  for y = 1, grid_h do
    for x = 1, grid_w do
      if #active >= max_p then break end
      local heat = grid[y][x]
      local ch = heat_to_char(heat)
      if ch then
        -- Map grid position to editor position (bottom-aligned)
        local editor_y = editor_h - grid_h + y - 1
        if editor_y >= 0 and editor_y < editor_h then
          active[#active + 1] = {
            x = x - 1,
            y = editor_y,
            char = ch,
            color_idx = heat_to_color(heat),
            lifetime = heat,  -- used for blend calculation
            max_lifetime = 255,
          }
        end
      end
    end
    if #active >= max_p then break end
  end
end

-- Alias spawn → seed_bottom for engine integration
function M.spawn(combo_level)
  M.seed_bottom(combo_level)
end

function M.get_active()
  return active
end

function M.clear()
  active = {}
  grid = {}
  grid_w = 0
  grid_h = 0
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
