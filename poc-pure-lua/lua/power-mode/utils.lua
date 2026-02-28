local M = {}

math.randomseed(os.time())

function M.random(min, max)
  return min + math.random() * (max - min)
end

function M.random_int(min, max)
  return math.random(min, max)
end

function M.clamp(value, min, max)
  if value < min then return min end
  if value > max then return max end
  return value
end

function M.lerp(a, b, t)
  return a + (b - a) * t
end

function M.random_choice(list)
  return list[math.random(#list)]
end

function M.get_editor_dimensions()
  return {
    width = vim.o.columns,
    height = vim.o.lines,
  }
end

return M
