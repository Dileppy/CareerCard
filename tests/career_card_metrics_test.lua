-- Standalone: luajit mods/career_card/tests/career_card_metrics_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Ladder = dofile("mods/career_card/ladder.lua")
local Metrics = dofile("mods/career_card/metrics.lua")

-- ------- badge ids come out of the constants registry record

local vanillaBadges = {
  { id = "BOULDERBADGE" }, { id = "CASCADEBADGE" }, { id = "THUNDERBADGE" },
  { id = "RAINBOWBADGE" },  { id = "SOULBADGE" },   { id = "MARSHBADGE" },
  { id = "VOLCANOBADGE" },  { id = "EARTHBADGE" },
}

local ids = Metrics.badgeIds(vanillaBadges)
T.eq(#ids, 8, "eight vanilla badges")
T.eq(ids[1], "BOULDERBADGE", "first badge id")

-- a record may name a different inventory key than its id
T.eq(Metrics.badgeIds({ { id = "X", item = "ITEM_X" } })[1], "ITEM_X",
  "the item field overrides the id when present")

T.eq(#Metrics.badgeIds(nil), 0, "a missing badge list yields no ids")
T.eq(#Metrics.badgeIds({}), 0, "an empty badge list yields no ids")

-- ------- counting what the player actually holds

T.eq(Metrics.badgesEarned({ inventory = {} }, ids), 0, "no badges yet")
T.eq(Metrics.badgesEarned({ inventory = { BOULDERBADGE = 1 } }, ids), 1, "one badge")
T.eq(Metrics.badgesEarned({ inventory = {
  BOULDERBADGE = 1, CASCADEBADGE = 1, EARTHBADGE = 1 } }, ids), 3, "three badges")
T.eq(Metrics.badgesEarned({}, ids), 0, "a save with no inventory counts zero")
T.eq(Metrics.badgesEarned(nil, ids), 0, "a nil save counts zero")

-- items in the bag that are not badges must not count
T.eq(Metrics.badgesEarned({ inventory = { POTION = 5, BOULDERBADGE = 1 } }, ids), 1,
  "non-badge inventory is ignored")

-- ------- dex owned

T.eq(Metrics.dexOwned({ pokedex = { owned = {} } }), 0, "empty dex")
T.eq(Metrics.dexOwned({ pokedex = { owned = { PIKACHU = true, EEVEE = true } } }), 2,
  "two owned")
T.eq(Metrics.dexOwned({}), 0, "a save with no pokedex counts zero")
T.eq(Metrics.dexOwned(nil), 0, "a nil save counts zero")

-- ------- scaling vanilla gates onto live totals
-- This is the whole point: the mod can never ask for more badges than exist.

T.eq(Metrics.scale(4, 8, 8), 4, "identity when the live total matches vanilla")
T.eq(Metrics.scale(8, 8, 8), 8, "the top gate is exactly the full set")
T.eq(Metrics.scale(0, 8, 8), 0, "a zero gate stays zero")
T.eq(Metrics.scale(4, 8, 16), 8, "doubling the badge count doubles the gate")
T.eq(Metrics.scale(8, 8, 4), 4, "halving it never exceeds what exists")
T.eq(Metrics.scale(60, 151, 151), 60, "dex gate identity at 151")
T.eq(Metrics.scale(60, 151, 302), 120, "dex gate doubles at 302 species")

-- rounding up, never down, so a gate never silently becomes free
T.eq(Metrics.scale(1, 8, 9), 2, "a fractional gate rounds up")

-- Identity must be EXACT for every gate the ladder actually uses. Dividing
-- before multiplying makes 50/151*151 = 50.000000000000007, which ceils to
-- 51 and silently moves the rank 5 dex gate. Only the value 50 trips it, so
-- a spot check of one or two gates does not catch it: assert all of them.
for _, gate in ipairs({ 0, 10, 20, 35, 50, 60 }) do
  T.eq(Metrics.scale(gate, 151, 151), gate,
    ("dex gate %d survives identity scaling exactly"):format(gate))
end
for _, gate in ipairs({ 0, 1, 2, 4, 6, 8 }) do
  T.eq(Metrics.scale(gate, 8, 8), gate,
    ("badge gate %d survives identity scaling exactly"):format(gate))
end

-- degenerate inputs must not divide by zero or return nil
T.eq(Metrics.scale(4, 0, 8), 0, "a zero vanilla total yields a zero gate")
T.eq(Metrics.scale(4, 8, 0), 0, "a zero live total yields a zero gate")

-- ------- assembled requirements for a rank record

local totals = { badges = 8, species = 151 }
local req = Metrics.requirements(Ladder.get(6), totals)
T.eq(req.badges, 8, "rank 6 needs all 8 badges")
T.eq(req.dexOwned, 60, "rank 6 needs 60 owned")
T.eq(req.wild, 260, "wild encounters are absolute, never scaled")

local doubled = Metrics.requirements(Ladder.get(6), { badges = 16, species = 302 })
T.eq(doubled.badges, 16, "badge gate follows a doubled badge set")
T.eq(doubled.dexOwned, 120, "dex gate follows a doubled species set")
T.eq(doubled.wild, 260, "the wild gate is unaffected by registry size")

-- ------- dexSeen, the basis of the CREDIT PAST estimate

T.eq(Metrics.dexSeen(nil), 0, "no save counts as nothing seen")
T.eq(Metrics.dexSeen({}), 0, "a save with no pokedex counts as nothing seen")
T.eq(Metrics.dexSeen({ pokedex = {} }), 0, "a pokedex with no seen table is zero")
T.eq(Metrics.dexSeen({ pokedex = { seen = "nope" } }), 0,
  "a non-table seen field is zero, not an error")
T.eq(Metrics.dexSeen({ pokedex = { seen = {} } }), 0, "an empty seen list is zero")
T.eq(Metrics.dexSeen({ pokedex = { seen = { BULBASAUR = true, PIDGEY = true } } }), 2,
  "counts the species present")

-- seen and owned are separate tallies; a species can be seen without being
-- owned, and the estimate is deliberately built on the larger of the two
local mixed = { pokedex = { seen = { A = true, B = true, C = true },
                            owned = { A = true } } }
T.eq(Metrics.dexSeen(mixed), 3, "seen counts every species met")
T.eq(Metrics.dexOwned(mixed), 1, "owned counts only those caught")

T.finish("career_card_metrics")
