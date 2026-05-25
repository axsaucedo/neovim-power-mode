-- tests/perf/_validate_repro.lua
-- Reads two hotspots result files and checks p50_ms of FULL_frame
-- for the (single) scenario is within ±15% of their median.

local A = assert(os.getenv("PM_REPRO_A"), "PM_REPRO_A")
local B = assert(os.getenv("PM_REPRO_B"), "PM_REPRO_B")
local BAND = tonumber(os.getenv("PM_REPRO_BAND") or "0.15")

local function p50(path)
  local s = io.open(path, "r"):read("*a")
  local j = vim.json.decode(s)
  for _, r in ipairs(j.results) do
    if r.stages.FULL_frame then return r.stages.FULL_frame.p50_ms end
  end
  return 0
end

local pa, pb = p50(A), p50(B)
local med = (pa + pb) / 2
if med <= 0 then
  io.stdout:write("FAIL zero median\n"); os.exit(1)
end
local dev_a = math.abs(pa - med) / med
local dev_b = math.abs(pb - med) / med
io.stdout:write(string.format("pa=%.4fms pb=%.4fms dev_a=%.3f dev_b=%.3f band=%.2f\n",
  pa, pb, dev_a, dev_b, BAND))
if dev_a <= BAND and dev_b <= BAND then
  io.stdout:write("PASS\n")
  vim.cmd("qa!")
else
  io.stdout:write("FAIL band exceeded\n")
  os.exit(1)
end
