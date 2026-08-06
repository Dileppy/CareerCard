-- Standalone: luajit mods/career_card/tests/career_card_ladder_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Ladder = dofile("mods/career_card/ladder.lua")

T.eq(Ladder.count(), 6, "six ranks")
T.eq(Ladder.VANILLA_BADGES, 8, "calibrated against 8 vanilla badges")
T.eq(Ladder.VANILLA_SPECIES, 151, "calibrated against 151 vanilla species")
T.eq(Ladder.FORFEITABLE, 4, "the GAME CORNER rung is the forfeitable one")

-- rank 1 is the floor: Mom, no requirements at all
local one = Ladder.get(1)
T.eq(one.sponsor, "MOM", "rank 1 sponsor is MOM")
T.eq(one.stipend, 100, "rank 1 pays 100")
T.eq(one.badges, 0, "rank 1 needs no badges")
T.eq(one.dexOwned, 0, "rank 1 needs no dex")
T.eq(one.wild, 0, "rank 1 needs no encounters")

T.eq(Ladder.get(4).sponsor, "GAME CORNER", "rank 4 is the GAME CORNER")
T.eq(Ladder.get(6).stipend, 500, "rank 6 pays 500")
T.eq(Ladder.get(7), nil, "there is no rank 7")

-- every field present, and every gate monotonically non-decreasing
local prev = nil
for n = 1, Ladder.count() do
  local r = Ladder.get(n)
  T.eq(r.rank, n, "record " .. n .. " knows its own rank")
  T.check(type(r.title) == "string" and #r.title > 0, "rank " .. n .. " has a title")
  T.check(type(r.sponsor) == "string" and #r.sponsor > 0, "rank " .. n .. " has a sponsor")
  T.check(r.stipend > 0, "rank " .. n .. " pays something")
  T.check(#r.title <= 18, "rank " .. n .. " title fits the text budget")
  T.check(#r.sponsor <= 18, "rank " .. n .. " sponsor fits the text budget")
  if prev then
    T.check(r.stipend > prev.stipend, "rank " .. n .. " pays more than " .. (n - 1))
    T.check(r.badges >= prev.badges, "badge gate never decreases at " .. n)
    T.check(r.dexOwned >= prev.dexOwned, "dex gate never decreases at " .. n)
    T.check(r.wild >= prev.wild, "wild gate never decreases at " .. n)
  end
  prev = r
end

T.check(Ladder.get(6).badges <= Ladder.VANILLA_BADGES,
  "the top rung never asks for more badges than exist")

T.finish("career_card_ladder")
