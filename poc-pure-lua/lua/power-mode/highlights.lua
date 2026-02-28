local M = {}

local particle_colors = {
  { fg = "#00FFFF", bg = "#002233" }, -- cyan
  { fg = "#FF1493", bg = "#330011" }, -- pink
  { fg = "#BF00FF", bg = "#1A0033" }, -- purple
  { fg = "#39FF14", bg = "#0A2200" }, -- green
  { fg = "#FF6600", bg = "#331100" }, -- orange
  { fg = "#FFD700", bg = "#332200" }, -- gold
  { fg = "#00FF88", bg = "#003318" }, -- teal
  { fg = "#FF00FF", bg = "#330033" }, -- magenta
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
    vim.api.nvim_set_hl(0, "PowerModeParticle" .. i, { fg = color.fg, bg = color.bg })
  end

  for level, color in pairs(combo_colors) do
    vim.api.nvim_set_hl(0, "PowerModeCombo" .. level, { fg = color, bg = "#0a0a1a", bold = true })
  end

  vim.api.nvim_set_hl(0, "PowerModeGlowOuter", { bg = "#003333", blend = 88 })
  vim.api.nvim_set_hl(0, "PowerModeGlowMid", { bg = "#005555", blend = 70 })
  vim.api.nvim_set_hl(0, "PowerModeGlowInner", { bg = "#00CCCC", blend = 45 })
end

function M.update_glow_color(color)
  vim.api.nvim_set_hl(0, "PowerModeGlowInner", { bg = color, blend = 45 })
  vim.api.nvim_set_hl(0, "PowerModeGlowMid", { bg = color, blend = 70 })
  vim.api.nvim_set_hl(0, "PowerModeGlowOuter", { bg = color, blend = 88 })
end

return M
