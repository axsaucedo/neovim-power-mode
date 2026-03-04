--- Combo counter for neovim-power-mode
--- Floating window with streak, timeout bar, exclamations, and shake
local config = require("power-mode.config")
local utils = require("power-mode.utils")

local M = {}

local state = {
  current_streak = 0,
  level = 0,
  max_streak = 0,
  last_keystroke_time = 0,
  timeout_remaining = 0,
}

-- Callback fired when combo resets (timeout or explicit)
local on_reset_cb = nil

function M.set_on_reset(cb)
  on_reset_cb = cb
end

local win = nil
local buf = nil
local base_row = 1
local base_col = 0
local exclamation = ""
local exclamation_timer = nil

local function compute_level(streak)
  local cfg = config.get()
  local thresholds = cfg.combo.thresholds
  local lvl = 0
  for i, threshold in ipairs(thresholds) do
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

local function compute_position(cfg)
  local pos = cfg.combo.position
  local w = cfg.combo.width
  local h = cfg.combo.height

  local row, col
  if pos == "top-right" then
    row = 1
    col = vim.o.columns - w - 2
  elseif pos == "top-left" then
    row = 1
    col = 2
  elseif pos == "bottom-right" then
    row = vim.o.lines - h - 3
    col = vim.o.columns - w - 2
  elseif pos == "bottom-left" then
    row = vim.o.lines - h - 3
    col = 2
  else
    row = 1
    col = vim.o.columns - w - 2
  end
  return row, col
end

--- Ensure combo floating window exists; re-create if destroyed externally.
--- Preserves combo state (streak, level, max) — only re-creates the UI.
function M.ensure_window()
  local cfg = config.get()
  if not cfg.combo.enabled then return end

  local w = cfg.combo.width
  local h = cfg.combo.height

  -- Re-create buffer if needed
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    buf = vim.api.nvim_create_buf(false, true)
    local empty_lines = {}
    for _ = 1, h do empty_lines[#empty_lines + 1] = "" end
    pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, empty_lines)
  end

  -- Re-create window if needed
  if not win or not vim.api.nvim_win_is_valid(win) then
    base_row, base_col = compute_position(cfg)
    local ok, w_handle = pcall(vim.api.nvim_open_win, buf, false, {
      relative = "editor",
      row = base_row,
      col = base_col,
      width = w,
      height = h,
      style = "minimal",
      border = "rounded",
      focusable = false,
      noautocmd = true,
      zindex = 100,
    })
    if ok then
      win = w_handle
      local hl = "PowerModeCombo" .. state.level
      pcall(vim.api.nvim_win_set_option, win, "winhighlight",
        "Normal:" .. hl .. ",NormalFloat:" .. hl .. ",FloatBorder:" .. hl)
    end
  end
end

function M.init()
  M.cleanup()
  M.ensure_window()
  M.render()
end

function M.increment()
  local cfg = config.get()
  if not cfg.combo.enabled then return end

  M.ensure_window()

  state.current_streak = state.current_streak + 1
  if state.current_streak > state.max_streak then
    state.max_streak = state.current_streak
  end

  state.level = compute_level(state.current_streak)
  state.timeout_remaining = cfg.combo.timeout
  state.last_keystroke_time = vim.loop.now()

  -- Milestone exclamations
  local interval = cfg.combo.exclamation_interval
  if state.current_streak % interval == 0 and #cfg.combo.exclamations > 0 then
    exclamation = utils.random_choice(cfg.combo.exclamations)
    if exclamation_timer then
      pcall(function() exclamation_timer:stop() exclamation_timer:close() end)
    end
    exclamation_timer = vim.loop.new_timer()
    exclamation_timer:start(cfg.combo.exclamation_duration, 0, vim.schedule_wrap(function()
      exclamation = ""
      M.render()
      if exclamation_timer then
        pcall(function() exclamation_timer:stop() exclamation_timer:close() end)
        exclamation_timer = nil
      end
    end))
  end

  -- Shake combo window
  if cfg.combo.shake and win and vim.api.nvim_win_is_valid(win) then
    local shake_amount
    if cfg.combo.shake_intensity then
      shake_amount = utils.random_int(cfg.combo.shake_intensity[1], cfg.combo.shake_intensity[2])
    else
      shake_amount = math.min(1 + state.level, 4)
    end
    local jitter_row = base_row + utils.random_int(-shake_amount, shake_amount)
    local jitter_col = base_col + utils.random_int(-shake_amount, shake_amount)
    jitter_row = utils.clamp(jitter_row, 0, vim.o.lines - cfg.combo.height - 2)
    jitter_col = utils.clamp(jitter_col, 0, vim.o.columns - cfg.combo.width - 2)

    pcall(vim.api.nvim_win_set_config, win, {
      relative = "editor",
      row = jitter_row,
      col = jitter_col,
      width = cfg.combo.width,
      height = cfg.combo.height,
    })

    vim.defer_fn(function()
      if win and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_set_config, win, {
          relative = "editor",
          row = base_row,
          col = base_col,
          width = cfg.combo.width,
          height = cfg.combo.height,
        })
      end
    end, 60)
  end

  -- Update highlight color for level
  if win and vim.api.nvim_win_is_valid(win) then
    local hl = "PowerModeCombo" .. state.level
    pcall(vim.api.nvim_win_set_option, win, "winhighlight",
      "Normal:" .. hl .. ",NormalFloat:" .. hl .. ",FloatBorder:" .. hl)
  end

  M.render()
end

function M.reset()
  state.current_streak = 0
  state.level = 0
  state.timeout_remaining = 0
  exclamation = ""

  -- Reset combo window highlight back to default level 0
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_set_option, win, "winhighlight",
      "Normal:PowerModeCombo0,NormalFloat:PowerModeCombo0,FloatBorder:PowerModeCombo0")
  end

  -- Notify listeners (e.g., fire_wall cooldown)
  if on_reset_cb then
    pcall(on_reset_cb)
  end

  M.render()
end

function M.update(dt)
  local cfg = config.get()
  if not cfg.combo.enabled then return end

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
  M.ensure_window()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local cfg = config.get()
  local w = cfg.combo.width

  local num_str = tostring(state.current_streak)
  local bar_ratio = state.timeout_remaining / cfg.combo.timeout
  bar_ratio = utils.clamp(bar_ratio, 0, 1)
  local bar = render_bar(bar_ratio, w - 4)

  local lines = {
    center_text("╔═ COMBO ═╗", w),
    center_text("║  " .. num_str .. "  ║", w),
    center_text("╚═════════╝", w),
    "  " .. bar,
    "  MAX: " .. tostring(state.max_streak),
    "",
    "",
  }

  if exclamation ~= "" then
    lines[6] = center_text(exclamation, w)
  end

  -- Trim to height
  while #lines > cfg.combo.height do
    table.remove(lines)
  end

  pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, lines)
end

function M.get_level()
  return state.level
end

function M.get_streak()
  return state.current_streak
end

function M.reposition()
  local cfg = config.get()
  if not cfg.combo.enabled then return end

  base_row, base_col = compute_position(cfg)
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_set_config, win, {
      relative = "editor",
      row = base_row,
      col = base_col,
      width = cfg.combo.width,
      height = cfg.combo.height,
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
  state.max_streak = 0
  state.timeout_remaining = 0
  exclamation = ""
end

return M
