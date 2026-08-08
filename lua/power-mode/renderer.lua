--- Floating window pool renderer for neovim-power-mode
--- Manages a pool of 1×1 floating windows for particle rendering
local config = require("power-mode.config")
local utils = require("power-mode.utils")

local M = {}

local pool = {}
local cleanup_batch_size = 20

-- Test-only accessor for the shared UI-suppression helper.
M._with_ui_suppressed = function(fn) return utils.with_ui_suppressed("renderer cleanup", fn) end

-- F8: cache strdisplaywidth(char) per unique particle char. The particle
-- alphabet across all presets is small and bounded (~30 chars), so the
-- cache fills within the first frame of activity and is pure table
-- lookup thereafter. strdisplaywidth is a vimscript bridge call that
-- accounted for ~0.25 ms p50 in the latency micro-bench; skipping the
-- bridge on cache hits is essentially free per-particle.
local char_width_cache = {}
local function get_char_width(ch)
  local w = char_width_cache[ch]
  if w == nil then
    w = vim.fn.strdisplaywidth(ch)
    if w < 1 then w = 1 end
    char_width_cache[ch] = w
  end
  return w
end

function M.init()
  M.cleanup()
  local cfg = config.get()
  local pool_size = cfg.particles.pool_size

  for i = 1, pool_size do
    local buf = vim.api.nvim_create_buf(false, true)
    pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, { " " })
    local ok, win = pcall(vim.api.nvim_open_win, buf, false, {
      relative = "editor",
      row = -10,
      col = -10,
      width = 1,
      height = 1,
      style = "minimal",
      focusable = false,
      noautocmd = true,
      zindex = 50,
    })
    if ok then
      -- F8: `was_in_use` tracks last-frame state so the offscreen-hide
      -- loop only emits nvim_win_set_config for slots that were in use
      -- last frame but aren't this frame. Pool size is 100 by default
      -- and steady-state usage is ~10 slots; this avoids ~90 redundant
      -- config writes per frame.
      pool[i] = { buf = buf, win = win, in_use = false, was_in_use = false }
    end
  end
end

local function cleanup_entries(entries, first, last)
  utils.with_ui_suppressed("renderer cleanup", function()
    for i = first, last do
      local entry = entries[i]
      if entry.buf and vim.api.nvim_buf_is_valid(entry.buf) then
        pcall(vim.api.nvim_buf_delete, entry.buf, { force = true })
      end
      if entry.win and vim.api.nvim_win_is_valid(entry.win) then
        pcall(vim.api.nvim_win_close, entry.win, true)
      end
    end
  end)
end

local function cleanup_deferred(entries, first)
  if first > #entries then return end
  cleanup_entries(entries, first, math.min(first + cleanup_batch_size - 1, #entries))
  local next_entry = first + cleanup_batch_size
  if next_entry <= #entries then
    vim.schedule(function() cleanup_deferred(entries, next_entry) end)
  end
end

function M.render(particles)
  local cfg = config.get()
  local avoid = cfg.particles.avoid_cursor

  -- Mark all as unused (preserving the previous-frame state in was_in_use)
  for _, entry in ipairs(pool) do
    entry.was_in_use = entry.in_use
    entry.in_use = false
  end

  -- Get cursor position for avoidance
  local cursor_row, cursor_col = -1, -1
  if avoid then
    pcall(function()
      local cur = vim.api.nvim_win_get_cursor(0)
      local pos = vim.fn.screenpos(vim.fn.win_getid(), cur[1], cur[2] + 1)
      cursor_row = pos.row - 1
      cursor_col = pos.col - 1
    end)
  end

  local pool_idx = 1
  for _, p in ipairs(particles) do
    while pool_idx <= #pool and pool[pool_idx].in_use do
      pool_idx = pool_idx + 1
    end
    if pool_idx > #pool then break end

    local entry = pool[pool_idx]
    local px, py = math.floor(p.x), math.floor(p.y)

    -- Skip particles that would shadow the cursor or previous character
    if avoid and py == cursor_row and (px == cursor_col or px == cursor_col - 1) then
      goto continue
    end

    entry.in_use = true

    if not vim.api.nvim_win_is_valid(entry.win) then
      local ok, win = pcall(vim.api.nvim_open_win, entry.buf, false, {
        relative = "editor",
        row = py,
        col = px,
        width = 2,
        height = 1,
        style = "minimal",
        focusable = false,
        noautocmd = true,
        zindex = 50,
      })
      if ok then
        entry.win = win
      else
        goto continue
      end
    end

    pcall(vim.api.nvim_buf_set_lines, entry.buf, 0, -1, false, { p.char })
    local char_width = get_char_width(p.char)
    pcall(vim.api.nvim_win_set_config, entry.win, {
      relative = "editor",
      row = py,
      col = px,
      width = char_width,
      height = 1,
    })

    local blend = math.floor(100 * (1 - p.lifetime / p.max_lifetime))
    pcall(vim.api.nvim_win_set_option, entry.win, "winblend", blend)
    local hl_name = "PowerModeParticle" .. p.color_idx
    pcall(vim.api.nvim_win_set_option, entry.win, "winhighlight",
      "Normal:" .. hl_name .. ",NormalFloat:" .. hl_name)

    pool_idx = pool_idx + 1
    ::continue::
  end

  -- Hide windows that *were* visible last frame but aren't this frame.
  -- Slots that have been parked offscreen since at least last frame
  -- already have row=-10,col=-10 and don't need to be touched again.
  for _, entry in ipairs(pool) do
    if entry.was_in_use and not entry.in_use and vim.api.nvim_win_is_valid(entry.win) then
      pcall(vim.api.nvim_win_set_config, entry.win, {
        relative = "editor",
        row = -10,
        col = -10,
        width = 1,
        height = 1,
      })
    end
  end
end

--- Reclaim the particle pool, optionally after parking visible slots.
--- @param defer boolean|nil
function M.cleanup(defer)
  local old_pool = pool
  pool = {}

  if defer then
    -- F9: park the few visible slots before returning, then reclaim the old
    -- pool in small batches. See the 2026-08-08 disable latency benchmark.
    for _, entry in ipairs(old_pool) do
      if entry.in_use and entry.win and vim.api.nvim_win_is_valid(entry.win) then
        pcall(vim.api.nvim_win_set_config, entry.win, {
          relative = "editor",
          row = -10,
          col = -10,
          width = 1,
          height = 1,
        })
      end
    end
    vim.schedule(function() cleanup_deferred(old_pool, 1) end)
  else
    cleanup_entries(old_pool, 1, #old_pool)
  end
end

return M
