--- Plugin entry point for neovim-power-mode
--- Defines user commands and prevents double-loading
if vim.g.loaded_power_mode then
  return
end
vim.g.loaded_power_mode = true

vim.api.nvim_create_user_command("PowerModeToggle", function()
  require("power-mode").toggle()
end, { desc = "Toggle Power Mode on/off" })

vim.api.nvim_create_user_command("PowerModeEnable", function()
  require("power-mode").enable()
end, { desc = "Enable Power Mode" })

vim.api.nvim_create_user_command("PowerModeDisable", function()
  require("power-mode").disable()
end, { desc = "Disable Power Mode" })

vim.api.nvim_create_user_command("PowerModeStyle", function(opts)
  require("power-mode.particles").set_mode(opts.args)
end, {
  nargs = 1,
  complete = function()
    return { "explosion", "fountain", "rightburst", "shockwave", "disintegrate", "emoji", "stars" }
  end,
  desc = "Set particle style preset",
})

vim.api.nvim_create_user_command("PowerModeShake", function(opts)
  local mode = opts.args
  local cfg = require("power-mode.config")
  cfg.config.shake.mode = mode
  vim.notify("⚡ Shake mode: " .. mode, vim.log.levels.INFO)
end, {
  nargs = 1,
  complete = function()
    return { "none", "scroll", "applescript" }
  end,
  desc = "Set shake mode: none, scroll, or applescript",
})

vim.api.nvim_create_user_command("PowerModeCancel", function(opts)
  local val = opts.args == "on" or opts.args == "true"
  local cfg = require("power-mode.config")
  cfg.config.particles.cancel_on_new = val
  vim.notify("⚡ Cancel on new: " .. tostring(val), vim.log.levels.INFO)
end, {
  nargs = 1,
  complete = function()
    return { "on", "off" }
  end,
  desc = "Toggle cancel-previous-particles: on/off",
})

vim.api.nvim_create_user_command("PowerModeFireWall", function(opts)
  require("power-mode.fire_wall").set_mode(opts.args)
end, {
  nargs = 1,
  complete = function()
    return { "none", "ember_rise", "fire_columns", "inferno" }
  end,
  desc = "Set fire wall mode: none, ember_rise, fire_columns, or inferno",
})

vim.api.nvim_create_user_command("PowerModeStatus", function()
  require("power-mode").status()
end, { desc = "Show Power Mode status and configuration" })
