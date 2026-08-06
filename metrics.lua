-- Reads the player's progress out of a save table, and rewrites the
-- ladder's vanilla-calibrated gates for whatever content is actually
-- loaded.
--
-- Badges live in save.inventory keyed by badge id (or by the record's
-- item field when it names a different key), mirroring
-- src/inventory/Badges.lua. That module is NOT requireable without the
-- engine_internals permission, so the logic is reproduced here against
-- the public constants registry record instead.

local Metrics = {}

-- constantsBadges is the data.constants.badges array: ordered records of
-- { id, name?, icon?, item? } where list position is the badge number
function Metrics.badgeIds(constantsBadges)
  local ids = {}
  if type(constantsBadges) ~= "table" then return ids end
  for _, entry in ipairs(constantsBadges) do
    if type(entry) == "table" and (entry.item or entry.id) then
      ids[#ids + 1] = entry.item or entry.id
    end
  end
  return ids
end

function Metrics.badgesEarned(save, badgeIds)
  local inventory = save and save.inventory
  if type(inventory) ~= "table" or type(badgeIds) ~= "table" then return 0 end
  local n = 0
  for _, key in ipairs(badgeIds) do
    if inventory[key] then n = n + 1 end
  end
  return n
end

function Metrics.dexOwned(save)
  local owned = save and save.pokedex and save.pokedex.owned
  if type(owned) ~= "table" then return 0 end
  local n = 0
  for _ in pairs(owned) do n = n + 1 end
  return n
end

-- Species SEEN, which is the only thing in a vanilla save that carries any
-- record of battles fought before this mod was installed. It is not a wild
-- battle count and cannot be turned into one:
--
--   * it counts a species once, however many times it was met, so a player
--     with 200 wild battles across 27 species reads as 27;
--   * markSeen also fires for a trainer's POKeMON
--     (src/battle/BattleState.lua:709,3228), so some of it is not wild at all;
--   * it says nothing about whether the battle was won, fled or lost.
--
-- The first of those dominates the other two by a wide margin, which is why
-- it is usable as a deliberately conservative floor. It is never used unless
-- the player switches CREDIT PAST on.
function Metrics.dexSeen(save)
  local seen = save and save.pokedex and save.pokedex.seen
  if type(seen) ~= "table" then return 0 end
  local n = 0
  for _ in pairs(seen) do n = n + 1 end
  return n
end

-- Rewrite a gate calibrated against vanillaTotal onto liveTotal. Rounds up
-- so a gate never silently becomes free, and clamps to liveTotal so the
-- mod can never demand more of a thing than the loaded game contains.
--
-- Multiply BEFORE dividing. Dividing first loses precision and then ceil
-- amplifies it into a whole unit: 50/151*151 is 50.000000000000007, which
-- ceils to 51, so the rank 5 dex gate would silently demand 51 species
-- instead of the 50 it is calibrated for. 50*151/151 is exactly 50.
-- Both operands are integers here, so the product is exact in a double
-- until it far exceeds any plausible registry size.
function Metrics.scale(vanillaValue, vanillaTotal, liveTotal)
  vanillaValue = tonumber(vanillaValue) or 0
  vanillaTotal = tonumber(vanillaTotal) or 0
  liveTotal = tonumber(liveTotal) or 0
  if vanillaValue <= 0 or vanillaTotal <= 0 or liveTotal <= 0 then return 0 end
  local scaled = math.ceil(vanillaValue * liveTotal / vanillaTotal)
  if scaled > liveTotal then scaled = liveTotal end
  return scaled
end

-- totals = { badges = n, species = n } read from the live registries
function Metrics.requirements(record, totals)
  local Ladder = Metrics.ladder
  local vanillaBadges = (Ladder and Ladder.VANILLA_BADGES) or 8
  local vanillaSpecies = (Ladder and Ladder.VANILLA_SPECIES) or 151
  totals = totals or {}
  return {
    badges = Metrics.scale(record.badges, vanillaBadges, totals.badges or 0),
    dexOwned = Metrics.scale(record.dexOwned, vanillaSpecies, totals.species or 0),
    -- wild encounters have no registry maximum, so they are never scaled
    wild = record.wild or 0,
  }
end

-- main.lua sets this after loading both modules; the fallbacks above keep
-- a bare dofile in the test suite working without it
Metrics.ladder = nil

return Metrics
