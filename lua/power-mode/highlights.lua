--- Highlight group management for neovim-power-mode
--- Reads colors from config and creates all highlight groups
local config = require("power-mode.config")

local M = {}

function M.setup()
  local cfg = config.get()

  -- Particle colors (PowerModeParticle1..8)
  for i = 1, 8 do
    local key = "color_" .. i
    local c = cfg.colors[key]
    if c then
      vim.api.nvim_set_hl(0, "PowerModeParticle" .. i, {
        fg = c[1],
        bg = c[2],
        ctermfg = c[3],
        ctermbg = c[4],
      })
    end
  end

  -- Combo level colors (PowerModeCombo0..4)
  local combo_bg = "#0a0a1a"
  local combo_ctermbg = 234
  for level = 0, 4 do
    local lc = cfg.combo.level_colors[level]
    if lc then
      vim.api.nvim_set_hl(0, "PowerModeCombo" .. level, {
        fg = lc[1],
        bg = combo_bg,
        bold = true,
        ctermfg = lc[2],
        ctermbg = combo_ctermbg,
      })
    end
  end
end

--- Update combo highlight to match current level
function M.update_combo_level(level)
  -- Combo highlights are already created in setup(); the combo module
  -- switches winhighlight to reference the correct level group
end

return M
