--- Fire wall module for neovim-power-mode (cacafire heat-buffer algorithm)
--- Self-managed floating window at the bottom of the editor.
--- Classic 2D heat buffer: continuously seed bottom → propagate upward with cooling → render
--- Height grows with combo level: hidden for levels 0-1, 2 rows at level 2, +1 row per 2 levels.
--- Fades out naturally when combo resets (heat cools without re-seeding).
--- Toggle: enabled (true/false)
local config = require("power-mode.config")
local utils = require("power-mode.utils")

local M = {}

-- Heat buffer: grid[y][x] = heat value 0-255
local grid = {}
local grid_w = 0
local grid_h = 0  -- max grid height (allocated)

-- Self-managed floating window
local fire_win = nil
local fire_buf = nil

-- Current combo state (set by spawn, used by update for continuous seeding)
local current_combo_level = 0

-- Whether actively seeding heat (true while typing, false during cooldown)
local is_active = false

-- Whether we're in cooldown phase (heat still visible but no longer seeded)
local cooling_down = false

-- Last visible_rows value (preserved during cooldown for smooth fade)
local last_visible_rows = 0

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

-- Fire highlight groups with transparent (NONE) background
-- winblend makes empty/cool cells see-through
local fire_hl_groups = {
  { name = "PowerModeFire1", threshold = 220, fg = "#FF2200", ctermfg = 196 },  -- bright red
  { name = "PowerModeFire2", threshold = 170, fg = "#FF6600", ctermfg = 202 },  -- orange
  { name = "PowerModeFire3", threshold = 120, fg = "#FFaa00", ctermfg = 220 },  -- gold/amber
  { name = "PowerModeFire4", threshold = 70,  fg = "#FFDD00", ctermfg = 226 },  -- yellow
  { name = "PowerModeFire5", threshold = 25,  fg = "#884400", ctermfg = 94  },  -- dim ember
}

-- Fire parameters (fire_columns-based, the best-performing mode)
local fire_params = {
  base_heat = 200,
  heat_per_level = 12,
  cooling = 5,
  seed_density = 0.8,
  -- Level-based growth: no fire for levels 0-1, 2 rows at level 2, +1 row per level after
  min_level = 2,
  base_rows = 2,
  levels_per_row = 1,
}

