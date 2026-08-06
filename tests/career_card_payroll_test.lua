-- Standalone: luajit mods/career_card/tests/career_card_payroll_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Payroll = dofile("mods/career_card/payroll.lua")

local CYCLE = 1200   -- 20 minutes
local CAP = Payroll.IDLE_CAP

T.eq(CAP, 30, "the idle cap is 30 seconds")

local function fresh(sample) return { lastSample = sample or 0, accrued = 0 } end

-- ------- nothing accrues without elapsed time

local st = fresh(0)
local due = Payroll.accrue(st, 0, CYCLE, CAP)
T.eq(due, 0, "no time, no payday")
T.eq(st.accrued, 0, "nothing banked")

-- ------- a normal walking step banks its full delta

st = fresh(0)
Payroll.accrue(st, 1, CYCLE, CAP)
T.eq(st.accrued, 1, "one second of walking banks one second")
Payroll.accrue(st, 3, CYCLE, CAP)
T.eq(st.accrued, 3, "deltas accumulate")
T.eq(st.lastSample, 3, "the sample advances to the current playTime")

-- ------- the idle cap is the anti-AFK rule
-- An hour parked with the game open must not pay an hour of stipend.

st = fresh(0)
Payroll.accrue(st, 3600, CYCLE, CAP)
T.eq(st.accrued, CAP, "an hour idle credits only the cap on the next step")
T.eq(st.lastSample, 3600, "the sample still jumps to the real playTime")

-- walking normally is never capped, because steps are seconds apart
st = fresh(0)
for i = 1, 100 do Payroll.accrue(st, i, CYCLE, CAP) end
T.eq(st.accrued, 100, "100 one-second steps bank 100 seconds, uncapped")

-- ------- maturity

st = fresh(0)
st.accrued = CYCLE - 1
due = Payroll.accrue(st, 1, CYCLE, CAP)
T.eq(due, 1, "crossing the cycle pays exactly one payday")
T.eq(st.accrued, 0, "the paid cycle is drained")

-- a long battle can mature several cycles; they pay together, not one each
st = fresh(0)
st.accrued = CYCLE * 3
due = Payroll.accrue(st, 0, CYCLE, CAP)
T.eq(due, 3, "three matured cycles pay at once")
T.eq(st.accrued, 0, "all three are drained")

-- remainder is kept, never rounded away
st = fresh(0)
st.accrued = CYCLE + 500
due = Payroll.accrue(st, 0, CYCLE, CAP)
T.eq(due, 1, "one full cycle matured")
T.eq(st.accrued, 500, "the remainder carries forward")

-- ------- a backward clock (edited save) must not pay or corrupt state

st = fresh(1000)
due = Payroll.accrue(st, 400, CYCLE, CAP)
T.eq(due, 0, "a backward playTime pays nothing")
T.eq(st.accrued, 0, "and banks nothing")
T.eq(st.lastSample, 400, "but resyncs the sample so play resumes normally")

-- ------- missing or junk playTime is inert

st = fresh(0)
T.eq(Payroll.accrue(st, nil, CYCLE, CAP), 0, "a nil playTime pays nothing")
T.eq(st.accrued, 0, "and banks nothing")

-- ------- NaN and Inf playTime must not poison state permanently
-- Before this guard, one bad sample corrupted st.lastSample and st.accrued
-- forever: every later `due` came out NaN, `due > 0` is false, and the
-- player was never paid again with no error. The property that matters is
-- not just "this call pays nothing" but "the NEXT normal call still works".

st = fresh(0)
due = Payroll.accrue(st, 0 / 0, CYCLE, CAP)
T.eq(due, 0, "a NaN playTime pays nothing")
T.eq(st.accrued, 0, "and does not touch accrued")
T.eq(st.lastSample, 0, "and does not touch lastSample")
due = Payroll.accrue(st, 1, CYCLE, CAP)
T.eq(due, 0, "a normal step right after a NaN sample still runs")
T.eq(st.accrued, 1, "and banks its delta normally")

st = fresh(0)
due = Payroll.accrue(st, math.huge, CYCLE, CAP)
T.eq(due, 0, "an infinite playTime pays nothing")
T.eq(st.accrued, 0, "and does not touch accrued")
T.eq(st.lastSample, 0, "and does not touch lastSample")
due = Payroll.accrue(st, 1, CYCLE, CAP)
T.eq(due, 0, "a normal step right after an infinite sample still runs")
T.eq(st.accrued, 1, "and banks its delta normally")

-- a pre-poisoned accrued (e.g. read back from a corrupted save) must heal
-- on the next normal step rather than propagating NaN into every payday
-- from then on
st = fresh(0)
st.accrued = 0 / 0
due = Payroll.accrue(st, 1, CYCLE, CAP)
T.eq(due, 0, "no cycle matures on the step that heals a poisoned accrued")
T.check(st.accrued == st.accrued, "accrued is healed back to a real number")
st.accrued = CYCLE - 1
due = Payroll.accrue(st, 2, CYCLE, CAP)
T.eq(due, 1, "and payday works normally on the very next step")
T.eq(st.accrued, 0, "cleanly drained, like nothing was ever wrong")

-- ------- the money clamp

T.eq(Payroll.credit(0, 100), 100, "a normal credit adds")
T.eq(Payroll.credit(3000, 500), 3500, "credits accumulate")
T.eq(Payroll.credit(999999, 100), 999999, "at the ceiling nothing is added")
T.eq(Payroll.credit(999950, 100), 999999, "a credit past the ceiling is clamped")
T.eq(Payroll.credit(nil, 100), 100, "a nil wallet is treated as empty")
T.eq(Payroll.credit(500, 0), 500, "a zero credit is a no-op")

T.finish("career_card_payroll")
