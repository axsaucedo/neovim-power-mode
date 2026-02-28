if vim.g.loaded_power_mode then
  return
end
vim.g.loaded_power_mode = true

vim.api.nvim_create_user_command("PowerModeToggle", function()
  require("power-mode").toggle()
end, { desc = "Toggle Power Mode" })

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
  desc = "Set particle style",
})

vim.api.nvim_create_user_command("PowerModeShake", function(opts)
  require("power-mode.shake").set_mode(opts.args)
end, {
  nargs = 1,
  complete = function()
    return { "none", "combo", "scroll", "applescript" }
  end,
  desc = "Set shake mode: none, combo (default), scroll, or applescript",
})
