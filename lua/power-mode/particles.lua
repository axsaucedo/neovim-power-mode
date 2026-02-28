--- Particle mode dispatcher for neovim-power-mode
--- Loads presets, dispatches spawn/update/clear, handles cancel-on-new
local config = require("power-mode.config")

local M = {}

local builtin_presets = {
  explosion = "power-mode.presets.explosion",
  fountain = "power-mode.presets.fountain",
  rightburst = "power-mode.presets.rightburst",
  shockwave = "power-mode.presets.shockwave",
  emoji = "power-mode.presets.emoji",
  stars = "power-mode.presets.stars",
  disintegrate = "power-mode.presets.disintegrate",
}

local current_preset_name = nil
local current_module = nil

local function load_preset(name)
  local cfg = config.get()

  if name == "custom" then
    -- Use custom preset definition from config
    local custom_def = cfg.particles.custom
    if not custom_def then
      vim.notify("[power-mode] No custom preset defined in config", vim.log.levels.ERROR)
      return
    end
    -- Build a generic module from the custom definition
    local generic = require("power-mode.presets.explosion")
    current_module = generic
    current_preset_name = "custom"
    return
  end

  local mod_path = builtin_presets[name]
  if not mod_path then
    vim.notify("[power-mode] Unknown preset: " .. tostring(name), vim.log.levels.ERROR)
    return
  end

  -- Clear cache and reload
  package.loaded[mod_path] = nil
  current_module = require(mod_path)
  current_preset_name = name
end

function M.set_mode(name)
  if current_module then
    current_module.clear()
  end
  load_preset(name)
  vim.notify("⚡ Particle style: " .. name, vim.log.levels.INFO)
end

function M.get_mode()
  return current_preset_name
end

function M.spawn(row, col)
  local cfg = config.get()
  if not current_module then
    load_preset(cfg.particles.preset)
  end
  if not current_module then return end

  -- Cancel-on-new: rapidly fade existing particles
  if cfg.particles.cancel_on_new then
    local fadeout = cfg.particles.cancel_fadeout_ms
    local existing = current_module.get_active()
    for _, p in ipairs(existing) do
      if p.lifetime > fadeout then
        p.lifetime = fadeout
      end
    end
  end

  current_module.spawn(row, col)
end

function M.update(dt)
  if not current_module then return end
  current_module.update(dt)
end

function M.get_active()
  if not current_module then return {} end
  return current_module.get_active()
end

function M.clear()
  if current_module then current_module.clear() end
end

--- Initialize with the configured preset
function M.init()
  local cfg = config.get()
  load_preset(cfg.particles.preset)
end

return M
