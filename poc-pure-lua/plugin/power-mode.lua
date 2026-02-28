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
