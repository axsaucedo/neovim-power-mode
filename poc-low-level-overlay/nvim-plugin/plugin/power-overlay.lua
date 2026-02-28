-- Power Mode Overlay - Neovim event bridge for external overlay process
-- Sends cursor position and keystroke events to an external overlay process

vim.api.nvim_create_user_command("OverlayStart", function(opts)
  require("power-overlay").start(opts.args ~= "" and opts.args or nil)
end, { nargs = "?", desc = "Start the Power Mode overlay process" })

vim.api.nvim_create_user_command("OverlayStop", function()
  require("power-overlay").stop()
end, { desc = "Stop the Power Mode overlay process" })

vim.api.nvim_create_user_command("OverlayStatus", function()
  require("power-overlay").status()
end, { desc = "Show Power Mode overlay status" })
