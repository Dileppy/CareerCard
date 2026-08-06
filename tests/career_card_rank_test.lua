-- Standalone: luajit mods/career_card/tests/career_card_rank_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Ladder = dofile("mods/career_card/ladder.lua")
local Metrics = dofile("mods/career_card/metrics.lua")
local Rank = dofile("mods/career_card/rank.lua")
Metrics.ladder = Ladder
Rank.metrics = Metrics
Rank.ladder = Ladder

local TOTALS = { badges = 8, species = 151 }
local ALL = { badges = true, dex = true, wild = true }

local function state(badges, owned, wild, extra)
  local st = { badges = badges, owned = owned, wild = wild,
               hideoutCleared = false, forfeited = {} }
  for k, v in pairs(extra or {}) do st[k] = v end
  return st
end

-- ------- the floor

T.eq(Rank.evaluate(state(0, 0, 0), TOTALS, ALL), 1, "a new save is rank 1")
T.eq(Rank.evaluate(state(0, 0, 0), TOTALS, ALL), 1, "rank 1 is never below 1")

-- ------- all three gates are required (AND), at the boundary

T.eq(Rank.evaluate(state(1, 10, 25), TOTALS, ALL), 2, "exactly meeting rank 2 promotes")
T.eq(Rank.evaluate(state(0, 10, 25), TOTALS, ALL), 1, "one badge short blocks rank 2")
T.eq(Rank.evaluate(state(1, 9, 25), TOTALS, ALL), 1, "one owned short blocks rank 2")
T.eq(Rank.evaluate(state(1, 10, 24), TOTALS, ALL), 1, "one encounter short blocks rank 2")

-- ------- the documented stall: maxed badges, short dex
-- Rank 5 needs 6 badges / 50 owned / 190 wild, all of which this state
-- meets; rank 6 needs 60 owned, which it does not. So the player sits at 5
-- with every badge in the game, which is the stall the Career Card exists
-- to explain.

T.eq(Rank.evaluate(state(8, 52, 271), TOTALS, ALL), 5,
  "8 badges but 52 owned stalls at rank 5, short of rank 6's 60")
T.eq(Rank.evaluate(state(8, 60, 260), TOTALS, ALL), 6,
  "meeting every rank 6 gate reaches the top")
T.eq(Rank.evaluate(state(8, 151, 9999), TOTALS, ALL), 6,
  "overshooting never exceeds the top rank")

-- ------- gates are contiguous: you cannot skip a rung you do not qualify for

T.eq(Rank.evaluate(state(4, 35, 120), TOTALS, ALL), 4, "rank 4 exactly")
T.eq(Rank.evaluate(state(6, 50, 190), TOTALS, ALL), 5, "rank 5 exactly")

