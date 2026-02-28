local utils = require("power-mode.utils")
local highlights = require("power-mode.highlights")

local M = {}

local state = {
  current_streak = 0,
  level = 0,
  max_streak = 0,
  last_keystroke_time = 0,
  timeout_remaining = 0,
}

local TIMEOUT_DURATION = 3000 -- ms
local WIN_WIDTH = 20
local WIN_HEIGHT = 7

local win = nil
local buf = nil
local base_row = 1
local base_col = 0
local exclamation = ""
local exclamation_timer = nil

local level_thresholds = { 10, 25, 50, 100, 200 }

local exclamations = {
  "UNSTOPPABLE!", "GODLIKE!", "RAMPAGE!", "MEGA KILL!",
  "DOMINATING!", "WICKED SICK!", "LEGENDARY!",
}

local level_glow_colors = {
  [0] = "#39FF14",
  [1] = "#00FFFF",
  [2] = "#FF1493",
  [3] = "#BF00FF",
  [4] = "#FF0000",
}

local function compute_level(streak)
  local lvl = 0
  for i, threshold in ipairs(level_thresholds) do
    if streak >= threshold then lvl = i end
  end
  return math.min(lvl, 4)
end

local function center_text(text, width)
  local pad = math.max(0, math.floor((width - #text) / 2))
  return string.rep(" ", pad) .. text .. string.rep(" ", math.max(0, width - pad - #text))
end

local function render_bar(ratio, width)
  local filled = math.floor(ratio * width)
  return string.rep("█", filled) .. string.rep("░", width - filled)
end

function M.init()
  M.cleanup()
  base_col = vim.o.columns - WIN_WIDTH - 2

  buf = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, { "", "", "", "", "", "", "" })

  local ok, w = pcall(vim.api.nvim_open_win, buf, false, {
    relative = "editor",
    row = base_row,
    col = base_col,
    width = WIN_WIDTH,
    height = WIN_HEIGHT,
    style = "minimal",
    border = "rounded",
    focusable = false,
    noautocmd = true,
    zindex = 100,
  })
  if ok then
    win = w
    pcall(vim.api.nvim_win_set_option, win, "winhighlight", "Normal:PowerModeCombo0,FloatBorder:PowerModeCombo0")
  end

  M.render()
end

function M.increment()
  state.current_streak = state.current_streak + 1
  if state.current_streak > state.max_streak then
    state.max_streak = state.current_streak
  end

  local new_level = compute_level(state.current_streak)
  state.level = new_level
  state.timeout_remaining = TIMEOUT_DURATION
  state.last_keystroke_time = vim.loop.now()

  -- Milestone exclamations
  if state.current_streak % 10 == 0 or state.current_streak == level_thresholds[state.level] then
    exclamation = utils.random_choice(exclamations)
    if exclamation_timer then
      pcall(function() exclamation_timer:stop() exclamation_timer:close() end)
    end
    exclamation_timer = vim.loop.new_timer()
    exclamation_timer:start(1500, 0, vim.schedule_wrap(function()
      exclamation = ""
      M.render()
      if exclamation_timer then
        pcall(function() exclamation_timer:stop() exclamation_timer:close() end)
        exclamation_timer = nil
      end
    end))
  end

  -- Shake effect
  if win and vim.api.nvim_win_is_valid(win) then
    local shake_amount = math.min(1 + state.level, 4)
    local jitter_row = base_row + utils.random_int(-shake_amount, shake_amount)
    local jitter_col = base_col + utils.random_int(-shake_amount, shake_amount)
    jitter_row = utils.clamp(jitter_row, 0, vim.o.lines - WIN_HEIGHT - 2)
    jitter_col = utils.clamp(jitter_col, 0, vim.o.columns - WIN_WIDTH - 2)

    pcall(vim.api.nvim_win_set_config, win, {
      relative = "editor",
      row = jitter_row,
      col = jitter_col,
      width = WIN_WIDTH,
      height = WIN_HEIGHT,
    })

    vim.defer_fn(function()
      if win and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_set_config, win, {
          relative = "editor",
          row = base_row,
          col = base_col,
          width = WIN_WIDTH,
          height = WIN_HEIGHT,
        })
      end
    end, 60)
  end

  -- Update highlight color for level
  if win and vim.api.nvim_win_is_valid(win) then
    local hl = "PowerModeCombo" .. state.level
    pcall(vim.api.nvim_win_set_option, win, "winhighlight", "Normal:" .. hl .. ",FloatBorder:" .. hl)
  end

  -- Update glow color
  local glow_color = level_glow_colors[state.level] or "#39FF14"
  highlights.update_glow_color(glow_color)

  M.render()
end

function M.reset()
  state.current_streak = 0
  state.level = 0
  state.timeout_remaining = 0
  exclamation = ""
  M.render()
end

function M.update(dt)
  if state.timeout_remaining > 0 then
    state.timeout_remaining = state.timeout_remaining - dt * 1000
    if state.timeout_remaining <= 0 then
      state.timeout_remaining = 0
      M.reset()
    end
  end
  M.render()
end

function M.render()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local num_str = tostring(state.current_streak)
  local bar_ratio = state.timeout_remaining / TIMEOUT_DURATION
  bar_ratio = utils.clamp(bar_ratio, 0, 1)
  local bar = render_bar(bar_ratio, WIN_WIDTH - 4)

  local lines = {
    center_text("╔═ COMBO ═╗", WIN_WIDTH),
    center_text("║  " .. num_str .. "  ║", WIN_WIDTH),
    center_text("╚═════════╝", WIN_WIDTH),
    "  " .. bar,
    "  MAX: " .. tostring(state.max_streak),
    "",
    "",
  }

  if exclamation ~= "" then
    lines[6] = center_text(exclamation, WIN_WIDTH)
  end

  pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, lines)
end

function M.get_level()
  return state.level
end

function M.reposition()
  base_col = vim.o.columns - WIN_WIDTH - 2
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_set_config, win, {
      relative = "editor",
      row = base_row,
      col = base_col,
      width = WIN_WIDTH,
      height = WIN_HEIGHT,
    })
  end
end

function M.cleanup()
  if exclamation_timer then
    pcall(function() exclamation_timer:stop() exclamation_timer:close() end)
    exclamation_timer = nil
  end
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
  win = nil
  buf = nil
  state.current_streak = 0
  state.level = 0
  state.timeout_remaining = 0
  exclamation = ""
end

return M
