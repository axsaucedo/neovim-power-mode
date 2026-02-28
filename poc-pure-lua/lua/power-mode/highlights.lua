local M = {}

local particle_colors = {
  "#00FFFF", "#FF1493", "#BF00FF", "#39FF14",
  "#FF6600", "#FFD700", "#00FF88", "#FF00FF",
}

local combo_colors = {
  [0] = "#39FF14",
  [1] = "#00FFFF",
  [2] = "#FF1493",
  [3] = "#BF00FF",
  [4] = "#FF0000",
}

function M.setup()
  for i, color in ipairs(particle_colors) do
    vim.api.nvim_set_hl(0, "PowerModeParticle" .. i, { fg = color, bg = "NONE" })
  end

  for level, color in pairs(combo_colors) do
    vim.api.nvim_set_hl(0, "PowerModeCombo" .. level, { fg = color, bg = "#0a0a1a", bold = true })
  end

  vim.api.nvim_set_hl(0, "PowerModeGlow", { bg = "#00FFFF", blend = 70 })
end

function M.update_glow_color(color)
  vim.api.nvim_set_hl(0, "PowerModeGlow", { bg = color, blend = 70 })
end

return M