-- ------- the Game Corner forfeit
-- heldWhenLost records the FACT of having held a rung at the moment it was
-- forfeited (main.lua's forfeitGameCorner sets it). It is not inferred from
-- peakRank, because a peak can rise without ever having held THIS rung --
-- see the regression case at the bottom of this section.

-- Never held it (raided the hideout before qualifying): the rung is simply
-- skipped and BILL keeps paying. Demoting here would cut the player's pay
-- for earning a badge, which reads as a bug.
local neverHeld = state(4, 35, 120, { forfeited = { [4] = true } })
T.eq(Rank.evaluate(neverHeld, TOTALS, ALL), 3,
  "a rung the player never held is skipped, leaving them on BILL")

-- Held it and lost it: MOM catches them, not BILL. This is the beat the
-- whole forfeit mechanic exists for.
local lostIt = state(4, 35, 120,
  { forfeited = { [4] = true }, heldWhenLost = { [4] = true } })
T.eq(Rank.evaluate(lostIt, TOTALS, ALL), 1,
  "losing a sponsor you held drops you to MOM, not to your previous boss")

-- and MOM keeps carrying them until the next sponsor qualifies
local stillOnMom = state(5, 40, 150,
  { forfeited = { [4] = true }, heldWhenLost = { [4] = true } })
T.eq(Rank.evaluate(stillOnMom, TOTALS, ALL), 1,
  "MOM carries them while they are still short of rank 5")

local raidedHigh = state(6, 50, 190,
  { forfeited = { [4] = true }, heldWhenLost = { [4] = true } })
T.eq(Rank.evaluate(raidedHigh, TOTALS, ALL), 5,
  "SILPH CO. picks them up and the forfeited rung never blocks progress")

-- heldWhenLost must not resurrect a forfeited rung the player is still
-- standing on
local exactlyAt = state(4, 35, 120,
  { forfeited = { [4] = true }, heldWhenLost = { [4] = true } })
T.eq(Rank.evaluate(exactlyAt, TOTALS, ALL), 1,
  "a recorded hold on the exact forfeited rung does not restore it")

-- Mom is the floor, never zero, even with rank 4 forfeited and nothing else met
local broke = state(0, 0, 0, { forfeited = { [4] = true } })
T.eq(Rank.evaluate(broke, TOTALS, ALL), 1, "the floor is always rank 1 (MOM)")

-- ------- regression: a stale peakRank must not stand in for the fact
-- Two real paths land here: toggling NEED ENCOUNTS off, reaching rank 5,
-- then toggling it back on; or reaching rank 5 in vanilla, then installing
-- a species-adding mod that rescales the gates downward. Either leaves
-- peakRank high with rank 4 never actually held. The old code inferred
-- "held" from peakRank alone and wrongly demoted these players to MOM.
local rescaled = state(4, 35, 120, { forfeited = { [4] = true }, peakRank = 6 })
T.eq(Rank.evaluate(rescaled, TOTALS, ALL), 3,
  "a high peakRank with no heldWhenLost fact must not demote to MOM")

-- ------- gates can be switched off in options

T.eq(Rank.evaluate(state(1, 0, 0), TOTALS,
  { badges = true, dex = false, wild = false }), 2,
  "disabling the dex and wild gates promotes on badges alone")
T.eq(Rank.evaluate(state(0, 0, 0), TOTALS,
  { badges = false, dex = false, wild = false }), 6,
  "disabling every gate reaches the top rank")

-- ------- unmetFor reports the shortfall for the card

local short = Rank.unmetFor(Ladder.get(6), state(8, 52, 271), TOTALS, ALL)
T.eq(short.badges, nil, "the badge gate is met, so it is not reported")
T.eq(short.dexOwned, 8, "8 more to catch")
T.eq(short.wild, nil, "the wild gate is met, so it is not reported")

local none = Rank.unmetFor(Ladder.get(2), state(8, 60, 300), TOTALS, ALL)
T.eq(none.badges, nil, "a fully met rank reports nothing short")
T.eq(none.dexOwned, nil, "a fully met rank reports nothing short")
T.eq(none.wild, nil, "a fully met rank reports nothing short")

local all = Rank.unmetFor(Ladder.get(6), state(0, 0, 0), TOTALS, ALL)
T.eq(all.badges, 8, "all 8 badges outstanding")
T.eq(all.dexOwned, 60, "all 60 owned outstanding")
T.eq(all.wild, 260, "all 260 encounters outstanding")

-- ------- progressFor reports standing, not just shortfall
-- unmetFor answers "how much further" and drops any gate that is not short.
-- progressFor answers "where am I", and must report every gate in every
-- state, because the card shows all three rows whatever the standing.

local p = Rank.progressFor(Ladder.get(6), state(3, 28, 95), TOTALS, ALL)
T.eq(p.badges.have, 3, "reports the badges held")
T.eq(p.badges.need, 8, "reports the badges required")
T.eq(p.dexOwned.have, 28, "reports the species owned")
T.eq(p.dexOwned.need, 60, "reports the species required")
T.eq(p.wild.have, 95, "reports the encounters seen")
T.eq(p.wild.need, 260, "reports the encounters required")

-- a MET gate is still reported, with its real numbers. unmetFor omits it;
-- the card cannot, or the row would vanish from a three-row view.
local met = Rank.progressFor(Ladder.get(2), state(8, 60, 300), TOTALS, ALL)
T.eq(met.badges.have, 8, "a met gate still reports what the player has")
T.eq(met.badges.need, 1, "a met gate still reports what was required")
T.check(met.wild.have > met.wild.need, "overshoot is reported as it stands")

-- the requirement is the SCALED one, not the raw ladder value, so a mod
-- that changes the species count moves what this reports (see metrics.lua)
local scaled = Rank.progressFor(Ladder.get(6), state(0, 0, 0),
  { badges = 4, species = 302 }, ALL)
T.eq(scaled.badges.need, 4, "the badge requirement rescales to the live total")
T.eq(scaled.dexOwned.need, 120, "the dex requirement rescales to the live total")
T.eq(scaled.wild.need, 260, "the encounter requirement does not rescale")

-- ------- a DISABLED gate is not a MET gate
-- This is the distinction unmetFor structurally cannot express: it omits a
-- disabled gate exactly as it omits a satisfied one, which is what made the
-- card render "DONE" for a switched-off gate at zero progress.

local offBadges = Rank.progressFor(Ladder.get(6), state(0, 0, 0),
  TOTALS, { badges = false, dex = true, wild = true })
T.eq(offBadges.badges.enabled, false, "a switched-off gate reports enabled=false")
T.eq(offBadges.badges.have, 0, "...and still reports the real standing")
T.eq(offBadges.dexOwned.enabled, true, "an untouched gate stays enabled")

local defaults = Rank.progressFor(Ladder.get(6), state(0, 0, 0), TOTALS, {})
T.eq(defaults.badges.enabled, true, "an absent gate switch defaults to on")

-- ------- metCount drives the ladder hint

local function count(...) local m, t = Rank.metCount(...) return m .. "/" .. t end

T.eq(count(Rank.progressFor(Ladder.get(6), state(0, 0, 0), TOTALS, ALL)),
  "0/3", "nothing met")
T.eq(count(Rank.progressFor(Ladder.get(6), state(8, 0, 0), TOTALS, ALL)),
  "1/3", "one of three met")
T.eq(count(Rank.progressFor(Ladder.get(6), state(8, 60, 0), TOTALS, ALL)),
  "2/3", "two of three met")
T.eq(count(Rank.progressFor(Ladder.get(6), state(8, 60, 260), TOTALS, ALL)),
  "3/3", "exactly at every threshold counts as met")
T.eq(count(Rank.progressFor(Ladder.get(6), state(99, 99, 999), TOTALS, ALL)),
  "3/3", "overshoot counts as met, not as more than met")

-- a disabled gate leaves the denominator, so the hint never reads "1/3"
-- for a player who only has two gates left to satisfy
T.eq(count(Rank.progressFor(Ladder.get(6), state(0, 60, 0), TOTALS,
  { badges = false, dex = true, wild = true })),
  "1/2", "a switched-off gate leaves both sides of the count")
T.eq(count(Rank.progressFor(Ladder.get(6), state(0, 0, 0), TOTALS,
  { badges = false, dex = false, wild = false })),
  "0/0", "every gate off leaves nothing to count")

T.finish("career_card_rank")
