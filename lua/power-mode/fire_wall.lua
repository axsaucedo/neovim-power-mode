--- Fire wall module for neovim-power-mode (cacafire heat-buffer algorithm)
--- Self-managed floating window at the bottom of the editor.
--- Classic 2D heat buffer: continuously seed bottom → propagate upward with cooling → render
--- Height grows with combo streak: starts at 1 row after 2 keystrokes, +1 row every 2 more.
--- Top cells rendered transparent (winblend + NONE bg) so editor shows through.
--- Four modes: none | ember_rise | fire_columns | inferno
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
local current_streak = 0

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

-- Fire highlight groups with transparent (NONE) background
-- winblend makes empty/cool cells see-through
local fire_hl_groups = {
  { name = "PowerModeFire1", threshold = 220, fg = "#FF2200", ctermfg = 196 },  -- bright red
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
    min_streak = 2,       -- combo keystrokes before fire starts
    rows_per_streak = 2,  -- add 1 row every N keystrokes
  },
  fire_columns = {
    base_heat = 200,
    heat_per_level = 12,
    cooling = 5,
    seed_density = 0.8,
    max_height_frac = 0.20,
    min_streak = 2,
    rows_per_streak = 2,
  },
  inferno = {
    base_heat = 240,
    heat_per_level = 4,
    cooling = 2,
    seed_density = 0.95,
    max_height_frac = 0.35,
    min_streak = 2,
    rows_per_streak = 2,
  },
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

--- Compute how many rows of fire should be visible based on combo streak
local function compute_visible_rows(params, max_rows)
  if current_streak < params.min_streak then return 0 end
  local extra = current_streak - params.min_streak
  local rows = 1 + math.floor(extra / params.rows_per_streak)
  return math.min(rows, max_rows)
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

  local win_row = dims.height - visible_h - 1  -- position at bottom, above statusline

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

  -- Compute max grid height and ensure grid
  local dims = utils.get_editor_dimensions()
  local max_grid_h = math.max(2, math.floor(dims.height * params.max_height_frac))
  ensure_grid(dims.width, max_grid_h)

  if grid_h == 0 then return end

  -- Compute visible rows based on combo streak
  local visible_rows = compute_visible_rows(params, grid_h)

  if visible_rows <= 0 then
    M._hide_window()
    return
  end

  -- Ensure window sized to visible rows
  if not ensure_window(visible_rows) then return end

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

--- Called on keystroke to update combo level/streak and activate fire
function M.spawn(combo_level, streak)
  current_combo_level = combo_level or 0
  current_streak = streak or 0
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
  current_streak = 0
  current_combo_level = 0
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
