--- Tests for highlight system
local config = require("power-mode.config")
config.resolve({})

local highlights = require("power-mode.highlights")

local pass = 0
local fail = 0

local function assert_eq(a, b, msg)
  if a == b then
    pass = pass + 1
  else
    fail = fail + 1
    print("FAIL: " .. msg .. " | expected: " .. tostring(b) .. " got: " .. tostring(a))
  end
end

local function assert_true(val, msg)
  if val then
    pass = pass + 1
  else
    fail = fail + 1
    print("FAIL: " .. msg)
  end
end

-- Setup highlights
highlights.setup()

-- Test 1: particle highlight groups exist
for i = 1, 8 do
  local name = "PowerModeParticle" .. i
  local hl = vim.api.nvim_get_hl(0, { name = name })
  assert_true(hl.fg ~= nil, name .. " has fg")
  assert_true(hl.bg ~= nil, name .. " has bg")
  assert_true(hl.ctermfg ~= nil, name .. " has ctermfg")
  assert_true(hl.ctermbg ~= nil, name .. " has ctermbg")
end

-- Test 2: combo highlight groups exist
for level = 0, 4 do
  local name = "PowerModeCombo" .. level
  local hl = vim.api.nvim_get_hl(0, { name = name })
  assert_true(hl.fg ~= nil, name .. " has fg")
  assert_true(hl.bg ~= nil, name .. " has bg")
  assert_true(hl.bold == true, name .. " is bold")
end

-- Test 3: custom colors are applied
config.resolve({ colors = { color_1 = { "#FF0000", "#110000", 196, 52 } } })
highlights.setup()
local hl = vim.api.nvim_get_hl(0, { name = "PowerModeParticle1" })
-- nvim_get_hl returns fg as integer; #FF0000 = 16711680
assert_eq(hl.fg, 16711680, "custom color_1 fg applied")

-- Reset
config.resolve({})
highlights.setup()

-- Test 4: Highlights survive colorscheme clear (via ColorScheme autocmd)
-- Simulate what setup() does: create the autocmd
local pm = require("power-mode")
pm.setup({})

-- Verify highlights exist
local hl_before = vim.api.nvim_get_hl(0, { name = "PowerModeParticle1" })
assert_true(hl_before.fg ~= nil, "highlights exist before colorscheme clear")

-- Simulate colorscheme loading: highlight clear + trigger ColorScheme event
vim.cmd("highlight clear")
local hl_cleared = vim.api.nvim_get_hl(0, { name = "PowerModeParticle1" })
assert_true(hl_cleared.fg == nil or next(hl_cleared) == nil, "highlights wiped after highlight clear")

-- Fire the ColorScheme autocmd (as a real :colorscheme X would)
vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "*" })
local hl_after = vim.api.nvim_get_hl(0, { name = "PowerModeParticle1" })
assert_true(hl_after.fg ~= nil, "highlights restored after ColorScheme autocmd")

-- Verify all 8 particle + 5 combo groups survived
for i = 1, 8 do
  local h = vim.api.nvim_get_hl(0, { name = "PowerModeParticle" .. i })
  assert_true(h.fg ~= nil, "Particle" .. i .. " survives colorscheme clear")
  assert_true(h.ctermfg ~= nil, "Particle" .. i .. " ctermfg survives colorscheme clear")
end
for level = 0, 4 do
  local h = vim.api.nvim_get_hl(0, { name = "PowerModeCombo" .. level })
  assert_true(h.fg ~= nil, "Combo" .. level .. " survives colorscheme clear")
  assert_true(h.ctermfg ~= nil, "Combo" .. level .. " ctermfg survives colorscheme clear")
end

print(string.format("\n=== Highlight Tests: %d passed, %d failed ===", pass, fail))
if fail > 0 then
  vim.cmd("cquit! 1")
end