local function create_fire_highlights()
  for _, hl in ipairs(fire_hl_groups) do
    vim.api.nvim_set_hl(0, hl.name, {
      fg = hl.fg,
      bg = "NONE",
      ctermfg = hl.ctermfg,
      ctermbg = "NONE",
    })
  end
  -- Transparent background for empty/cold cells
  vim.api.nvim_set_hl(0, "PowerModeFireBg", {
    fg = "NONE",
    bg = "NONE",
    ctermfg = "NONE",
    ctermbg = "NONE",
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

--- Compute how many rows of fire should be visible based on combo level
--- Level 0-1: 0 rows, Level 2: base_rows, then +1 row every levels_per_row levels
local function compute_visible_rows(max_rows)
  local p = fire_params
  local cfg = config.get()
  local cap = math.min(cfg.fire_wall.max_rows or 5, max_rows)
  if current_combo_level < p.min_level then return 0 end
  local extra_levels = current_combo_level - p.min_level
  local rows = p.base_rows + math.floor(extra_levels / p.levels_per_row)
  return math.min(rows, cap)
end

local function ensure_window(visible_h)
  if fire_buf and not vim.api.nvim_buf_is_valid(fire_buf) then
    fire_buf = nil
  end
  if fire_win and not vim.api.nvim_win_is_valid(fire_win) then
    fire_win = nil
  end

  if visible_h <= 0 then
    M._hide_window()
    return false
  end

  local dims = utils.get_editor_dimensions()
  local fire_w = dims.width

  if not fire_buf then
    fire_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[fire_buf].bufhidden = "wipe"
  end

  local win_row = dims.height - visible_h - (config.get().fire_wall.bottom_offset or 2)

  if not fire_win then
    local ok, w = pcall(vim.api.nvim_open_win, fire_buf, false, {
      relative = "editor",
      row = win_row,
      col = 0,
      width = fire_w,
      height = visible_h,
      style = "minimal",
      focusable = false,
      noautocmd = true,
      zindex = 40,
    })
    if ok then
      fire_win = w
      pcall(vim.api.nvim_win_set_option, fire_win, "winhighlight",
        "Normal:PowerModeFireBg,NormalFloat:PowerModeFireBg")
      -- High winblend makes cool/empty cells transparent so editor shows through
      pcall(vim.api.nvim_win_set_option, fire_win, "winblend", 50)
    else
      return false
    end
  else
    pcall(vim.api.nvim_win_set_config, fire_win, {
      relative = "editor",
      row = win_row,
      col = 0,
      width = fire_w,
      height = visible_h,
    })
  end

  return true
end

local function seed_bottom_row()
  local cfg = config.get()
  if not cfg.fire_wall.enabled then return end
  if grid_h == 0 then return end

  local level = math.min(current_combo_level or 0, 4)
  local max_heat = math.min(255, fire_params.base_heat + level * fire_params.heat_per_level)

  for x = 1, grid_w do
    if math.random() < fire_params.seed_density then
      grid[grid_h][x] = utils.random_int(math.floor(max_heat * 0.7), max_heat)
    else
      grid[grid_h][x] = utils.random_int(0, math.floor(max_heat * 0.15))
    end
  end
end

--- Check if the grid has any heat remaining
local function grid_has_heat()
  for y = 1, grid_h do
    for x = 1, grid_w do
      if grid[y] and grid[y][x] and grid[y][x] > 5 then
        return true
      end
    end
  end
  return false
end

--- Propagate heat upward and render to the floating window
function M.update(_dt)
  local cfg = config.get()
  if not cfg.fire_wall.enabled then
    M._hide_window()
    return
  end

  -- Compute max grid height and ensure grid
  local dims = utils.get_editor_dimensions()
  local max_grid_h = math.max(2, cfg.fire_wall.max_rows or 5)
  ensure_grid(dims.width, max_grid_h)

  if grid_h == 0 then return end

  -- Compute visible rows based on combo level
  local visible_rows
  if cooling_down then
    -- During cooldown, keep last visible height but check if heat is gone
    visible_rows = last_visible_rows
    if not grid_has_heat() then
      cooling_down = false
      last_visible_rows = 0
      M._hide_window()
      return
    end
  else
    visible_rows = compute_visible_rows(grid_h)
    last_visible_rows = visible_rows
  end

  if visible_rows <= 0 then
    M._hide_window()
    return
  end

  -- Ensure window sized to visible rows
  if not ensure_window(visible_rows) then return end

  -- Seed bottom row only when actively typing (not during cooldown)
  if is_active and not cooling_down then
    seed_bottom_row()
  end

  -- Propagate: each cell = average of 3 cells below - random cooling
  for y = 1, grid_h - 1 do
    for x = 1, grid_w do
      local below = grid[y + 1][x]
      local left = grid[y + 1][math.max(1, x - 1)]
      local right = grid[y + 1][math.min(grid_w, x + 1)]
      local avg = (below + left + right) / 3
      local cool = utils.random_int(0, fire_params.cooling)
      grid[y][x] = math.max(0, math.floor(avg - cool))
    end
  end

  -- Cool the bottom row (faster during cooldown for visible fade)
  local cool_factor = cooling_down and 1.5 or 0.3
  for x = 1, grid_w do
    local cool = utils.random_int(0, math.floor(fire_params.cooling * cool_factor))
    grid[grid_h][x] = math.max(0, grid[grid_h][x] - cool)
  end

  -- Render only the bottom `visible_rows` of the heat grid to the buffer
  if not fire_buf or not vim.api.nvim_buf_is_valid(fire_buf) then return end

  local start_y = grid_h - visible_rows + 1
  local lines = {}
  for y = start_y, grid_h do
    local row_chars = {}
    for x = 1, grid_w do
      row_chars[x] = heat_to_char(grid[y][x])
    end
    lines[#lines + 1] = table.concat(row_chars)
  end

  pcall(vim.api.nvim_buf_set_lines, fire_buf, 0, -1, false, lines)

  -- Apply per-cell highlights
  vim.api.nvim_buf_clear_namespace(fire_buf, fire_ns, 0, -1)
  for i = 1, visible_rows do
    local y = start_y + i - 1
    local col_byte = 0
    for x = 1, grid_w do
      local heat = grid[y][x]
      local hl = heat_to_hl(heat)
      local ch = heat_to_char(heat)
      local ch_len = #ch
      pcall(vim.api.nvim_buf_add_highlight, fire_buf, fire_ns, hl, i - 1, col_byte, col_byte + ch_len)
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
function M.spawn(combo_level, _streak)
  current_combo_level = combo_level or 0
  is_active = true
  cooling_down = false
end

--- Begin cooldown: stop seeding, let heat fade naturally
function M.cool_down()
  is_active = false
  cooling_down = true
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
  cooling_down = false
  current_combo_level = 0
  last_visible_rows = 0
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

function M.set_enabled(val)
  local cfg = config.get()
  cfg.fire_wall.enabled = val and true or false
  if cfg.fire_wall.enabled then
    create_fire_highlights()
    is_active = true
    cooling_down = false
    vim.notify("⚡ Fire wall: on", vim.log.levels.INFO)
  else
    M.clear()
    vim.notify("⚡ Fire wall: off", vim.log.levels.INFO)
  end
end

--- Legacy set_mode: "none" → disabled, anything else → enabled
function M.set_mode(mode)
  if mode == "none" or mode == "off" then
    M.set_enabled(false)
  elseif mode == "on" or mode == "ember_rise" or mode == "fire_columns" or mode == "inferno" then
    M.set_enabled(true)
  else
    vim.notify("[power-mode] Unknown fire wall mode: " .. tostring(mode), vim.log.levels.ERROR)
  end
end

function M.is_enabled()
  local cfg = config.get()
  return cfg.fire_wall.enabled
end

--- Legacy get_mode for backward compat
function M.get_mode()
  local cfg = config.get()
  return cfg.fire_wall.enabled and "on" or "none"
end

return M
