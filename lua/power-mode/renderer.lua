--- Floating window pool renderer for neovim-power-mode
--- Manages a pool of 1×1 floating windows for particle rendering
local config = require("power-mode.config")

local M = {}

local pool = {}

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
      pool[i] = { buf = buf, win = win, in_use = false }
    end
  end
end

function M.render(particles)
  local cfg = config.get()
  local avoid = cfg.particles.avoid_cursor

  -- Mark all as unused
  for _, entry in ipairs(pool) do
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
    local char_width = vim.fn.strdisplaywidth(p.char)
    if char_width < 1 then char_width = 1 end
    pcall(vim.api.nvim_win_set_config, entry.win, {
      relative = "editor",
      row = py,
      col = px,
      width = char_width,
      height = 1,
    })

    local blend = math.floor(100 * (1 - p.lifetime / p.max_lifetime))
    pcall(vim.api.nvim_win_set_option, entry.win, "winblend", blend)
    pcall(vim.api.nvim_win_set_option, entry.win, "winhighlight",
      "Normal:PowerModeParticle" .. p.color_idx)

    pool_idx = pool_idx + 1
    ::continue::
  end

  -- Hide unused windows offscreen
  for _, entry in ipairs(pool) do
    if not entry.in_use and vim.api.nvim_win_is_valid(entry.win) then
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

function M.cleanup()
  for _, entry in ipairs(pool) do
    if entry.win and vim.api.nvim_win_is_valid(entry.win) then
      pcall(vim.api.nvim_win_close, entry.win, true)
    end
    if entry.buf and vim.api.nvim_buf_is_valid(entry.buf) then
      pcall(vim.api.nvim_buf_delete, entry.buf, { force = true })
    end
  end
  pool = {}
end

return M
