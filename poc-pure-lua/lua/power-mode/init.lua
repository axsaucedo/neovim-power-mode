local highlights = require("power-mode.highlights")
local particles = require("power-mode.particles")
local renderer = require("power-mode.renderer")
local combo = require("power-mode.combo")
local engine = require("power-mode.engine")

local M = {}

local enabled = false
local augroup = nil
local stop_timer = nil

local defaults = {
  auto_enable = false,
}

local config = {}

function M.setup(opts)
  config = vim.tbl_deep_extend("force", defaults, opts or {})
  highlights.setup()
  if config.auto_enable then
    M.enable()
  end
end

local function get_cursor_pos()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local pos = vim.fn.screenpos(vim.fn.win_getid(), cursor[1], cursor[2] + 1)
  return pos.row - 1, pos.col - 1
end

function M.enable()
  if enabled then return end
  enabled = true

  highlights.setup()
  renderer.init()
  combo.init()
  engine.start()

  augroup = vim.api.nvim_create_augroup("PowerMode", { clear = true })

  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = augroup,
    callback = function()
      vim.schedule(function()
        if not enabled then return end
        local row, col = get_cursor_pos()
        particles.spawn(row, col)
        combo.increment()

        -- Cancel any pending stop timer
        if stop_timer then
          pcall(function() stop_timer:stop() stop_timer:close() end)
          stop_timer = nil
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd("InsertLeave", {
    group = augroup,
    callback = function()
      if not enabled then return end
      combo.reset()

      -- Stop engine after a short delay to let particles finish
      if stop_timer then
        pcall(function() stop_timer:stop() stop_timer:close() end)
      end
      stop_timer = vim.loop.new_timer()
      stop_timer:start(2000, 0, vim.schedule_wrap(function()
        if not enabled then return end
        if #particles.get_active() == 0 then
          engine.stop()
        end
        if stop_timer then
          pcall(function() stop_timer:stop() stop_timer:close() end)
          stop_timer = nil
        end
      end))
    end,
  })

  vim.api.nvim_create_autocmd("InsertEnter", {
    group = augroup,
    callback = function()
      if not enabled then return end
      -- Cancel pending stop and restart engine
      if stop_timer then
        pcall(function() stop_timer:stop() stop_timer:close() end)
        stop_timer = nil
      end
      if not engine.is_running() then
        engine.start()
      end
    end,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = augroup,
    callback = function()
      if not enabled then return end
      combo.reposition()
    end,
  })

  vim.notify("⚡ Power Mode ENABLED", vim.log.levels.INFO)
end

function M.disable()
  if not enabled then return end
  enabled = false

  if stop_timer then
    pcall(function() stop_timer:stop() stop_timer:close() end)
    stop_timer = nil
  end

  if augroup then
    vim.api.nvim_del_augroup_by_id(augroup)
    augroup = nil
  end

  engine.stop()
  particles.clear()
  renderer.cleanup()
  combo.cleanup()

  vim.notify("Power Mode disabled", vim.log.levels.INFO)
end

function M.toggle()
  if enabled then
    M.disable()
  else
    M.enable()
  end
end

return M
