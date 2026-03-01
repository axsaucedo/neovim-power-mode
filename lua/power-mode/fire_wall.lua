--- Fire wall module for neovim-power-mode (cacafire heat-buffer algorithm)
--- Self-managed floating window at the bottom of the editor.
--- Classic 2D heat buffer: continuously seed bottom → propagate upward with cooling → render
--- Four modes: none | ember_rise | fire_columns | inferno
--- Intensity scales with combo level
local config = require("power-mode.config")
local utils = require("power-mode.utils")

local M = {}

-- Heat buffer: grid[y][x] = heat value 0-255
local grid = {}
local grid_w = 0
local grid_h = 0

-- Self-managed floating window
local fire_win = nil
local fire_buf = nil

-- Current combo level (set by spawn, used by update for continuous seeding)
local current_combo_level = 0

-- Whether fire wall is active (mode ~= none and has been initialized)
local is_active = false

-- Fire highlight namespace
local fire_ns = vim.api.nvim_create_namespace("power_mode_fire")

-- Heat-to-character mapping (hottest → coldest)
local heat_chars = {
  { threshold = 220, char = "█" },
  { threshold = 170, char = "▓" },
  { threshold = 120, char = "▒" },
  { threshold = 70,  char = "░" },
  { threshold = 25,  char = "·" },
}

-- Fire highlight groups (created in init, warm fire palette)
-- These are separate from the particle highlights to get proper fire colors
local fire_hl_groups = {
  { name = "PowerModeFire1", threshold = 220, fg = "#FF2200", ctermfg = 196 },  -- bright red (hottest)
  { name = "PowerModeFire2", threshold = 170, fg = "#FF6600", ctermfg = 202 },  -- orange
  { name = "PowerModeFire3", threshold = 120, fg = "#FFaa00", ctermfg = 220 },  -- gold/amber
  { name = "PowerModeFire4", threshold = 70,  fg = "#FFDD00", ctermfg = 226 },  -- yellow
  { name = "PowerModeFire5", threshold = 25,  fg = "#884400", ctermfg = 94  },  -- dim ember
}

-- Mode parameters
local mode_params = {
  ember_rise = {
    base_heat = 120,
    heat_per_level = 25,
    cooling = 10,
    seed_density = 0.4,
    max_height_frac = 0.12,
  },
  fire_columns = {
    base_heat = 200,
    heat_per_level = 12,
    cooling = 5,
    seed_density = 0.8,
    max_height_frac = 0.20,
  },
  inferno = {
    base_heat = 240,
    heat_per_level = 4,
    cooling = 2,
    seed_density = 0.95,
    max_height_frac = 0.35,
  },
}

local function create_fire_highlights()
  local bg = "#110800"
  local ctermbg = 0
  for _, hl in ipairs(fire_hl_groups) do
    vim.api.nvim_set_hl(0, hl.name, {
      fg = hl.fg,
      bg = bg,
      ctermfg = hl.ctermfg,
      ctermbg = ctermbg,
    })
  end
  -- Background highlight for empty cells
  vim.api.nvim_set_hl(0, "PowerModeFireBg", {
    fg = bg,
    bg = bg,
    ctermfg = ctermbg,
    ctermbg = ctermbg,
  })
end

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
  return " "
end

local function heat_to_hl(heat)
  for _, hl in ipairs(fire_hl_groups) do
    if heat >= hl.threshold then return hl.name end
  end
  return "PowerModeFireBg"
end

local function ensure_window()
  if fire_buf and not vim.api.nvim_buf_is_valid(fire_buf) then
    fire_buf = nil
  end
  if fire_win and not vim.api.nvim_win_is_valid(fire_win) then
    fire_win = nil
  end

  local dims = utils.get_editor_dimensions()
  local cfg = config.get()
  local fw = cfg.fire_wall
  if fw.mode == "none" then return false end

  local params = mode_params[fw.mode]
  if not params then return false end

  local fire_h = math.max(2, math.floor(dims.height * params.max_height_frac))
  local fire_w = dims.width

  ensure_grid(fire_w, fire_h)

  if not fire_buf then
    fire_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[fire_buf].bufhidden = "wipe"
  end

  local win_row = dims.height - fire_h - 1  -- position at bottom, above statusline

  if not fire_win then
    local ok, w = pcall(vim.api.nvim_open_win, fire_buf, false, {
      relative = "editor",
      row = win_row,
      col = 0,
      width = fire_w,
      height = fire_h,
      style = "minimal",
      focusable = false,
      noautocmd = true,
      zindex = 40,
    })
    if ok then
      fire_win = w
      pcall(vim.api.nvim_win_set_option, fire_win, "winhighlight",
        "Normal:PowerModeFireBg,NormalFloat:PowerModeFireBg")
      pcall(vim.api.nvim_win_set_option, fire_win, "winblend", 20)
    else
      return false
    end
  else
    pcall(vim.api.nvim_win_set_config, fire_win, {
      relative = "editor",
      row = win_row,
      col = 0,
      width = fire_w,
      height = fire_h,
    })
  end

  return true
