--- Configuration system for neovim-power-mode
--- Priority: setup() opts > vim globals > defaults
local M = {}

local defaults = {
  auto_enable = true,

  particles = {
    preset = "rightburst",
    cancel_on_new = true,
    cancel_fadeout_ms = 80,
    count = { 6, 10 },
    speed = { 5, 12 },
    lifetime = { 200, 500 },
    gravity = 0.15,
    drag = 0.96,
    spread = { -2.79, -0.35 },
    upward_bias = 0.7,
    chars = nil,
    pool_size = 60,
    max_particles = 100,
    avoid_cursor = true,
    -- Custom preset definition (only used when preset = "custom")
    custom = nil,
  },

  backspace = {
    enabled = true,
    preset = "fire",
    chars = nil,
    colors = { 5, 6 },
  },

  colors = {
    color_1 = { "#00FFFF", "#002233", 14, 23 },
    color_2 = { "#FF1493", "#330011", 199, 52 },
    color_3 = { "#BF00FF", "#1A0033", 129, 53 },
    color_4 = { "#39FF14", "#0A2200", 46, 22 },
    color_5 = { "#FF6600", "#331100", 202, 94 },
    color_6 = { "#FFD700", "#332200", 220, 58 },
    color_7 = { "#00FF88", "#003318", 48, 23 },
    color_8 = { "#FF00FF", "#330033", 201, 53 },
  },

  combo = {
    enabled = true,
    position = "top-right",
    width = 20,
    height = 7,
    timeout = 3000,
    thresholds = { 10, 25, 50, 100, 200 },
    shake = true,
    shake_intensity = nil,
    exclamations = {
      "UNSTOPPABLE!", "GODLIKE!", "RAMPAGE!", "MEGA KILL!",
      "SUPERCHARGED!", "ON FIRE!", "LEGENDARY!",
    },
    exclamation_interval = 10,
    exclamation_duration = 1500,
    level_colors = {
      [0] = { "#39FF14", 46 },
      [1] = { "#00FFFF", 14 },
      [2] = { "#FF1493", 199 },
      [3] = { "#BF00FF", 129 },
      [4] = { "#FF0000", 196 },
    },
  },

  shake = {
    mode = "none",
    interval = 1,
    magnitude = nil,
    restore_delay = 50,
  },

  fire_wall = {
    mode = "none",        -- "none" | "ember_rise" | "fire_columns" | "inferno"
  },

  engine = {
    fps = 25,
    stop_delay = 2000,
  },
}

-- The resolved configuration
M.config = vim.deepcopy(defaults)

