-- The rank ladder, as data. Nothing here knows about the mod object, the
-- engine, or LOVE, so the suite loads it with a bare dofile.
--
-- Gate values are calibrated against vanilla Red/Blue: 8 badges and 151
-- species. metrics.scale() rewrites them for whatever the loaded game
-- actually has, so a mod that adds species does not break the ladder.

local Ladder = {}

Ladder.VANILLA_BADGES = 8
Ladder.VANILLA_SPECIES = 151

-- rank 4 (GAME CORNER) is forfeited permanently if the player beats
-- Giovanni in the Rocket Hideout before qualifying for it
Ladder.FORFEITABLE = 4

Ladder.RANKS = {
  { rank = 1, title = "DEPENDENT",   sponsor = "MOM",
    stipend = 100, badges = 0, dexOwned = 0,  wild = 0 },
  { rank = 2, title = "FIELD AIDE",  sponsor = "PROF. OAK",
    stipend = 150, badges = 1, dexOwned = 10, wild = 25 },
  { rank = 3, title = "RESEARCHER",  sponsor = "BILL",
    stipend = 200, badges = 2, dexOwned = 20, wild = 60 },
  { rank = 4, title = "HEADLINER",   sponsor = "GAME CORNER",
    stipend = 300, badges = 4, dexOwned = 35, wild = 120 },
  { rank = 5, title = "CONTRACTOR",  sponsor = "SILPH CO.",
    stipend = 400, badges = 6, dexOwned = 50, wild = 190 },
  { rank = 6, title = "ACE TRAINER", sponsor = "PKMN LEAGUE",
    stipend = 500, badges = 8, dexOwned = 60, wild = 260 },
}

function Ladder.get(n)
  return Ladder.RANKS[n]
end

function Ladder.count()
  return #Ladder.RANKS
end

return Ladder
