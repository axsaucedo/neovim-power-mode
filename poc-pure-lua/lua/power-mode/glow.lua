local M = {}

local win = nil
local buf = nil

function M.init()
  M.cleanup()
  buf = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, { "   ", "   ", "   " })

  local ok, w = pcall(vim.api.nvim_open_win, buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = 3,
    height = 3,
    style = "minimal",
    focusable = false,
    noautocmd = true,
    zindex = 1,
  })
  if ok then
    win = w
    pcall(vim.api.nvim_win_set_option, win, "winblend", 70)
    pcall(vim.api.nvim_win_set_option, win, "winhighlight", "Normal:PowerModeGlow")
  end
end

function M.update(row, col)
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  local r = math.max(0, row - 1)
  local c = math.max(0, col - 1)
  pcall(vim.api.nvim_win_set_config, win, {
    relative = "editor",
    row = r,
    col = c,
    width = 3,
    height = 3,
  })
end

function M.show()
  -- Glow is always shown when win exists; just ensure it's valid
  if not win or not vim.api.nvim_win_is_valid(win) then
    M.init()
  end
end

function M.hide()
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_set_config, win, {
      relative = "editor",
      row = -10,
      col = -10,
      width = 3,
      height = 3,
    })
  end
end

function M.cleanup()
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
  win = nil
  buf = nil
end

return M
