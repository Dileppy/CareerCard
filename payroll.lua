-- The pay clock.
--
-- save.playTime (src/core/Game.lua:213) accumulates dt every frame while
-- the game runs, including while the player stands still. Paying against
-- it raw would reward leaving the game open, so accrual is sampled per
-- step and capped: ordinary walking credits its full delta because steps
-- are far under IDLE_CAP apart, while an hour parked credits IDLE_CAP.
--
-- The clock therefore measures time played rather than time the process
-- was open.

local Payroll = {}

-- seconds of playTime a single step may credit
Payroll.IDLE_CAP = 30

-- Gen 1 stores money as 3-byte BCD; src/save_convert/GenSave.lua:857
-- clamps on export, so exceeding this would silently lose money when a
-- player converts their save.
Payroll.MONEY_MAX = 999999

-- `x ~= x` is the standard Lua NaN test; `x == math.huge` (or -math.huge)
-- catches infinity. tonumber("nan") and tonumber("inf") both return real
-- numbers in LuaJIT, so a plain finiteness guard is needed before either
-- value touches arithmetic: one NaN playTime sample poisons st.lastSample
-- AND st.accrued forever (every later `due` comes out NaN, `due > 0` is
-- false, and the player is never paid again with no error), and a corrupt
-- `accrued` read back from the save survives the round trip the same way.
local function notFinite(n)
  return n ~= n or n == math.huge or n == -math.huge
end

-- Advances st and returns how many whole cycles matured. st is mutated in
-- place and also returned, so callers can chain or ignore the return.
function Payroll.accrue(st, playTime, cycleSeconds, idleCap)
  idleCap = idleCap or Payroll.IDLE_CAP
  cycleSeconds = cycleSeconds or 1200

  playTime = tonumber(playTime)
  if not playTime then return 0, st end
  if notFinite(playTime) then return 0, st end

  -- heal a poisoned accrued (e.g. read back from a corrupted save) instead
  -- of letting it propagate NaN into every payday from here on
  if notFinite(st.accrued or 0) then st.accrued = 0 end

  local delta = playTime - (st.lastSample or 0)
  -- an explicit "if delta < 0" guard resyncs a backward clock without
  -- paying; nil playTime is already filtered out above by tonumber, so
  -- there is nothing left for a max() to absorb here
  if delta < 0 then delta = 0 end
  if delta > idleCap then delta = idleCap end

  st.lastSample = playTime
  st.accrued = (st.accrued or 0) + delta

  if cycleSeconds <= 0 then return 0, st end

  local due = math.floor(st.accrued / cycleSeconds)
  if due > 0 then
    st.accrued = st.accrued - due * cycleSeconds
  end
  return due, st
end

function Payroll.credit(money, amount)
  money = tonumber(money) or 0
  amount = tonumber(amount) or 0
  local total = money + amount
  if total > Payroll.MONEY_MAX then total = Payroll.MONEY_MAX end
  return total
end

return Payroll
