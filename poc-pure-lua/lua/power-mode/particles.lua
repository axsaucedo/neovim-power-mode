local M = {}

local modes = {
  shockwave = "power-mode.particles_shockwave",
  fountain = "power-mode.particles_fountain",
  disintegrate = "power-mode.particles_disintegrate",
  explosion = "power-mode.particles_explosion",
  rightburst = "power-mode.particles_rightburst",
  emoji = "power-mode.particles_emoji",
  stars = "power-mode.particles_stars",
}

local current_mode = "explosion"  -- default
local current_module = nil

local function load_mode(mode_name)
  local mod_path = modes[mode_name]
  if not mod_path then
    vim.notify("Unknown particle mode: " .. tostring(mode_name), vim.log.levels.ERROR)
    return
  end
  -- Clear old module cache to force reload
  package.loaded[mod_path] = nil
  current_module = require(mod_path)
  current_mode = mode_name
end

function M.set_mode(mode_name)
  if current_module then
    current_module.clear()
  end
  load_mode(mode_name)
  vim.notify("⚡ Particle mode: " .. mode_name, vim.log.levels.INFO)
end

function M.get_mode()
  return current_mode
end

function M.spawn(row, col)
  if not current_module then load_mode(current_mode) end
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

-- Initialize default mode
load_mode(current_mode)

return M
