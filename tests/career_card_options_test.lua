-- Standalone: luajit mods/career_card/tests/career_card_options_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Options = dofile("mods/career_card/options.lua")

-- ------- row shape matches what mod.options:define expects

local byKey = {}
for _, row in ipairs(Options.ROWS) do
  T.check(type(row.key) == "string" and #row.key > 0, "every row has a key")
  T.check(type(row.label) == "string" and #row.label > 0, "every row has a label")
  T.check(row.type == "toggle" or row.type == "choice" or row.type == "number",
    "row " .. row.key .. " has a supported type")
  T.check(row.default ~= nil, "row " .. row.key .. " has a default")
  T.check(byKey[row.key] == nil, "no duplicate key: " .. row.key)
  byKey[row.key] = row
end

T.check(byKey.enabled ~= nil, "there is a master switch")
T.eq(byKey.enabled.default, true, "the mod is on by default")
T.eq(byKey.cycleMinutes.default, 20, "the default cycle is 20 minutes")
T.eq(byKey.notify.default, true, "payday notifications are on by default")
T.eq(byKey.requireBadges.default, true, "the badge gate is on by default")
T.eq(byKey.requireDex.default, true, "the dex gate is on by default")
T.eq(byKey.requireEncounters.default, true, "the wild gate is on by default")

-- ------- readers translate option values into what rank/payroll want

local function getter(values)
  return function(key) return values[key] end
end

local gates = Options.gates(getter({
  requireBadges = true, requireDex = true, requireEncounters = true }))
T.eq(gates.badges, true, "badge gate on")
T.eq(gates.dex, true, "dex gate on")
T.eq(gates.wild, true, "wild gate on")

gates = Options.gates(getter({
  requireBadges = true, requireDex = false, requireEncounters = false }))
T.eq(gates.badges, true, "badge gate still on")
T.eq(gates.dex, false, "dex gate off")
T.eq(gates.wild, false, "wild gate off")

T.eq(Options.cycleSeconds(getter({ cycleMinutes = 20 })), 1200, "20 minutes is 1200s")
T.eq(Options.cycleSeconds(getter({ cycleMinutes = 5 })), 300, "5 minutes is 300s")
T.eq(Options.cycleSeconds(getter({})), 1200, "a missing value falls back to 20 minutes")
T.eq(Options.cycleSeconds(getter({ cycleMinutes = 0 })), 1200,
  "zero is refused; it would divide by zero")
T.eq(Options.cycleSeconds(getter({ cycleMinutes = -5 })), 1200, "negatives are refused")

T.eq(Options.scale(getter({ stipendScale = "100" })), 1.0, "100 percent is 1.0")
T.eq(Options.scale(getter({ stipendScale = "50" })), 0.5, "50 percent is 0.5")
T.eq(Options.scale(getter({ stipendScale = "200" })), 2.0, "200 percent is 2.0")
T.eq(Options.scale(getter({})), 1.0, "a missing scale falls back to 1.0")

-- ------- values tonumber accepts but arithmetic cannot survive
-- `tonumber("nan")` is a real number in LuaJIT, and NaN defeats ordinary
-- comparisons: `nan <= 0` is false, so a plain positivity guard passes it
-- through. A NaN cycle length makes every payday stop firing, silently and
-- permanently. ManagerState:applyProfile writes option values with no schema
-- validation, so an imported mod list can inject one.
for _, poison in ipairs({ "nan", "inf", "-inf", "abc", "" }) do
  T.eq(Options.cycleSeconds(getter({ cycleMinutes = poison })), 1200,
    ("cycleMinutes=%q falls back to 20 minutes"):format(poison))
  T.eq(Options.scale(getter({ stipendScale = poison })), 1.0,
    ("stipendScale=%q falls back to 1.0"):format(poison))
end

-- and the results must be usable arithmetic, not just non-nil
local seconds = Options.cycleSeconds(getter({ cycleMinutes = "nan" }))
T.check(seconds == seconds, "the fallback cycle length is not NaN")
T.check(seconds ~= math.huge, "the fallback cycle length is finite")
T.check(math.floor(600 / seconds) == 0, "and it divides sanely")

-- ------- math.floor must not reintroduce the zero positiveOr rejects
-- positiveOr(0.001, ...) passes 0.001 through (it is > 0), but
-- math.floor(0.001 * 60) is 0, and Payroll.accrue's `cycleSeconds <= 0`
-- guard would then never pay while accrued grows unbounded.
T.eq(Options.cycleSeconds(getter({ cycleMinutes = 0.001 })), 1,
  "a floored-to-zero cycle length still returns at least 1 second")
T.check(Options.cycleSeconds(getter({ cycleMinutes = 0.001 })) > 0,
  "and it is never zero or negative")

-- ------- Options.scale is capped so a profile-injected garbage value
-- cannot pay out an absurd multiple of the intended stipend
T.eq(Options.scale(getter({ stipendScale = "100000" })), 10,
  "an injected scale of 100000 is capped at 10x, not x1000")
T.eq(Options.scale(getter({ stipendScale = "1000" })), 10,
  "a scale over the cap clamps to 10x")
T.eq(Options.scale(getter({ stipendScale = "200" })), 2.0,
  "a normal in-range scale is unaffected by the cap")

-- ------- CREDIT PAST is the one toggle that defaults OFF
-- Every other switch here is read as "not false", which treats an unset key
-- as on. This one grants an estimate the mod never watched happen, so it
-- has to be read as "explicitly true" or an untouched save would silently
-- receive the credit.

T.eq(Options.creditPast(getter({})), false,
  "an unset CREDIT PAST is off, not on")
T.eq(Options.creditPast(getter({ creditPast = nil })), false,
  "an explicit nil is off")
T.eq(Options.creditPast(getter({ creditPast = false })), false,
  "false is off")
T.eq(Options.creditPast(getter({ creditPast = true })), true,
  "true is on")
-- a profile can write anything (see the NaN note above); only a real
-- boolean true may switch this on
T.eq(Options.creditPast(getter({ creditPast = "true" })), false,
  "the string \"true\" does not switch it on")
T.eq(Options.creditPast(getter({ creditPast = 1 })), false,
  "a truthy non-boolean does not switch it on")

local creditRow
for _, row in ipairs(Options.ROWS) do
  if row.key == "creditPast" then creditRow = row end
end
T.check(creditRow ~= nil, "CREDIT PAST is an actual option row")
T.eq(creditRow.default, false, "...and its declared default is off")
T.eq(creditRow.type, "toggle", "...and it is a toggle")

T.finish("career_card_options")
