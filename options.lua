-- Option rows and the readers that translate them.
--
-- The readers take a getter function rather than the mod object, so this
-- module stays pure and the suite can drive it with a table.

local Options = {}

Options.ROWS = {
  { key = "enabled", label = "ALLOWANCE", type = "toggle", default = true },
  { key = "cycleMinutes", label = "PAYDAY MINS", type = "number", default = 20,
    min = 1, max = 120 },
  { key = "stipendScale", label = "PAY RATE", type = "choice", default = "100",
    choices = { { "50%", "50" }, { "100%", "100" },
                { "150%", "150" }, { "200%", "200" } } },
  { key = "notify", label = "PAYDAY POPUP", type = "toggle", default = true },
  { key = "requireBadges", label = "NEED BADGES", type = "toggle", default = true },
  { key = "requireDex", label = "NEED DEX", type = "toggle", default = true },
  { key = "requireEncounters", label = "NEED WILD WINS", type = "toggle", default = true },
  -- Off by default, because it is the only number on the card the mod did
  -- not watch happen. See main.lua for what it estimates and why the
  -- estimate cannot be exact.
  { key = "creditPast", label = "CREDIT PAST", type = "toggle", default = false },
}

function Options.gates(get)
  return {
    badges = get("requireBadges") ~= false,
    dex = get("requireDex") ~= false,
    wild = get("requireEncounters") ~= false,
  }
end

-- Unlike every other toggle here, this one defaults OFF, so it is the one
-- switch that must be read as "explicitly true" rather than "not false".
function Options.creditPast(get)
  return get("creditPast") == true
end

-- `tonumber` accepts "nan" and "inf", and NaN defeats every ordinary
-- comparison: `nan <= 0` is false and `not nan` is false, so a plain
-- positivity guard lets it straight through. `x ~= x` is the standard Lua
-- NaN test. This is not theoretical: ManagerState:applyProfile writes
-- profile-supplied option values with no schema validation, so an imported
-- mod list can inject one. A NaN cycle length would make every payday
-- silently stop firing forever, with no error to explain it.
local function positiveOr(value, fallback)
  local number = tonumber(value)
  if not number then return fallback end
  if number ~= number then return fallback end          -- NaN
  if number == math.huge then return fallback end       -- +inf
  if number <= 0 then return fallback end               -- zero, negative, -inf
  return number
end

function Options.cycleSeconds(get)
  local seconds = math.floor(positiveOr(get("cycleMinutes"), 20) * 60)
  -- positiveOr rejects an exact 0, but math.floor can reintroduce it:
  -- math.floor(0.001 * 60) is 0, and Payroll.accrue's `cycleSeconds <= 0`
  -- guard then never pays while `accrued` grows unbounded. Clamp the
  -- floored result, not just the pre-floor value.
  if seconds < 1 then seconds = 1 end
  return seconds
end

function Options.scale(get)
  local scale = positiveOr(get("stipendScale"), 100) / 100
  -- ManagerState:applyProfile writes option values with no schema
  -- validation (see the NaN/Inf note above), so a profile-injected
  -- stipendScale of, say, 100000 would otherwise pay x1000 the intended
  -- stipend. 10x is already generous headroom over the documented 50-200%
  -- range.
  if scale > 10 then scale = 10 end
  return scale
end

return Options
