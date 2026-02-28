local M = {}

-- State
M.job_id = nil
M.combo = {
  streak = 0,
  level = 0,
  max_streak = 0,
  last_keystroke = 0,
  timeout = 3000, -- ms
  levels = { 10, 25, 50, 100, 200 },
}
M.augroup = nil

-- Detect overlay binary path
local function find_overlay()
  -- Look for overlay binaries relative to this plugin
  local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h:h")
  
  -- Try Swift overlay first (compiled binary)
  local swift_path = plugin_dir .. "/swift-overlay/power-mode-overlay"
  if vim.fn.executable(swift_path) == 1 then
    return swift_path
  end
  
  -- Fall back to Python overlay
  local python_path = plugin_dir .. "/python-overlay/main.py"
  if vim.fn.filereadable(python_path) == 1 then
    return "python3 " .. python_path
  end
  
  return nil
end

-- Calculate combo level from streak
local function calc_level(streak)
  local level = 0
  for _, threshold in ipairs(M.combo.levels) do
    if streak >= threshold then
      level = level + 1
    else
      break
    end
  end
  return level
end

-- Send a JSON event to the overlay process
local function send_event(event)
  if not M.job_id then return end
  
  local ok, json = pcall(vim.fn.json_encode, event)
  if not ok then return end
  
  pcall(vim.fn.chansend, M.job_id, json .. "\n")
end

-- Handle keystroke
local function on_keystroke()
  local now = vim.loop.now()
  
  -- Check timeout
  if M.combo.last_keystroke > 0 and (now - M.combo.last_keystroke) > M.combo.timeout then
    M.combo.streak = 0
    M.combo.level = 0
  end
  
  M.combo.streak = M.combo.streak + 1
  M.combo.last_keystroke = now
  M.combo.level = calc_level(M.combo.streak)
  
  if M.combo.streak > M.combo.max_streak then
    M.combo.max_streak = M.combo.streak
  end
  
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1  -- 0-indexed
  local col = cursor[2]
  
  -- Get screen position (account for line numbers, etc.)
  local win_pos = vim.api.nvim_win_get_position(0)
  local screen_row = win_pos[1] + row - vim.fn.line("w0") + 1
  local screen_col = win_pos[2] + col
  
  send_event({
    event = "keystroke",
    row = screen_row,
    col = screen_col,
    combo = M.combo.streak,
    level = M.combo.level,
    max_streak = M.combo.max_streak,
  })
end

-- Handle cursor move
local function on_cursor_move()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local win_pos = vim.api.nvim_win_get_position(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local screen_row = win_pos[1] + row - vim.fn.line("w0") + 1
  local screen_col = win_pos[2] + col
  
  send_event({
    event = "cursor_move",
    row = screen_row,
    col = screen_col,
    combo = M.combo.streak,
    level = M.combo.level,
  })
end

-- Handle leaving insert mode
local function on_insert_leave()
  send_event({ event = "pause" })
  -- Don't reset combo immediately — let timeout handle it
end

-- Start the overlay process
function M.start(cmd)
  if M.job_id then
    vim.notify("Power Mode overlay already running (job " .. M.job_id .. ")", vim.log.levels.WARN)
    return
  end
  
  cmd = cmd or find_overlay()
  if not cmd then
    vim.notify("No overlay binary found! Build swift-overlay or install python deps first.", vim.log.levels.ERROR)
    return
  end
  
  vim.notify("Starting Power Mode overlay: " .. cmd, vim.log.levels.INFO)
  
  M.job_id = vim.fn.jobstart(cmd, {
    stdin = "pipe",
    on_stderr = function(_, data, _)
      for _, line in ipairs(data) do
        if line ~= "" then
          vim.schedule(function()
            vim.notify("[overlay] " .. line, vim.log.levels.DEBUG)
          end)
        end
      end
    end,
    on_exit = function(_, code, _)
      vim.schedule(function()
        vim.notify("Power Mode overlay exited (code " .. code .. ")", vim.log.levels.INFO)
        M.job_id = nil
      end)
    end,
  })
  
  if M.job_id <= 0 then
    vim.notify("Failed to start overlay process", vim.log.levels.ERROR)
    M.job_id = nil
    return
  end
  
  -- Reset combo state
  M.combo.streak = 0
  M.combo.level = 0
  M.combo.last_keystroke = 0
  
  -- Setup autocmds
  M.augroup = vim.api.nvim_create_augroup("PowerOverlay", { clear = true })
  
  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = M.augroup,
    callback = on_keystroke,
  })
  
  vim.api.nvim_create_autocmd("CursorMovedI", {
    group = M.augroup,
    callback = on_cursor_move,
  })
  
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = M.augroup,
    callback = on_insert_leave,
  })
  
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = M.augroup,
    callback = function()
      M.stop()
    end,
  })
  
  vim.notify("Power Mode overlay started! Enter insert mode to activate.", vim.log.levels.INFO)
end

-- Stop the overlay process
function M.stop()
  if M.job_id then
    send_event({ event = "quit" })
    vim.fn.jobstop(M.job_id)
    M.job_id = nil
  end
  
  if M.augroup then
    vim.api.nvim_del_augroup_by_id(M.augroup)
    M.augroup = nil
  end
  
  M.combo.streak = 0
  M.combo.level = 0
  M.combo.last_keystroke = 0
  
  vim.notify("Power Mode overlay stopped.", vim.log.levels.INFO)
end

-- Show status
function M.status()
  if M.job_id then
    vim.notify(string.format(
      "Power Mode overlay: RUNNING (job %d)\nCombo: %d (level %d, max %d)",
      M.job_id, M.combo.streak, M.combo.level, M.combo.max_streak
    ), vim.log.levels.INFO)
  else
    vim.notify("Power Mode overlay: STOPPED", vim.log.levels.INFO)
  end
end

return M
