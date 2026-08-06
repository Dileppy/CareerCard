-- Career Card: a trainer salary on the in-game playtime clock.
--
-- The heartbeat is world.stepped, not a per-frame update, because the mod
-- API has no update event (see Reference-Events). That choice also buys
-- two things for free: payday text boxes can only appear while the player
-- is walking in the overworld, and a player who is not moving is not being
-- paid.
--
-- Every gameplay decision lives in the five pure modules below (Ladder,
-- Metrics, Rank, Payroll, Options); Notify and Card only render what those
-- modules decide. This file only wires them all to the mod object and owns
-- the save state.

local HIDEOUT_FLAG = "EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI"

return function(mod)
  -- ------- sibling modules
  -- A mod cannot require its own files through package.path, so they are
  -- read through the loader's filesystem and compiled here. Same idiom the
  -- Pokewalker mod uses.

  local function requireFile(rel)
    local source = mod:read(rel)
    if not source then
      mod.log:error("%s missing from %s -- reinstall the mod", rel, mod.path)
      return nil
    end
    local chunk, err = load(source, "@" .. mod.path .. "/" .. rel)
    if not chunk then
      mod.log:error("%s failed to compile: %s", rel, tostring(err))
      return nil
    end
    return chunk()
  end

  local Ladder = requireFile("ladder.lua")
  local Metrics = requireFile("metrics.lua")
  local Rank = requireFile("rank.lua")
  local Payroll = requireFile("payroll.lua")
  local Options = requireFile("options.lua")
  local Notify = requireFile("notify.lua")
  local Card = requireFile("card.lua")

  if not (Ladder and Metrics and Rank and Payroll and Options and Notify and Card) then
    mod.log:error("career_card could not load its own modules; staying inert")
    return
  end

  Metrics.ladder = Ladder
  Rank.ladder = Ladder
  Rank.metrics = Metrics
  Card.metCount = Rank.metCount

  mod.options:define(Options.ROWS)

  local function opt(key) return mod.options:get(key) end

  -- ALLOWANCE is documented as a master switch: with it off, nothing about
  -- career tracking runs. Not just the heartbeat's pay -- the encounter
  -- counter, rank reevaluation and every notification also go inert, so a
  -- disabled mod truly changes nothing rather than quietly still ranking
  -- and popping text boxes behind the player's back.
  local function isEnabled() return opt("enabled") ~= false end

  -- ------- live game handle and derived totals

  local game = nil
  local totals = { badges = 0, species = 0 }
  local badgeIds = {}

  local function computeTotals()
    local badges = mod.content.constants:get("badges")
    badgeIds = Metrics.badgeIds(badges)
    totals.badges = #badgeIds
    if totals.badges == 0 then
      mod.log:warn("constants.badges is empty; the badge gate is disabled")
    end
    local species = 0
    for _ in mod.content.pokemon:each() do species = species + 1 end
    totals.species = species
  end

  -- ------- save state

  local function get(key, default) return mod.save:get(key, default) end
  local function set(key, value) return mod.save:set(key, value) end

  -- ------- credit for play that happened before the mod was installed
  --
  -- No vanilla save records a wild battle count, or a battle count at all
  -- (src/core/SaveData.lua:1429-1470 is the whole schema). A player who
  -- installs this at 40 hours therefore owes the full wild gate on top of
  -- everything they already did, which is why CREDIT PAST exists.
  --
  -- What it grants is an estimate, and it is kept strictly apart from
  -- `wildEncounters` rather than folded into it. That counter only ever
  -- holds battles this mod actually watched end, so it stays true whatever
  -- the option is set to, and switching CREDIT PAST back off removes the
  -- credit cleanly instead of leaving an inflated number behind.
  --
  -- The estimate is measured ONCE, the first time the mod sees a save, so
  -- it reflects play that genuinely predates it. Measuring it later would
  -- quietly fold in progress the mod was already counting properly, and
  -- credit the same battles twice.
  local function measurePastCredit()
    if get("pastCredit") ~= nil then return end
    if not game then return end
    set("pastCredit", Metrics.dexSeen(game.save))
  end

  local function pastCredit()
    if not Options.creditPast(opt) then return 0 end
    return get("pastCredit", 0)
  end

  local function snapshot()
    local save = game and game.save
    return {
      badges = Metrics.badgesEarned(save, badgeIds),
      owned = Metrics.dexOwned(save),
      wild = get("wildEncounters", 0) + pastCredit(),
      forfeited = get("forfeited", {}),
      -- Rank.evaluate needs this to tell "lost a sponsor I held" (drop to
      -- MOM) from "never held that rung" (skip it, keep the lower one).
      -- forfeitGameCorner records the fact directly; see rank.lua.
      heldWhenLost = get("heldWhenLost", {}),
    }
  end

  local function currentRecord()
    return Ladder.get(get("rank", 1)) or Ladder.get(1)
  end

  -- ------- rank evaluation

  local function reevaluate()
    if not game or not isEnabled() then return end
    local was = get("rank", 1)
    local now = Rank.evaluate(snapshot(), totals, Options.gates(opt))
    if now == was then return end
    set("rank", now)
    if now > get("peakRank", 1) then set("peakRank", now) end
    if now > was and opt("notify") ~= false then
      local record = Ladder.get(now)
      Notify.promoted(game, record.title, record.sponsor,
        math.floor(record.stipend * Options.scale(opt)))
    end
  end

  -- ------- the Game Corner shutdown
  -- Beating Giovanni in the Rocket Hideout ends the rank 4 sponsorship
  -- permanently, whether or not the player ever held it.
  --
  -- This is world state, not a payout: the forfeited flag and the
  -- heldWhenLost fact are recorded regardless of ALLOWANCE, so a raid
  -- that happens while the mod is disabled is never silently lost. Only
  -- the notification is gated -- the player should not get a text box for
  -- something that happened while they had the mod off.

  local function forfeitGameCorner()
    local forfeited = get("forfeited", {})
    if forfeited[Ladder.FORFEITABLE] then return end
    forfeited[Ladder.FORFEITABLE] = true
    set("forfeited", forfeited)
    local held = get("rank", 1) == Ladder.FORFEITABLE
    if held then
      local heldWhenLost = get("heldWhenLost", {})
      heldWhenLost[Ladder.FORFEITABLE] = true
      set("heldWhenLost", heldWhenLost)
    end
    reevaluate() -- self-gated: no rank churn while disabled
    if held and isEnabled() and opt("notify") ~= false then
      Notify.lostSponsor(game, Ladder.get(Ladder.FORFEITABLE).sponsor)
    end
  end

  -- ------- reconciling the hideout flag from world state, not just its
  -- transition event
  --
  -- flag.changed (src/script/Flags.lua) fires exactly once, on the actual
  -- transition. Relying on it alone misses the forfeit whenever nothing
  -- is listening at that exact moment: raiding the hideout while
  -- ALLOWANCE is off, installing Career Card on a save that already
  -- cleared the hideout (probably the common case -- players add mods
  -- mid-playthrough), or any save edited, converted or migrated across
  -- the transition. Reconcile from the real flag on every load instead,
  -- before reevaluate() runs, so a stale forfeit can never leak through
  -- as an active GAME CORNER sponsorship.
  --
  -- mod.world materializes lazily and only resolves a live game
  -- (src/mods/Loader.lua), so this has to tolerate not having one yet.
  local function reconcileHideout()
    local ok, flagSet = pcall(function()
      return mod.world and mod.world:getFlag(HIDEOUT_FLAG)
    end)
    if ok and flagSet then forfeitGameCorner() end
  end

  -- ------- the heartbeat

  local function heartbeat()
    if not game or not isEnabled() then return end

    reevaluate()

    local st = { lastSample = get("lastSample", 0), accrued = get("accrued", 0) }
    local due = Payroll.accrue(st, game.save.playTime,
      Options.cycleSeconds(opt), Payroll.IDLE_CAP)
    set("lastSample", st.lastSample)
    set("accrued", st.accrued)
    if due <= 0 then return end

    local record = currentRecord()
    local amount = math.floor(record.stipend * Options.scale(opt) * due)
    if amount <= 0 then return end

    local before = game.save.money or 0
    game.save.money = Payroll.credit(before, amount)
    local paid = game.save.money - before
    if paid <= 0 then return end

    set("lifetimeEarned", get("lifetimeEarned", 0) + paid)
    if opt("notify") ~= false then
      Notify.payday(game, record.sponsor, paid)
    end
  end

  -- ------- subscriptions

  mod.events:on("game.ready", function(ev)
    game = ev.game
    computeTotals()
    -- mod.ui.TextBox, NOT require("src.render.TextBox"). ModUI exposes the
    -- widget toolkit as the supported mod-facing surface and resolves it
    -- lazily (src/ui/ModUI.lua:8-27), so this needs no permission and trips
    -- no undeclared-engine_internals warning. Requiring the module directly
    -- worked, but only because a pcall hid that it was reaching past the
    -- public API for something the public API already offers.
    Notify.pushText = function(g, page)
      if g and g.stack then
        pcall(function()
          g.stack:push(mod.ui.TextBox.new(g, page, function() end))
        end)
      end
    end
    -- resync the sample so time spent before the mod was enabled is not
    -- banked all at once on the first step
    set("lastSample", game.save.playTime or 0)
    measurePastCredit()
    reconcileHideout()
    reevaluate()
  end)

  mod.events:on("save.loaded", function()
    if not game then return end
    set("lastSample", game.save.playTime or 0)
    measurePastCredit()
    reconcileHideout()
    reevaluate()
  end)

  -- ------- the wild battle counter
  --
  -- Credited on battle.ENDED, not battle.started, and only for a win or a
  -- capture. The gate exists to reward engaging with wild POKeMON, and
  -- counting the encounter itself rewarded running away from one: walk into
  -- grass, flee, repeat, and the counter climbed without a single battle
  -- being fought.
  --
  -- battle.ended carries `result` but not `kind`
  -- (src/battle/BattleState.lua:4685), so the kind is remembered from
  -- battle.started, which does carry it. One battle is on screen at a time,
  -- so a single slot is enough; it is cleared on use so an `ended` with no
  -- matching `started` (a battle already running when the mod loaded) can
  -- never credit anything.
  local pendingKind = nil

  mod.events:on("battle.started", function(ev)
    -- kind is the mutated verb: ghost, safari and oldman are scripted
    -- encounters, not random ones (src/battle/BattleState.lua:1424-1431)
    pendingKind = ev.kind
  end)

  mod.events:on("battle.ended", function(ev)
    local kind = pendingKind
    pendingKind = nil
    if not isEnabled() then return end
    if kind ~= "wild" then return end
    -- "win" is the wild POKeMON fainting; "caught" is a successful ball.
    -- "run" covers both the player fleeing and the POKeMON fleeing, and
    -- "lose" is a blackout; neither is engagement worth crediting.
    if ev.result ~= "win" and ev.result ~= "caught" then return end
    set("wildEncounters", get("wildEncounters", 0) + 1)
  end)

  mod.events:on("pokemon.caught", function() reevaluate() end)

  mod.events:on("flag.changed", function(ev)
    if ev.name ~= HIDEOUT_FLAG then return end
    if ev.value then forfeitGameCorner() end
  end)

  mod.events:on("world.stepped", heartbeat)

  -- ------- the inter-mod API, also consumed by card.lua

  mod.exports.rank = function() return get("rank", 1) end
  mod.exports.sponsor = function() return currentRecord().sponsor end
  mod.exports.title = function() return currentRecord().title end
  mod.exports.stipend = function()
    return math.floor(currentRecord().stipend * Options.scale(opt))
  end
  mod.exports.state = function()
    local st = snapshot()
    st.rank = get("rank", 1)
    st.peakRank = get("peakRank", 1)
    st.lifetimeEarned = get("lifetimeEarned", 0)
    st.accrued = get("accrued", 0)
    st.cycleSeconds = Options.cycleSeconds(opt)
    st.totals = totals
    return st
  end
  mod.exports.unmetFor = function(n)
    local record = Ladder.get(n)
    if not record then return {} end
    return Rank.unmetFor(record, snapshot(), totals, Options.gates(opt))
  end
  -- What the player HAS beside what a rung ASKS FOR, per gate. unmetFor
  -- answers "how much further"; this answers "where am I", and is what the
  -- card renders. Nil above the top of the ladder, which is how the ladder
  -- view knows there is no next rung to show a hint for.
  mod.exports.progressFor = function(n)
    local record = Ladder.get(n)
    if not record then return nil end
    local p = Rank.progressFor(record, snapshot(), totals, Options.gates(opt))
    -- How much of the wild total the player did not earn under this mod's
    -- watch. The card says so out loud: an estimate the player opted into is
    -- still an estimate, and a WILD WON row silently inflated by 27 would be
    -- the one number on the card that cannot be trusted.
    p.wild.credited = pastCredit()
    return p
  end
  mod.exports.ladder = Ladder

  Card.install(mod, function() return game end, Ladder)
end