--- Read vim global variables and merge into a table
local function read_vim_globals()
  local g = {}
  local mappings = {
    { "g:power_mode_auto_enable", { "auto_enable" } },
    { "g:power_mode_particle_preset", { "particles", "preset" } },
    { "g:power_mode_particle_cancel_on_new", { "particles", "cancel_on_new" } },
    { "g:power_mode_particle_cancel_fadeout_ms", { "particles", "cancel_fadeout_ms" } },
    { "g:power_mode_particle_pool_size", { "particles", "pool_size" } },
    { "g:power_mode_particle_max_particles", { "particles", "max_particles" } },
    { "g:power_mode_particle_avoid_cursor", { "particles", "avoid_cursor" } },
    { "g:power_mode_particle_gravity", { "particles", "gravity" } },
    { "g:power_mode_particle_drag", { "particles", "drag" } },
    { "g:power_mode_particle_upward_bias", { "particles", "upward_bias" } },
    { "g:power_mode_backspace_enabled", { "backspace", "enabled" } },
    { "g:power_mode_backspace_preset", { "backspace", "preset" } },
    { "g:power_mode_combo_enabled", { "combo", "enabled" } },
    { "g:power_mode_combo_position", { "combo", "position" } },
    { "g:power_mode_combo_timeout", { "combo", "timeout" } },
    { "g:power_mode_shake_mode", { "shake", "mode" } },
    { "g:power_mode_shake_interval", { "shake", "interval" } },
    { "g:power_mode_shake_restore_delay", { "shake", "restore_delay" } },
    { "g:power_mode_fire_wall_mode", { "fire_wall", "mode" } },
    { "g:power_mode_engine_fps", { "engine", "fps" } },
    { "g:power_mode_engine_stop_delay", { "engine", "stop_delay" } },
  }

  for _, mapping in ipairs(mappings) do
    local var_name = mapping[1]:gsub("g:", "")
    local val = vim.g[var_name]
    if val ~= nil then
      -- Navigate the nested path and set value
      local tbl = g
      local path = mapping[2]
      for i = 1, #path - 1 do
        tbl[path[i]] = tbl[path[i]] or {}
        tbl = tbl[path[i]]
      end
      -- Convert 0/1 to boolean for boolean fields
      if type(val) == "number" and (val == 0 or val == 1) then
        local key = path[#path]
        if key == "auto_enable" or key == "cancel_on_new"
          or key == "avoid_cursor" or key == "enabled"
          or key == "shake" then
          val = val == 1
        end
      end
      tbl[path[#path]] = val
    end
  end

  -- Color overrides: g:power_mode_color_1 through g:power_mode_color_8
  for i = 1, 8 do
    local val = vim.g["power_mode_color_" .. i]
    if val and type(val) == "string" then
      g.colors = g.colors or {}
      -- Simple hex override replaces fg only
      local key = "color_" .. i
      local existing = defaults.colors[key]
      g.colors[key] = { val, existing[2], existing[3], existing[4] }
    end
  end

  return g
end

--- Validate configuration values
local function validate(cfg)
  local p = cfg.particles
  if p.preset and type(p.preset) ~= "string" then
    vim.notify("[power-mode] particles.preset must be a string", vim.log.levels.WARN)
    p.preset = defaults.particles.preset
  end
  if p.pool_size and (p.pool_size < 10 or p.pool_size > 500) then
    vim.notify("[power-mode] particles.pool_size must be 10-500", vim.log.levels.WARN)
    p.pool_size = defaults.particles.pool_size
  end
  if p.max_particles and (p.max_particles < 10 or p.max_particles > 500) then
    vim.notify("[power-mode] particles.max_particles must be 10-500", vim.log.levels.WARN)
    p.max_particles = defaults.particles.max_particles
  end

  local e = cfg.engine
  if e.fps and (e.fps < 10 or e.fps > 60) then
    vim.notify("[power-mode] engine.fps must be 10-60", vim.log.levels.WARN)
    e.fps = defaults.engine.fps
  end

  local s = cfg.shake
  local valid_modes = { none = true, scroll = true, applescript = true }
  if s.mode and not valid_modes[s.mode] then
    vim.notify("[power-mode] shake.mode must be none/scroll/applescript", vim.log.levels.WARN)
    s.mode = defaults.shake.mode
  end

  local c = cfg.combo
  local valid_positions = {
    ["top-right"] = true, ["top-left"] = true,
    ["bottom-right"] = true, ["bottom-left"] = true,
  }
  if c.position and not valid_positions[c.position] then
    vim.notify("[power-mode] combo.position must be top-right/top-left/bottom-right/bottom-left", vim.log.levels.WARN)
    c.position = defaults.combo.position
  end

  local fw = cfg.fire_wall
  local valid_fw_modes = { none = true, ember_rise = true, fire_columns = true, inferno = true }
  if fw.mode and not valid_fw_modes[fw.mode] then
    vim.notify("[power-mode] fire_wall.mode must be none/ember_rise/fire_columns/inferno", vim.log.levels.WARN)
    fw.mode = defaults.fire_wall.mode
  end

  return cfg
end

--- Resolve configuration: defaults → vim globals → user opts
function M.resolve(user_opts)
  local base = vim.deepcopy(defaults)
  local globals = read_vim_globals()
  local merged = vim.tbl_deep_extend("force", base, globals, user_opts or {})
  M.config = validate(merged)
  return M.config
end

--- Get the current resolved config
function M.get()
  return M.config
end

--- Get defaults (for reference/testing)
function M.get_defaults()
  return vim.deepcopy(defaults)
end

return M
