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

print(string.format("\n=== Highlight Tests: %d passed, %d failed ===", pass, fail))
if fail > 0 then
  vim.cmd("cquit! 1")
end
