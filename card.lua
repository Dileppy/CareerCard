-- The two Career Card screens.
--
-- The Trainer Card is deliberately not extended. src/ui/TrainerCard.lua
-- contains no Runtime call and the engine exposes no ui.trainer_card hook,
-- so the only way in would be overriding the whole screen record, which
-- needs engine_internals and would fight any other Trainer Card mod.
-- A sibling entry in the START menu is the supported route, and is the
-- pattern mods/examples/example_dexnav uses.

local Card = {}

local LADDER = "CareerLadder"
local DETAIL = "CareerDetail"

-- Rungs at or below peakRank show their real title; everything above is
-- masked, so meeting SILPH CO. is a surprise rather than a menu spoiler.
-- A forfeited rung is the one exception: it reads CLOSED the moment it is
-- forfeited, whether or not the player ever reached it. A player who raids
-- the Rocket Hideout before qualifying for rank 4 has peakRank stuck below
-- it, and "4 ???" would promise a promotion that can never be granted.
-- `nextProgress`, when given, is Rank.progressFor for the rung immediately
-- above peak. It draws a met/total hint ("1/3") on that one row only, which
-- is what makes the masked rows legible as something worth selecting. The
-- rows below it are already reached and the rows above it stay fully dark,
-- so the hint spoils nothing: it names no sponsor, title or stipend, only
-- how many of the three requirements the player has already cleared.
function Card.ladderRows(Ladder, state, nextProgress)
  local peak = state.peakRank or 1
  local forfeited = state.forfeited or {}
  local rows = {}
  for n = 1, Ladder.count() do
    local record = Ladder.get(n)
    local label, right
    if forfeited[n] then
      label, right = ("%d CLOSED"):format(n), ""
    elseif n <= peak then
      label, right = ("%d %s"):format(n, record.title), ("¥%d"):format(record.stipend)
    else
      label, right = ("%d ???"):format(n), ""
      if n == peak + 1 and nextProgress then
        local met, total = Card.metCount(nextProgress)
        if total > 0 then right = ("%d/%d"):format(met, total) end
      end
    end
    rows[#rows + 1] = { label = label, right = right, value = n }
  end
  return rows
end

-- Injected by main.lua from rank.lua so this module stays free of siblings.
Card.metCount = function() return 0, 0 end

function Card.formatClock(seconds)
  seconds = math.floor(tonumber(seconds) or 0)
  if seconds < 0 then seconds = 0 end
  return ("%02d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- One gate's row on the progress view: what the player has beside what the
-- rung asks for. A bare shortfall ("25 MORE") was actionable but not
-- legible, because nothing else in the mod ever showed the encounter count
-- it was counting down from.
--
-- `have` is clamped for display only. Wild battles won have no ceiling, and
-- a five-digit count would push the row past the 18-column budget that
-- ListMenu:draw neither wraps nor truncates. Four digits keeps the widest
-- possible row ("WILD WON 9999/9999") at exactly 18.
local function gateRow(label, gate)
  if not gate then return ("%-8s %s"):format(label, "--") end
  if not gate.enabled then return ("%-8s %s"):format(label, "OFF") end
  local have = math.min(math.floor(gate.have or 0), 9999)
  local need = math.min(math.floor(gate.need or 0), 9999)
  return ("%-8s %d/%d"):format(label, have, need)
end

-- Lines for the detail screen. A reached rung reports its terms; an
-- unreached rung reports the player's standing against each of its gates,
-- so a stalled promotion is always legible and always actionable. A
-- forfeited rung is checked before either of those, regardless of peak,
-- because showing its old stipend, sponsor or NEXT PAY would imply a
-- sponsorship that is actually dead.
function Card.detailLines(Ladder, state, n, progress)
  local record = Ladder.get(n)
  local peak = state.peakRank or 1
  local forfeited = state.forfeited or {}
  local lines = {}
  if not record then return lines end

  if forfeited[n] then
    lines[#lines + 1] = record.title
    lines[#lines + 1] = ""
    lines[#lines + 1] = "CLOSED"
    lines[#lines + 1] = "SPONSOR IS GONE"
  elseif n <= peak then
    lines[#lines + 1] = record.title
    lines[#lines + 1] = ""
    -- The sponsor gets its own row. Every other value here is short enough to
    -- sit behind a 9-column label, but sponsor names run to 11 characters
    -- ("GAME CORNER", "PKMN LEAGUE"), and 9 + 11 overflows the 18-column line
    -- budget. ListMenu:draw neither wraps nor truncates, so those two ranks
    -- would visibly run off the screen edge - and one of them is the top rank,
    -- which every finishing player reaches.
    lines[#lines + 1] = "SPONSOR"
    lines[#lines + 1] = ("  %s"):format(record.sponsor)
    lines[#lines + 1] = ("STIPEND  ¥%d"):format(record.stipend)
    lines[#lines + 1] = ("EVERY    %s"):format(
      Card.formatClock(state.cycleSeconds or 1200))
    lines[#lines + 1] = ("EARNED   ¥%d"):format(state.lifetimeEarned or 0)
    local remaining = (state.cycleSeconds or 1200) - (state.accrued or 0)
    lines[#lines + 1] = ("NEXT PAY %s"):format(Card.formatClock(remaining))
  else
    progress = progress or {}
    lines[#lines + 1] = "???"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "YOU / NEEDED"
    lines[#lines + 1] = gateRow("BADGES", progress.badges)
    lines[#lines + 1] = gateRow("OWNED", progress.dexOwned)
    lines[#lines + 1] = gateRow("WILD WON", progress.wild)
    -- CREDIT PAST folds an estimate of pre-install play into the wild total.
    -- Say so on the card. Without this the row is the one number here the
    -- mod did not watch happen, and nothing on screen would admit it.
    local credited = progress.wild and progress.wild.credited or 0
    if progress.wild and progress.wild.enabled and credited > 0 then
      lines[#lines + 1] = ("  (%d CREDITED)"):format(math.min(credited, 9999))
    end
  end
  return lines
end

-- getGame returns the live game handle; mod.exports supplies the state
function Card.install(mod, getGame, Ladder)
  mod.content.screens:register(DETAIL, {
    new = function(game, n)
      local state = mod.exports.state()
      local lines = Card.detailLines(Ladder, state, n, mod.exports.progressFor(n))
      local items = {}
      for _, line in ipairs(lines) do
        items[#items + 1] = { label = line, value = line }
      end
      return mod.ui.ListMenu.new(game, ("RANK %d"):format(n), items, {
        onChoose = function(_, menu) menu:close() end,
      })
    end,
  })

  mod.content.screens:register(LADDER, {
    new = function(game)
      local state = mod.exports.state()
      -- progress for the rung above peak, for the at-a-glance hint. Nil at
      -- the top of the ladder, where there is no next rung to be short of.
      local items = Card.ladderRows(Ladder, state,
        mod.exports.progressFor((state.peakRank or 1) + 1))
      return mod.ui.ListMenu.new(game, "CAREER LADDER", items, {
        pageJump = true,
        -- ListMenu calls onChoose(item, menu) with the ITEM TABLE, not the
        -- item's value (src/ui/ListMenu.lua:175). Reach through to .value or
        -- the detail screen receives a table where it expects a rank number.
        onChoose = function(item)
          mod.ui.push(game, DETAIL, item and item.value)
        end,
      })
    end,
  })

  -- Default hook priority is deliberate. Do NOT raise it to force CAREER into
  -- the root Start menu.
  --
  -- Hooks:wrap sorts links highest-first and calls chain[1] outermost
  -- (src/mods/Hooks.lua:24-26), so a high priority would place this link
  -- OUTSIDE a UI-overhaul mod's link. That looks like a fix when CAREER seems
  -- "missing" under gen1_modern_ui, but the row is not missing: gen1_modern_ui
  -- wraps this same hook at priority 90, identifies non-vanilla rows by object
  -- identity, and moves them into a MOD MENUS submenu on purpose. Its README
  -- documents SELECT to pin any grouped row back onto the root menu.
  -- Outranking it would defeat a documented feature of another mod and start
  -- an arms race no player wins.
  --
  -- The row carries a stable `id` instead. gen1_modern_ui's pinKey() prefers
  -- item.id and falls back to "label:"..label, so a namespaced id keeps a
  -- player's pin alive across any future label change.
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then return out end
    return mod.ui.insertBefore(out, "SAVE", {
      id = "career_card.career",
      label = "CAREER",
      onSelect = function() mod.ui.push(getGame() or game, LADDER) end,
    })
  end)
end

return Card
