-- Standalone: luajit mods/career_card/tests/career_card_integration_test.lua
-- Drives the live mod through the runtime bus.
--
-- Everything here is derived from the loaded dataset, never hardcoded to
-- vanilla's 8 badges and 151 species. The fixture dataset carries 3 species
-- and 2 badges, so a test that assumed vanilla totals would assert the wrong
-- thresholds. Deriving is also the honest test of the design: the mod is
-- supposed to track whatever content is actually loaded.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Data = T.fixtures.fresh()

local run = T.sdk.loadMod("mods/career_card", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

-- Exports do NOT hang off the mod record. `run.mod` is `loader.mods[id]`,
-- which Loader.lua:221 builds as `{ manifest = ..., path = ... }` and never
-- adds exports to; the loader keeps them in a separate table
-- (Loader.lua:702,775). The engine's own suite reads them the same way -
-- see tests/modkit/cases/pointer_input.lua:95.
local api = run.loader.exports.career_card
T.check(api ~= nil, "the mod publishes exports")
T.eq(run.mod.exports, nil,
  "exports are NOT on the mod record; read them off run.loader.exports")

-- mod.world materializes on first touch and then MEMOIZES for the rest of
-- the loader's life (src/mods/Loader.lua:746-755): once resolved it never
-- re-resolves, even if run.loader.game changes later. So it has to be
-- pointed at a real game before the very first game.ready below -- that
-- is what first touches it, through reconcileHideout(). One persistent
-- handle, injected the same way src/dev/HotReload.lua:41 does in
-- production, with its .save field repointed at whichever save is "live"
-- before each scenario's game.ready/save.loaded emission.
local worldGame = { data = Data }
run.loader.game = worldGame

-- what this dataset actually contains
local badgeKeys = {}
for _, entry in ipairs(Data.constants.badges or {}) do
  badgeKeys[#badgeKeys + 1] = entry.item or entry.id
end
local speciesIds = {}
for id in pairs(Data.pokemon or {}) do speciesIds[#speciesIds + 1] = id end
table.sort(speciesIds)

T.check(#badgeKeys > 0, "the dataset has at least one badge to earn")
T.check(#speciesIds > 0, "the dataset has at least one species to own")

local save = {
  playTime = 0,
  money = 3000,
  inventory = {},
  pokedex = { seen = {}, owned = {} },
  defeatedTrainers = {},
  modData = {},
}
local game = { save = save, data = Data }
worldGame.save = save
Runtime.emit("game.ready", { game = game })

local function walk(seconds)
  local base = save.playTime
  for i = 1, seconds do
    save.playTime = base + i
    Runtime.emit("world.stepped", { mapId = "FIX_TOWN", x = 5, y = 5 })
  end
end

-- ------- only wild battles the player FINISHES count
--
-- The gate exists to reward engaging with wild POKeMON. Crediting on
-- battle.started rewarded the opposite: walk into grass, flee, repeat, and
-- the counter climbed without a battle ever being fought. Credit lands on
-- battle.ended, and only for a win or a capture.

local function battle(kind, result, extra)
  local started = { kind = kind, species = speciesIds[1], level = 3 }
  for k, v in pairs(extra or {}) do started[k] = v end
  Runtime.emit("battle.started", started)
  Runtime.emit("battle.ended", { result = result })
end

battle("wild", "win")
battle("wild", "caught")
T.eq(api.state().wild, 2, "a wild POKeMON defeated and one caught both count")

-- the behavior this whole change exists to stop
battle("wild", "run")
T.eq(api.state().wild, 2, "running away from a wild POKeMON counts for nothing")
battle("wild", "lose")
T.eq(api.state().wild, 2, "blacking out to a wild POKeMON counts for nothing")

-- "run" is also what the engine records when the POKeMON flees the player
-- (src/battle/BattleState.lua:4276), so a fleeing ABRA is not a free credit
battle("wild", "run")
T.eq(api.state().wild, 2, "a POKeMON that flees is not a win")

-- kind still gates: a won trainer battle is not wild engagement
battle("trainer", "win", { trainerId = "FIX_TRAINER" })
battle("ghost", "win")
battle("oldman", "win")
battle("safari", "caught")
battle("link", "win")
T.eq(api.state().wild, 2, "trainer, ghost, oldman, safari and link never count")

-- battle.started alone credits nothing; the battle has to actually end
Runtime.emit("battle.started", { kind = "wild", species = speciesIds[1] })
T.eq(api.state().wild, 2, "an unfinished battle credits nothing")

-- ...and that dangling `started` must not leak into the NEXT ended event.
-- The kind is remembered in one slot and cleared on use, so an `ended` with
-- no matching `started` (a battle already running when the mod loaded)
-- credits nothing either.
Runtime.emit("battle.ended", { result = "win" })
T.eq(api.state().wild, 3, "the pending battle resolves against its own start")
Runtime.emit("battle.ended", { result = "win" })
T.eq(api.state().wild, 3, "a second ended with no start credits nothing")

-- ------- rank 1 is the floor

T.eq(api.rank(), 1, "a fresh save is rank 1")
T.eq(api.sponsor(), "MOM", "rank 1 sponsor is MOM")
T.eq(api.stipend(), 100, "rank 1 pays 100")

-- ------- the heartbeat pays on the playtime clock

T.eq(save.money, 3000, "no payout before any time has passed")
walk(1200)
T.eq(save.money, 3100, "one matured cycle paid the rank 1 stipend of 100")
T.eq(api.state().lifetimeEarned, 100, "lifetime earnings tracked")

-- ------- standing still does not pay

local before = save.money
save.playTime = save.playTime + 3600      -- an hour parked, then one step
Runtime.emit("world.stepped", { mapId = "FIX_TOWN", x = 5, y = 5 })
T.eq(save.money, before, "an idle hour does not mature a cycle on one step")

-- ------- the badge gate holds on its own
-- Everything except badges is maxed; rank must not move off the floor.

for _, id in ipairs(speciesIds) do save.pokedex.owned[id] = true end
for _ = 1, 300 do battle("wild", "win") end
Runtime.emit("pokemon.caught", { species = speciesIds[1] })
T.eq(api.rank(), 1, "with no badges the player stays on MOM's floor")

-- ------- meeting every gate reaches the top rung

for _, key in ipairs(badgeKeys) do save.inventory[key] = 1 end
Runtime.emit("pokemon.caught", { species = speciesIds[1] })
T.eq(api.rank(), 6, "all badges, all species and 300 encounters reaches rank 6")
T.eq(api.sponsor(), "PKMN LEAGUE", "rank 6 sponsor is PKMN LEAGUE")
T.eq(api.state().peakRank, 6, "peak rank recorded")

-- the raise takes effect on the next payday
before = save.money
walk(1200)
T.eq(save.money - before, 500, "the next payday pays the rank 6 stipend")

-- ------- the money clamp holds through the live path

save.money = 999950
before = save.money
walk(1200)
T.eq(save.money, 999999, "a payday past the ceiling clamps to 999999")

-- ------- the GAME CORNER collapse, driven through the live flag event
-- The rank suite proves the rule in isolation. This proves main.lua's
-- flag.changed -> forfeitGameCorner wiring actually reaches it, and that the
-- held-check runs before reevaluate mutates the stored rank.
-- A fresh save, because the state accumulated above would mask the drop.

local save2 = {
  playTime = 0, money = 3000, inventory = {},
  pokedex = { seen = {}, owned = {} },
  defeatedTrainers = {}, modData = {},
}

-- Emitting game.ready is NOT enough to get a fresh save's mod state. mod.save
-- reads and writes loader.modSave (src/mods/Loader.lua:140,645-660), and the
-- only thing that binds a save's own modData to it is one line inside
-- Game:adoptSave:
--     loader.modSave = save.modData        (src/core/Game.lua:999)
-- The headless SDK never constructs a Game, so that line never runs and every
-- key set earlier in this suite would leak into the scenario below. Do exactly
-- what adopting a save does in production.
run.loader.modSave = save2.modData
worldGame.save = save2

Runtime.emit("game.ready", { game = { save = save2, data = Data } })

-- climb to exactly rank 4: one badge, one species, and enough encounters.
-- Gates are scaled to the loaded dataset, so assert the rank rather than
-- assuming which raw numbers produce it.
save2.inventory[badgeKeys[1]] = 1
save2.pokedex.owned[speciesIds[1]] = true
for _ = 1, 120 do battle("wild", "win") end
Runtime.emit("pokemon.caught", { species = speciesIds[1] })
T.eq(api.rank(), 4, "reached the GAME CORNER rung")
T.eq(api.sponsor(), "GAME CORNER", "and it is the one paying")

-- raid the hideout beneath it
Runtime.emit("flag.changed",
  { name = "EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI", value = true })

T.eq(api.rank(), 1, "losing a sponsor you held drops you to the floor")
T.eq(api.sponsor(), "MOM", "and MOM is the one who catches you")
T.eq(api.stipend(), 100, "paying her stipend, not the GAME CORNER's")
T.eq(api.state().peakRank, 4, "peakRank remembers the rung despite the drop")

-- MOM keeps paying while the player is stranded
before = save2.money
local base2 = save2.playTime
for i = 1, 1200 do
  save2.playTime = base2 + i
  Runtime.emit("world.stepped", { mapId = "FIX_TOWN", x = 1, y = 1 })
end
T.eq(save2.money - before, 100, "MOM's stipend actually arrives")

-- until the next sponsor qualifies
for _, key in ipairs(badgeKeys) do save2.inventory[key] = 1 end
for _, id in ipairs(speciesIds) do save2.pokedex.owned[id] = true end
for _ = 1, 200 do battle("wild", "win") end
Runtime.emit("pokemon.caught", { species = speciesIds[1] })
T.check(api.rank() > 1, "a later sponsor eventually picks the player up")
T.neq(api.sponsor(), "GAME CORNER", "and it is never the collapsed one")

-- ------- ALLOWANCE is the master switch: everything is inert while off
-- README calls it a master switch. Before this fix, only the heartbeat's
-- pay respected it -- the encounter counter, rank reevaluation and every
-- notification kept running regardless. Prove a disabled mod changes
-- nothing: not money, not rank, not the encounter counter, not the
-- forfeit flag, even after a full cycle's worth of play and a hideout raid.

local save3 = {
  playTime = 0, money = 3000, inventory = {},
  pokedex = { seen = {}, owned = {} },
  defeatedTrainers = {}, modData = {},
}
run.loader.modSave = save3.modData
run.loader.modOptions.career_card = { enabled = false }
worldGame.save = save3

Runtime.emit("game.ready", { game = { save = save3, data = Data } })

local base3 = save3.playTime
for i = 1, 1200 do
  save3.playTime = base3 + i
  Runtime.emit("world.stepped", { mapId = "FIX_TOWN", x = 5, y = 5 })
end
for _ = 1, 300 do battle("wild", "win") end
for _, key in ipairs(badgeKeys) do save3.inventory[key] = 1 end
for _, id in ipairs(speciesIds) do save3.pokedex.owned[id] = true end
Runtime.emit("pokemon.caught", { species = speciesIds[1] })
Runtime.emit("flag.changed",
  { name = "EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI", value = true })

T.eq(save3.money, 3000, "a disabled mod pays nothing even after a full cycle")
T.eq(api.rank(), 1, "a disabled mod never re-evaluates rank")
T.eq(api.state().wild, 0, "a disabled mod never counts encounters")

-- re-enabling picks back up from the real, unmodified save data. Because
-- wild encounters were never counted while disabled, the wild gate is
-- still unmet even though every badge and every species is now owned --
-- proof the counter really was inert the whole time, not just under-reported.
run.loader.modOptions.career_card.enabled = true
Runtime.emit("pokemon.caught", { species = speciesIds[1] })
T.eq(api.rank(), 1,
  "re-enabling shows the encounters truly were never counted while off")

-- ------- reconciling the hideout flag from world state, not just its event
-- flag.changed fires exactly once, on the transition. These scenarios
-- drive the flag through save.flags directly (Flags.lua's own storage
-- shape: save.flags[name] = true) and through mod.world:getFlag, which is
-- what reconcileHideout() actually calls in production -- see the
-- worldGame setup above for how mod.world is routed at each save in this
-- headless SDK.

-- (a) the flag is ALREADY set when the mod first sees the save (e.g. the
-- player cleared the hideout before ever installing Career Card -- the
-- common case, since players add mods mid-playthrough), and the player is
-- short of rank 4. They must not be demoted -- there is nothing to demote
-- FROM -- and once their stats reach what would be rank 4's gates, the
-- CLOSED rung must be skipped, not granted.

local save4 = {
  playTime = 0, money = 3000, inventory = {},
  pokedex = { seen = {}, owned = {} },
  defeatedTrainers = {}, modData = {},
  flags = { EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI = true },
}
run.loader.modSave = save4.modData
worldGame.save = save4

Runtime.emit("game.ready", { game = { save = save4, data = Data } })

T.eq(api.state().forfeited[4], true,
  "the flag reconciles into the forfeited fact right on game.ready")
T.eq(api.state().heldWhenLost[4], nil,
  "never held it (rank was never 4), so heldWhenLost stays unset")
T.eq(api.rank(), 1, "nothing to demote from -- still the floor")

-- climb to exactly the stats that would reach rank 4 (same recipe as the
-- live-flag scenario above, which reaches rank 4 exactly with this dataset)
save4.inventory[badgeKeys[1]] = 1
save4.pokedex.owned[speciesIds[1]] = true
for _ = 1, 120 do battle("wild", "win") end
Runtime.emit("pokemon.caught", { species = speciesIds[1] })
T.eq(api.rank(), 3, "gates that would reach the already-CLOSED rung stay on BILL instead")
T.eq(api.sponsor(), "BILL", "BILL keeps paying; the rung was never granted")

-- (b) the player was ALREADY at rank 4 (a real, currently-paying GAME
-- CORNER sponsorship) when the flag transition is missed by flag.changed
-- -- a save edited, converted or migrated across it, or any other path
-- that bypasses the live event -- and only caught on the next reconcile.

local save5 = {
  playTime = 0, money = 3000, inventory = {},
  pokedex = { seen = {}, owned = {} },
  defeatedTrainers = {}, modData = {}, flags = {},
}
run.loader.modSave = save5.modData
worldGame.save = save5

Runtime.emit("game.ready", { game = { save = save5, data = Data } })

-- climb to rank 4 legitimately; the flag is still clear, so this is a
-- real, currently-paying sponsorship, not a reconciled skip
save5.inventory[badgeKeys[1]] = 1
save5.pokedex.owned[speciesIds[1]] = true
for _ = 1, 120 do battle("wild", "win") end
Runtime.emit("pokemon.caught", { species = speciesIds[1] })
T.eq(api.rank(), 4, "legitimately reached the GAME CORNER rung")
T.eq(api.sponsor(), "GAME CORNER", "and it is really paying, flag still clear")

-- the flag flips WITHOUT flag.changed firing
save5.flags.EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI = true
T.eq(api.rank(), 4, "a missed transition does not demote by itself")

-- caught on the next reconcile point (a save reload)
Runtime.emit("save.loaded", {})

T.eq(api.rank(), 1, "save.loaded reconciles the missed transition and demotes to MOM")
T.eq(api.sponsor(), "MOM", "MOM catches them, exactly as the live event would have")
T.eq(api.state().forfeited[4], true, "the forfeit fact is recorded")
T.eq(api.state().heldWhenLost[4], true,
  "heldWhenLost is recorded too, since they truly held it")

-- (c) raiding the hideout while ALLOWANCE is off must not lose the fact.
-- Concern from the review: forfeitGameCorner used to be gated entirely by
-- isEnabled(), so a raid during a disabled period was silently lost --
-- re-enabling kept paying the GAME CORNER's stipend forever. The write is
-- now ungated; only the payout and the notification are gated.

local save6 = {
  playTime = 0, money = 3000, inventory = {},
  pokedex = { seen = {}, owned = {} },
  defeatedTrainers = {}, modData = {}, flags = {},
}
run.loader.modSave = save6.modData
worldGame.save = save6

Runtime.emit("game.ready", { game = { save = save6, data = Data } })

save6.inventory[badgeKeys[1]] = 1
save6.pokedex.owned[speciesIds[1]] = true
for _ = 1, 120 do battle("wild", "win") end
Runtime.emit("pokemon.caught", { species = speciesIds[1] })
T.eq(api.rank(), 4, "reached the GAME CORNER rung before disabling")

-- turn ALLOWANCE off, then raid the hideout through the live event
run.loader.modOptions.career_card.enabled = false
Runtime.emit("flag.changed",
  { name = "EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI", value = true })

-- nothing visible changes while disabled...
T.eq(api.rank(), 4, "rank does not visibly churn while disabled")
T.eq(save6.money, 3000, "no pay happens while disabled")

-- ...but the fact is recorded, not lost
T.eq(api.state().forfeited[4], true,
  "the forfeit is recorded even though ALLOWANCE was off")
T.eq(api.state().heldWhenLost[4], true,
  "heldWhenLost is recorded too, since they really held it")

-- re-enabling reflects the fact that was quietly recorded all along
run.loader.modOptions.career_card.enabled = true
Runtime.emit("pokemon.caught", { species = speciesIds[1] })
T.eq(api.rank(), 1, "re-enabling demotes to MOM using the fact recorded while off")
T.eq(api.sponsor(), "MOM", "and MOM is the one who catches them")

-- ------- progressFor, across the seam
-- card.lua renders straight off this export, so the shape has to survive the
-- trip through main.lua's snapshot() and Options.gates(), not just rank.lua's
-- unit tests.

local prog = api.progressFor(2)
T.check(type(prog) == "table", "progressFor returns a table for a real rung")
for _, key in ipairs({ "badges", "dexOwned", "wild" }) do
  T.check(type(prog[key]) == "table", key .. " is reported")
  T.eq(type(prog[key].have), "number", key .. ".have is a number")
  T.eq(type(prog[key].need), "number", key .. ".need is a number")
  T.eq(type(prog[key].enabled), "boolean", key .. ".enabled is a boolean")
end
T.eq(prog.badges.have, api.state().badges,
  "the badge standing matches the live snapshot, not a stale copy")
T.eq(prog.wild.have, api.state().wild,
  "the encounter standing matches the live snapshot")

-- the ladder view asks for peak+1, which at the top of the ladder is off the
-- end. That must be nil rather than an error: it is how ladderRows knows to
-- draw no hint.
T.eq(api.progressFor(api.ladder.count() + 1), nil,
  "progressFor past the top of the ladder is nil, not an error")
T.eq(api.progressFor(0), nil, "progressFor below the ladder is nil too")

-- a switched-off gate reaches the card as enabled=false, which is what stops
-- it rendering as DONE at zero progress
run.loader.modOptions.career_card.requireBadges = false
T.eq(api.progressFor(2).badges.enabled, false,
  "switching NEED BADGES off reaches progressFor")
T.eq(api.progressFor(2).dexOwned.enabled, true,
  "and leaves the other gates alone")
run.loader.modOptions.career_card.requireBadges = true

-- ------- CREDIT PAST
--
-- No vanilla save records a wild battle count, so a player installing this
-- mid-playthrough starts the wild gate at zero however long they have
-- played. CREDIT PAST grants an estimate from the POKeDEX. Three things
-- have to hold, and none of them is obvious from the code alone: the credit
-- must be reversible, the underlying counter must stay honest, and the
-- estimate must be taken ONCE so it never folds in play the mod already
-- counted properly.

local save3 = {
  playTime = 0, money = 3000, inventory = {},
  -- a save that predates the mod: species already seen, none of it watched
  pokedex = { seen = {}, owned = {} },
  defeatedTrainers = {}, modData = {},
}
for _, id in ipairs(speciesIds) do save3.pokedex.seen[id] = true end
local seenCount = #speciesIds

run.loader.modSave = save3.modData      -- what Game:adoptSave does
worldGame.save = save3
run.loader.modOptions.career_card.enabled = true
run.loader.modOptions.career_card.creditPast = false
Runtime.emit("game.ready", { game = { save = save3, data = Data } })

T.eq(api.state().wild, 0, "with CREDIT PAST off, a fresh install starts at zero")

run.loader.modOptions.career_card.creditPast = true
T.eq(api.state().wild, seenCount,
  "switching CREDIT PAST on grants the POKeDEX estimate")

-- reversible: the option is a live modifier, not a one-way grant
run.loader.modOptions.career_card.creditPast = false
T.eq(api.state().wild, 0, "switching it back off removes the credit cleanly")

-- the underlying counter never absorbs the estimate, so it stays true
-- whatever the option is set to
run.loader.modOptions.career_card.creditPast = true
battle("wild", "win")
battle("wild", "win")
T.eq(api.state().wild, seenCount + 2, "real wins stack on top of the credit")
run.loader.modOptions.career_card.creditPast = false
T.eq(api.state().wild, 2,
  "and turning the credit off leaves exactly the wins the mod watched")

-- measured ONCE. Seeing more species after install must not raise the
-- credit, or the same battles would be counted twice: once as the win the
-- mod watched, and again as a bigger estimate.
for i = 1, #speciesIds do save3.pokedex.seen["EXTRA_" .. i] = true end
Runtime.emit("save.loaded", {})
run.loader.modOptions.career_card.creditPast = true
T.eq(api.state().wild, seenCount + 2,
  "the estimate is not re-measured as the POKeDEX grows")
run.loader.modOptions.career_card.creditPast = false

-- ...and it really is the wild gate it moves, not the display alone
run.loader.modOptions.career_card.creditPast = true
T.check(api.progressFor(2).wild.have >= seenCount,
  "the credit reaches the promotion gate, not just the card")
T.eq(api.progressFor(2).wild.credited, seenCount,
  "and the card is told how much of the total was credited, not earned")
run.loader.modOptions.career_card.creditPast = false
T.eq(api.progressFor(2).wild.credited, 0,
  "with the option off, nothing is reported as credited")

run.release()
T.finish("career_card_integration")
