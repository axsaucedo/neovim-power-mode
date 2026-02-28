--- neovim-power-mode: VS Code Power Mode for Neovim
--- Main orchestrator: setup, enable/disable, event wiring
local config = require("power-mode.config")
local highlights = require("power-mode.highlights")
local particles = require("power-mode.particles")
local renderer = require("power-mode.renderer")
local combo = require("power-mode.combo")
local engine = require("power-mode.engine")
local shake = require("power-mode.shake")
local fire = require("power-mode.presets.fire")

local M = {}

local enabled = false
local augroup = nil
local stop_timer = nil
local on_key_ns = nil

local function get_cursor_pos()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local pos = vim.fn.screenpos(vim.fn.win_getid(), cursor[1], cursor[2] + 1)
  return pos.row - 1, pos.col - 1
end

--- Configure neovim-power-mode
--- @param opts table|nil User configuration (merged with defaults + vim globals)
function M.setup(opts)
  config.resolve(opts)
  highlights.setup()
  particles.init()

  -- Wire engine modules (avoids circular requires)
  engine.set_modules(particles, fire, renderer, combo)

  local cfg = config.get()
  if cfg.auto_enable then
    M.enable()
  end
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
        shake.trigger(combo.get_level())

        if stop_timer then
          pcall(function() stop_timer:stop() stop_timer:close() end)
          stop_timer = nil
        end
      end)
    end,
  })

  -- Detect backspace for fire effect
  local cfg = config.get()
  if cfg.backspace.enabled then
    local bs_code = vim.api.nvim_replace_termcodes("<BS>", true, false, true)
    local del_code = vim.api.nvim_replace_termcodes("<Del>", true, false, true)
    on_key_ns = vim.on_key(function(key)
      if not enabled then return end
      if key ~= bs_code and key ~= del_code then return end
      vim.schedule(function()
        if not enabled then return end
        local m = vim.api.nvim_get_mode().mode
        if m ~= "i" and m ~= "ic" and m ~= "ix" then return end
        local row, col = get_cursor_pos()
        fire.spawn(row, col)
      end)
    end)
  end

  vim.api.nvim_create_autocmd("InsertLeave", {
    group = augroup,
    callback = function()
      if not enabled then return end
      combo.reset()

      if stop_timer then
        pcall(function() stop_timer:stop() stop_timer:close() end)
      end
      local delay = config.get().engine.stop_delay
      stop_timer = vim.loop.new_timer()
      stop_timer:start(delay, 0, vim.schedule_wrap(function()
        if not enabled then return end
        if #particles.get_active() == 0 and #fire.get_active() == 0 then
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

  if on_key_ns then
    pcall(vim.on_key, nil, on_key_ns)
    on_key_ns = nil
  end

  if augroup then
    vim.api.nvim_del_augroup_by_id(augroup)
    augroup = nil
  end

  engine.stop()
  particles.clear()
  fire.clear()
  renderer.cleanup()
  combo.cleanup()
  shake.cleanup()

  vim.notify("Power Mode disabled", vim.log.levels.INFO)
end

function M.toggle()
  if enabled then
    M.disable()
  else
    M.enable()
  end
end

function M.is_enabled()
  return enabled
end

--- Show current configuration status
function M.status()
  local cfg = config.get()
  local lines = {
    "⚡ Power Mode Status",
    "  Enabled: " .. tostring(enabled),
    "  Particle preset: " .. tostring(cfg.particles.preset),
    "  Cancel on new: " .. tostring(cfg.particles.cancel_on_new),
    "  Shake mode: " .. cfg.shake.mode,
    "  Combo: " .. tostring(cfg.combo.enabled),
    "  FPS: " .. tostring(cfg.engine.fps),
    "  Backspace fire: " .. tostring(cfg.backspace.enabled),
  }
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

return M
