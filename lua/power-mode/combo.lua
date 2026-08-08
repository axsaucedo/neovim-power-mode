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
  hidden = true,
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
local hide_timer = nil
local render_valid = false
local highlight_valid = false
local last_streak = nil
local last_bar_filled = nil
local last_max_streak = nil
local last_exclamation = nil
local last_width = nil
local last_height = nil
local last_level = nil

local function invalidate_render()
  render_valid = false
  highlight_valid = false
end

local function apply_highlight()
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  if highlight_valid and last_level == state.level then return end
  local hl = "PowerModeCombo" .. state.level
  local ok = pcall(vim.api.nvim_win_set_option, win, "winhighlight",
    "Normal:" .. hl .. ",NormalFloat:" .. hl .. ",FloatBorder:" .. hl)
  if ok then
    last_level = state.level
    highlight_valid = true
  end
end

local function cancel_hide_timer()
  if hide_timer then
    pcall(function() hide_timer:stop() hide_timer:close() end)
    hide_timer = nil
  end
end

--- Close the floating window but keep buffer + state intact so we can
--- re-show the combo immediately on the next keystroke.
local function close_window()
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  win = nil
end

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
--- No-op while the combo box is hidden (auto-hide after reset): the engine
--- render loop and BufEnter autocmd both call into here, and we must not
--- resurrect the window between combos.
function M.ensure_window()
  local cfg = config.get()
  if not cfg.combo.enabled then return end
  if state.hidden then return end

  local w = cfg.combo.width
  local h = cfg.combo.height

  -- Re-create buffer if needed
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    buf = vim.api.nvim_create_buf(false, true)
    local empty_lines = {}
    for _ = 1, h do empty_lines[#empty_lines + 1] = "" end
    pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, empty_lines)
    invalidate_render()
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
      invalidate_render()
      apply_highlight()
    end
  end
end

function M.init()
  M.cleanup()
  -- Start hidden — the window is created lazily on the first keystroke so
  -- the combo box is only visible while a combo is actually active.
  state.hidden = true
end

function M.increment()
  local cfg = config.get()
  if not cfg.combo.enabled then return end

  -- A new keystroke always cancels any pending auto-hide and re-shows the
  -- combo box immediately (even if the previous streak had just timed out).
  cancel_hide_timer()
  state.hidden = false

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

  M.render()
end

function M.reset()
  state.current_streak = 0
  state.level = 0
  state.timeout_remaining = 0
  exclamation = ""

  -- Schedule auto-hide: after combo_box_disappear_seconds of no activity,
  -- close the floating window entirely. A new keystroke cancels this timer
  -- via increment(). Only schedule if not already hidden and no timer is
  -- pending, so repeated reset() calls don't stack timers.
  local cfg = config.get()
  local linger_s = cfg.combo.combo_box_disappear_seconds or 0
  if not state.hidden and not hide_timer then
    if linger_s <= 0 then
      state.hidden = true
      close_window()
    else
      hide_timer = vim.loop.new_timer()
      hide_timer:start(math.floor(linger_s * 1000), 0, vim.schedule_wrap(function()
        cancel_hide_timer()
        state.hidden = true
        close_window()
      end))
    end
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
  if state.hidden then return end
  M.ensure_window()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local cfg = config.get()
  local w = cfg.combo.width
  local h = cfg.combo.height

  local num_str = tostring(state.current_streak)
  local bar_ratio = state.timeout_remaining / cfg.combo.timeout
  bar_ratio = utils.clamp(bar_ratio, 0, 1)
  local bar_width = w - 4
  local bar_filled = math.floor(bar_ratio * bar_width)

  apply_highlight()

  -- E1: skip the buffer write when every visible combo key is unchanged.
  -- Phase 1 found 47.4% duplicate combo frames at 25 fps and 74.6% at
  -- 60 fps in the particles + combo workload (report-energy-phase1.md).
  if render_valid
    and last_streak == state.current_streak
    and last_bar_filled == bar_filled
    and last_max_streak == state.max_streak
    and last_exclamation == exclamation
    and last_width == w
    and last_height == h then
    return
  end

  local bar = string.rep("█", bar_filled) .. string.rep("░", bar_width - bar_filled)

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
  while #lines > h do
    table.remove(lines)
  end

  local ok = pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, lines)
  if ok then
    last_streak = state.current_streak
    last_bar_filled = bar_filled
    last_max_streak = state.max_streak
    last_exclamation = exclamation
    last_width = w
    last_height = h
    render_valid = true
  end
end

function M.get_level()
  return state.level
end

--- Cheap idle predicate used by the engine fast-path.
--- Combo has no work to do this tick iff the window is hidden AND
--- there is no timeout remaining to count down.
function M.is_idle()
  return state.hidden and state.timeout_remaining <= 0
end

function M.get_streak()
  return state.current_streak
end

function M.reposition()
  local cfg = config.get()
  if not cfg.combo.enabled then return end

  base_row, base_col = compute_position(cfg)
  invalidate_render()
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
  cancel_hide_timer()
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
  state.hidden = true
  exclamation = ""
  invalidate_render()
end

--- Invalidate cached UI state after an external redraw boundary.
function M.invalidate()
  invalidate_render()
end

-- Internal accessor for tests: returns visibility state.
function M._is_hidden()
  return state.hidden
end

function M._has_pending_hide()
  return hide_timer ~= nil
end

function M._get_window()
  return win
end

return M
