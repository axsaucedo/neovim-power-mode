local M = {}

local layers = {}

local layer_specs = {
  { width = 7, height = 3, blend = 88, hl = "PowerModeGlowOuter" },
  { width = 5, height = 3, blend = 70, hl = "PowerModeGlowMid" },
  { width = 3, height = 1, blend = 45, hl = "PowerModeGlowInner" },
}

function M.init()
  M.cleanup()
  for _, spec in ipairs(layer_specs) do
    local buf = vim.api.nvim_create_buf(false, true)
    local lines = {}
    for _ = 1, spec.height do
      table.insert(lines, string.rep(" ", spec.width))
    end
    pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, lines)

    local ok, win = pcall(vim.api.nvim_open_win, buf, false, {
      relative = "editor",
      row = -10, col = -10,
      width = spec.width, height = spec.height,
      style = "minimal", focusable = false, noautocmd = true, zindex = 1,
    })
    if ok then
      pcall(vim.api.nvim_win_set_option, win, "winblend", spec.blend)
      pcall(vim.api.nvim_win_set_option, win, "winhighlight", "Normal:" .. spec.hl)
      table.insert(layers, { win = win, buf = buf, width = spec.width, height = spec.height })
    end
  end
end

function M.update(row, col)
  for _, layer in ipairs(layers) do
    if layer.win and vim.api.nvim_win_is_valid(layer.win) then
      local r = math.max(0, row - math.floor(layer.height / 2))
      local c = math.max(0, col - math.floor(layer.width / 2))
      pcall(vim.api.nvim_win_set_config, layer.win, {
        relative = "editor",
        row = r, col = c,
        width = layer.width, height = layer.height,
      })
    end
  end
end

function M.show()
  local valid = false
  for _, layer in ipairs(layers) do
    if layer.win and vim.api.nvim_win_is_valid(layer.win) then
      valid = true
      break
    end
  end
  if not valid then M.init() end
end

function M.hide()
  for _, layer in ipairs(layers) do
    if layer.win and vim.api.nvim_win_is_valid(layer.win) then
      pcall(vim.api.nvim_win_set_config, layer.win, {
        relative = "editor",
        row = -10, col = -10,
        width = layer.width, height = layer.height,
      })
    end
  end
end

function M.cleanup()
  for _, layer in ipairs(layers) do
    if layer.win and vim.api.nvim_win_is_valid(layer.win) then
      pcall(vim.api.nvim_win_close, layer.win, true)
    end
    if layer.buf and vim.api.nvim_buf_is_valid(layer.buf) then
      pcall(vim.api.nvim_buf_delete, layer.buf, { force = true })
    end
  end
  layers = {}
end

return M
