local M = {}

local particle_colors = {
  { fg = "#00FFFF", bg = "#002233", ctermfg = 14,  ctermbg = 23  }, -- cyan
  { fg = "#FF1493", bg = "#330011", ctermfg = 199, ctermbg = 52  }, -- pink
  { fg = "#BF00FF", bg = "#1A0033", ctermfg = 129, ctermbg = 53  }, -- purple
  { fg = "#39FF14", bg = "#0A2200", ctermfg = 46,  ctermbg = 22  }, -- green
  { fg = "#FF6600", bg = "#331100", ctermfg = 202, ctermbg = 94  }, -- orange
  { fg = "#FFD700", bg = "#332200", ctermfg = 220, ctermbg = 58  }, -- gold
  { fg = "#00FF88", bg = "#003318", ctermfg = 48,  ctermbg = 23  }, -- teal
  { fg = "#FF00FF", bg = "#330033", ctermfg = 201, ctermbg = 53  }, -- magenta
}

local combo_colors = {
  [0] = { fg = "#39FF14", bg = "#0a0a1a", ctermfg = 46,  ctermbg = 234 },
  [1] = { fg = "#00FFFF", bg = "#0a0a1a", ctermfg = 14,  ctermbg = 234 },
  [2] = { fg = "#FF1493", bg = "#0a0a1a", ctermfg = 199, ctermbg = 234 },
  [3] = { fg = "#BF00FF", bg = "#0a0a1a", ctermfg = 129, ctermbg = 234 },
  [4] = { fg = "#FF0000", bg = "#0a0a1a", ctermfg = 196, ctermbg = 234 },
}

function M.setup()
  for i, color in ipairs(particle_colors) do
    vim.api.nvim_set_hl(0, "PowerModeParticle" .. i, {
      fg = color.fg,
      bg = color.bg,
      ctermfg = color.ctermfg,
      ctermbg = color.ctermbg,
    })
  end

  for level, color in pairs(combo_colors) do
    vim.api.nvim_set_hl(0, "PowerModeCombo" .. level, {
      fg = color.fg, bg = color.bg, bold = true,
      ctermfg = color.ctermfg, ctermbg = color.ctermbg,
    })
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
