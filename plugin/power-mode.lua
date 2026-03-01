--- Plugin entry point for neovim-power-mode
--- Defines user commands, auto-enables on VimEnter, prevents double-loading
if vim.g.loaded_power_mode then
  return
end
vim.g.loaded_power_mode = true

-- Auto-setup on VimEnter if user never called setup() explicitly.
-- This makes install → works with zero config.
vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("PowerModeAutoSetup", { clear = true }),
  once = true,
  callback = function()
    -- Defer to let user's config (init.lua / vimrc) finish loading first
    vim.defer_fn(function()
      local pm = require("power-mode")
      if not pm._is_setup_called() then
        pm.setup()
      end
    end, 0)
  end,
})

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
    return { "rightburst", "stars", "explosion", "fountain", "shockwave", "emoji", "disintegrate" }
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

vim.api.nvim_create_user_command("PowerModeInterrupt", function(opts)
  local val = opts.args == "on" or opts.args == "true"
  local cfg = require("power-mode.config")
  cfg.config.particles.cancel_on_new = val
  vim.notify("⚡ Interrupt on new: " .. tostring(val), vim.log.levels.INFO)
end, {
  nargs = 1,
  complete = function()
    return { "on", "off" }
  end,
  desc = "Toggle interrupt-previous-particles: on/off",
})

-- Deprecated alias: PowerModeCancel → PowerModeInterrupt
vim.api.nvim_create_user_command("PowerModeCancel", function(opts)
  vim.notify("[power-mode] PowerModeCancel is deprecated, use PowerModeInterrupt", vim.log.levels.WARN)
  vim.cmd("PowerModeInterrupt " .. opts.args)
end, {
  nargs = 1,
  complete = function()
    return { "on", "off" }
  end,
  desc = "(Deprecated) Use :PowerModeInterrupt instead",
})

vim.api.nvim_create_user_command("PowerModeFireWall", function(opts)
  local arg = opts.args
  if arg == "on" then
    require("power-mode.fire_wall").set_enabled(true)
  elseif arg == "off" then
    require("power-mode.fire_wall").set_enabled(false)
  else
    -- Legacy mode names still accepted
    require("power-mode.fire_wall").set_mode(arg)
  end
end, {
  nargs = 1,
  complete = function()
    return { "on", "off" }
  end,
  desc = "Toggle fire wall: on or off",
})

vim.api.nvim_create_user_command("PowerModeStatus", function()
  require("power-mode").status()
end, { desc = "Show Power Mode status and configuration" })
