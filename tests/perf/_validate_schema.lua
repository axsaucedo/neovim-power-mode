-- tests/perf/_validate_schema.lua
-- Validates that a JSON result file has schema_version==1 and contains
-- at least one result with the required stage key. Args via env vars
-- because we're invoked with `nvim -l`.

local PATH  = assert(os.getenv("PM_VAL_PATH"),  "PM_VAL_PATH not set")
local STAGE = os.getenv("PM_VAL_STAGE") or ""

local f = io.open(PATH, "r")
if not f then
  io.stderr:write("MISSING " .. PATH .. "\n")
  os.exit(2)
end
local s = f:read("*a"); f:close()

local ok, j = pcall(vim.json.decode, s)
if not ok or type(j) ~= "table" then
  io.stderr:write("UNPARSEABLE " .. PATH .. "\n")
  os.exit(3)
end

if j.schema_version ~= 1 then
  io.stderr:write("BAD_SCHEMA schema_version=" .. tostring(j.schema_version) .. " in " .. PATH .. "\n")
  os.exit(4)
end

if STAGE ~= "" then
  local found = false
  for _, r in ipairs(j.results or {}) do
    if r.stages and r.stages[STAGE] then found = true; break end
  end
  if not found then
    io.stderr:write("MISSING_STAGE " .. STAGE .. " in " .. PATH .. "\n")
    os.exit(5)
  end
end

io.stdout:write("OK\n")
vim.cmd("qa!")
