local M = {}

local pool = {}
local POOL_SIZE = 60

function M.init()
  M.cleanup()
  for i = 1, POOL_SIZE do
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
  -- Mark all as unused
  for _, entry in ipairs(pool) do
    entry.in_use = false
  end

  local pool_idx = 1
  for _, p in ipairs(particles) do
    -- Find next available slot
    while pool_idx <= #pool and pool[pool_idx].in_use do
      pool_idx = pool_idx + 1
    end
    if pool_idx > #pool then break end

    local entry = pool[pool_idx]
    entry.in_use = true

    if not vim.api.nvim_win_is_valid(entry.win) then
      -- Recreate window if invalidated
      local ok, win = pcall(vim.api.nvim_open_win, entry.buf, false, {
        relative = "editor",
        row = math.floor(p.y),
        col = math.floor(p.x),
        width = 1,
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
    pcall(vim.api.nvim_win_set_config, entry.win, {
      relative = "editor",
      row = math.floor(p.y),
      col = math.floor(p.x),
      width = 1,
      height = 1,
    })

    local blend = math.floor(100 * (1 - p.lifetime / p.max_lifetime))
    pcall(vim.api.nvim_win_set_option, entry.win, "winblend", blend)
    pcall(vim.api.nvim_win_set_option, entry.win, "winhighlight", "Normal:PowerModeParticle" .. p.color_idx)

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