end

local function seed_bottom_row()
  local cfg = config.get()
  local fw = cfg.fire_wall
  if fw.mode == "none" then return end

  local params = mode_params[fw.mode]
  if not params or grid_h == 0 then return end

  local level = math.min(current_combo_level or 0, 4)
  local max_heat = math.min(255, params.base_heat + level * params.heat_per_level)

  for x = 1, grid_w do
    if math.random() < params.seed_density then
      grid[grid_h][x] = utils.random_int(math.floor(max_heat * 0.7), max_heat)
    else
      grid[grid_h][x] = utils.random_int(0, math.floor(max_heat * 0.15))
    end
  end
end

--- Propagate heat upward and render to the floating window
function M.update(_dt)
  local cfg = config.get()
  local fw = cfg.fire_wall
  if fw.mode == "none" then
    M._hide_window()
    return
  end

  local params = mode_params[fw.mode]
  if not params then
    M._hide_window()
    return
  end

  -- Ensure window exists
  if not ensure_window() then return end
  if grid_h == 0 then return end

  -- Continuously re-seed bottom row every frame (like real cacafire)
  if is_active then
    seed_bottom_row()
  end

  -- Propagate: each cell = average of 3 cells below - random cooling
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
    local cool = utils.random_int(0, math.floor(params.cooling * 0.3))
    grid[grid_h][x] = math.max(0, grid[grid_h][x] - cool)
  end

  -- Render heat buffer to the floating window buffer
  if not fire_buf or not vim.api.nvim_buf_is_valid(fire_buf) then return end

  local lines = {}
  for y = 1, grid_h do
    local row_chars = {}
    for x = 1, grid_w do
      row_chars[x] = heat_to_char(grid[y][x])
    end
    lines[y] = table.concat(row_chars)
  end

  pcall(vim.api.nvim_buf_set_lines, fire_buf, 0, -1, false, lines)

  -- Apply per-cell highlights
  vim.api.nvim_buf_clear_namespace(fire_buf, fire_ns, 0, -1)
  for y = 1, grid_h do
    local col_byte = 0
    for x = 1, grid_w do
      local heat = grid[y][x]
      local hl = heat_to_hl(heat)
      local ch = heat_to_char(heat)
      local ch_len = #ch  -- byte length
      pcall(vim.api.nvim_buf_add_highlight, fire_buf, fire_ns, hl, y - 1, col_byte, col_byte + ch_len)
      col_byte = col_byte + ch_len
    end
  end
end

function M._hide_window()
  if fire_win and vim.api.nvim_win_is_valid(fire_win) then
    pcall(vim.api.nvim_win_set_config, fire_win, {
      relative = "editor",
      row = -100,
      col = -100,
      width = 1,
      height = 1,
    })
  end
end

--- Called on keystroke to update combo level and activate fire
function M.spawn(combo_level)
  current_combo_level = combo_level or 0
  is_active = true
end

--- For engine compatibility (fire wall manages its own window, returns empty)
function M.get_active()
  return {}
end

function M.init()
  create_fire_highlights()
end

function M.clear()
  is_active = false
  grid = {}
  grid_w = 0
  grid_h = 0

  if fire_win and vim.api.nvim_win_is_valid(fire_win) then
    pcall(vim.api.nvim_win_close, fire_win, true)
  end
  fire_win = nil
  if fire_buf and vim.api.nvim_buf_is_valid(fire_buf) then
    pcall(vim.api.nvim_buf_delete, fire_buf, { force = true })
  end
  fire_buf = nil
end

function M.set_mode(mode)
  if mode ~= "none" and not mode_params[mode] then
    vim.notify("[power-mode] Unknown fire wall mode: " .. tostring(mode), vim.log.levels.ERROR)
    return
  end
  local cfg = config.get()
  cfg.fire_wall.mode = mode
  if mode == "none" then
    M.clear()
  else
    create_fire_highlights()
    is_active = true
  end
  vim.notify("⚡ Fire wall mode: " .. mode, vim.log.levels.INFO)
end

function M.get_mode()
  local cfg = config.get()
  return cfg.fire_wall.mode
end

return M
