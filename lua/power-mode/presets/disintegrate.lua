--- Disintegrate preset: buffer text characters shatter outward
--- Uses actual text from buffer near cursor + tumble animation
local utils = require("power-mode.utils")
local config = require("power-mode.config")

local M = {}
local active = {}

local tumble_frames = { "╱", "─", "╲", "│" }

function M.spawn(row, col)
  local cfg = config.get()
  local max_p = cfg.particles.max_particles

  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local buf_row = cursor[1]
  local buf_col = cursor[2]
  local lines = vim.api.nvim_buf_get_lines(buf, math.max(0, buf_row - 2), buf_row + 1, false)

  for dy = -1, 1 do
    local line_idx = dy + 1 + 1
    local line = lines[line_idx]
    if not line then goto next_row end

    for dx = -3, 3 do
      if dx == 0 and dy == 0 then goto next_col end
      if #active >= max_p then return end
      if math.random() > 0.4 then goto next_col end

      local char_col = buf_col + dx
      if char_col < 0 or char_col >= #line then goto next_col end

      local char = line:sub(char_col + 1, char_col + 1)
      if char == " " or char == "" then goto next_col end

      local dist = math.sqrt(dx * dx + dy * dy)
      if dist < 0.01 then dist = 1 end
      local dir_x = dx / dist
      local dir_y = dy / dist
      local speed = utils.random(2, 5)

      active[#active + 1] = {
        x = col + dx, y = row + dy,
        vx = dir_x * speed + utils.random(-0.5, 0.5),
        vy = dir_y * speed * 0.5 + utils.random(-0.3, 0.3),
        char = char,
        original_char = char,
        use_tumble = math.random() > 0.5,
        tumble_idx = utils.random_int(1, 4),
        tumble_timer = 0,
        color_idx = utils.random_int(1, 8),
        lifetime = utils.random(400, 800),
        max_lifetime = 800,
      }

      ::next_col::
    end
    ::next_row::
  end
end

function M.update(dt)
  local dims = utils.get_editor_dimensions()
  local i = 1
  while i <= #active do
    local p = active[i]
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    p.vy = p.vy + 0.2 * dt * 60
    p.vx = p.vx * 0.96
    p.vy = p.vy * 0.96
    p.lifetime = p.lifetime - dt * 1000

    if p.use_tumble then
      p.tumble_timer = p.tumble_timer + dt * 1000
      if p.tumble_timer > 80 then
        p.tumble_timer = 0
        p.tumble_idx = (p.tumble_idx % #tumble_frames) + 1
        p.char = tumble_frames[p.tumble_idx]
      end
    end

    if p.lifetime <= 0 or p.x < 0 or p.x >= dims.width or p.y < 0 or p.y >= dims.height then
      active[i] = active[#active]
      active[#active] = nil
    else
      i = i + 1
    end
  end
end

function M.get_active() return active end
function M.clear() active = {} end
return M
