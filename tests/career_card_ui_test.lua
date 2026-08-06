-- Standalone: luajit mods/career_card/tests/career_card_ui_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
-- fixtures.fresh(), not Data:load(); see the note in the load suite.
local Data = T.fixtures.fresh()

local run = T.sdk.loadMod("mods/career_card", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

-- ------- both screens registered into the merged view
-- Read through run.data rather than a captured local: the loader merges
-- into the dataset it was handed, and the fixture dataset has no screens
-- table until a mod registers the first one.

local screens = run.data.screens or {}
T.check(screens.CareerLadder ~= nil, "the ladder screen is registered")
T.check(screens.CareerDetail ~= nil, "the detail screen is registered")

-- ------- the Start menu gains exactly one row, anchored before SAVE

local vanilla = { { label = "POKeDEX" }, { label = "POKeMON" },
                  { label = "ITEM" }, { label = "SAVE" }, { label = "OPTION" } }

-- The hook chain threads ONE table reference through every link
-- (src/mods/Hooks.lua) and ModUI.insertBefore mutates in place and returns
-- the same table (src/ui/ModUI.lua:41-45). A passthrough that returned its
-- argument would therefore hand back the very table the mod just mutated:
-- `out` and `vanilla` would be the same object, `#out == #vanilla + 1`
-- could never hold, and the "vanilla rows survived" loop below would be
-- comparing a table against itself. Returning a copy is also the more
-- faithful stand-in, since the real start menu builds a fresh list per open.
local function passthrough(_, items)
  local copy = {}
  for i, row in ipairs(items) do copy[i] = row end
  return copy
end
local out = Runtime.call("ui.start_menu.items", passthrough, nil, vanilla)
T.check(out ~= vanilla, "the hook result is a distinct table from the input")

T.eq(#out, #vanilla + 1, "exactly one row added")

local careerAt, saveAt
for i, row in ipairs(out) do
  if row.label == "CAREER" then careerAt = i end
  if row.label == "SAVE" then saveAt = i end
end
T.check(careerAt ~= nil, "a CAREER row exists")
T.check(saveAt ~= nil, "SAVE survived")
T.check(careerAt < saveAt, "CAREER sits before SAVE")
T.check(type(out[careerAt].onSelect) == "function", "the row is selectable")

-- vanilla rows are preserved, not rebuilt
for _, want in ipairs(vanilla) do
  local found = false
  for _, row in ipairs(out) do
    if row.label == want.label then found = true end
  end
  T.check(found, want.label .. " survived the insertion")
end

-- ------- masking: unreached rungs read as ???

local Card = dofile("mods/career_card/card.lua")
local Ladder = dofile("mods/career_card/ladder.lua")
local Metrics = dofile("mods/career_card/metrics.lua")
local Rank = dofile("mods/career_card/rank.lua")
Metrics.ladder, Rank.ladder, Rank.metrics = Ladder, Ladder, Metrics

local rows = Card.ladderRows(Ladder, { rank = 2, peakRank = 2, forfeited = {} })
T.eq(#rows, 6, "every rung is listed")
T.eq(rows[1].label, "1 DEPENDENT", "a reached rung shows its title")
T.eq(rows[2].label, "2 FIELD AIDE", "the current rung shows its title")
T.eq(rows[3].label, "3 ???", "the next rung is masked")
T.eq(rows[6].label, "6 ???", "distant rungs are masked")
T.eq(rows[1].right, "¥100", "a reached rung shows its stipend")
T.eq(rows[3].right, "", "a masked rung shows no stipend")

-- a forfeited rung reads CLOSED once it has been seen
local closed = Card.ladderRows(Ladder, { rank = 5, peakRank = 5,
  forfeited = { [4] = true } })
T.eq(closed[4].label, "4 CLOSED", "a forfeited rung reads CLOSED")
T.eq(closed[4].right, "", "a forfeited rung shows no stipend")

-- a forfeited rung reads CLOSED immediately, even if the player never
-- qualified for it and peakRank never reached it. Raiding the hideout
-- before qualifying for rank 4 must not leave it reading "4 ???" -- that
-- would promise a promotion that can now never be granted.
local never = Card.ladderRows(Ladder, { rank = 2, peakRank = 2,
  forfeited = { [4] = true } })
T.eq(never[4].label, "4 CLOSED", "a forfeited rung is CLOSED even below peak")
T.eq(never[4].right, "", "a forfeited rung shows no stipend, even below peak")

-- ------- detail lines, and the 18-column budget
-- This is the function that actually renders sponsor names, and ListMenu:draw
-- neither wraps nor truncates. Assert the width invariant across EVERY rank in
-- both states rather than spot-checking one, because the two names that
-- overflow (GAME CORNER, PKMN LEAGUE) are ranks 4 and 6, not rank 1.

local WIDTH = 18

-- Columns, not bytes. The yen sign is a literal UTF-8 character in these
-- strings (the engine writes it that way too - see src/ui/BagMenu.lua), so it
-- occupies two bytes but one screen column. Counting #s would over-report and
-- make a legal line look like an overflow. Continuation bytes are 0x80..0xBF.
local function cols(s)
  local n = 0
  for i = 1, #s do
    local b = s:byte(i)
    if b < 0x80 or b > 0xBF then n = n + 1 end
  end
  return n
end

local function widthCheck(label, lines)
  for _, line in ipairs(lines) do
    T.check(cols(line) <= WIDTH,
      ("%s: %q is %d cols, budget is %d"):format(label, line, cols(line), WIDTH))
  end
end

-- the helper itself must be right, or every assertion below is meaningless
T.eq(cols("ABC"), 3, "plain ascii counts as itself")
T.eq(cols("¥100"), 4, "a UTF-8 yen counts as ONE column, not two bytes")
T.eq(#("¥100"), 5, "...and is genuinely two bytes wide in memory")

local full = { rank = 6, peakRank = 6, forfeited = {},
               lifetimeEarned = 999999, accrued = 0, cycleSeconds = 1200 }
for n = 1, Ladder.count() do
  local lines = Card.detailLines(Ladder, full, n, {})
  T.check(#lines > 0, ("rank %d produces detail lines"):format(n))
  widthCheck(("reached rank %d"):format(n), lines)
end

-- an unreached rung shows the progress view, which must also fit
local none = { rank = 1, peakRank = 1, forfeited = {},
               lifetimeEarned = 0, accrued = 0, cycleSeconds = 1200 }

local function progress(badgesHave, badgesNeed, ownedHave, ownedNeed,
                        wildHave, wildNeed, enabled)
  if enabled == nil then enabled = true end
  return {
    badges   = { have = badgesHave, need = badgesNeed, enabled = enabled },
    dexOwned = { have = ownedHave,  need = ownedNeed,  enabled = enabled },
    wild     = { have = wildHave,   need = wildNeed,   enabled = enabled },
  }
end

for n = 2, Ladder.count() do
  local lines = Card.detailLines(Ladder, none, n, progress(0, 8, 0, 60, 0, 260))
  T.check(#lines > 0, ("unreached rank %d produces lines"):format(n))
  widthCheck(("unreached rank %d"):format(n), lines)
end

-- ------- the progress view answers "where am I", not just "how much further"
-- This is the whole point of the view: a bare "25 MORE" never revealed the
-- encounter count it was counting down from, because nothing else in the mod
-- displays that number anywhere.

local standing = table.concat(
  Card.detailLines(Ladder, none, 4, progress(3, 4, 28, 35, 95, 120)), "\n")
T.check(standing:find("BADGES   3/4", 1, true) ~= nil,
  "the badge row shows have/need, not a bare shortfall")
T.check(standing:find("OWNED    28/35", 1, true) ~= nil,
  "the dex row shows have/need")
T.check(standing:find("WILD WON 95/120", 1, true) ~= nil,
  "the wild-win row shows the count the player could not otherwise see")
T.eq(standing:find("MORE", 1, true), nil, "the old shortfall wording is gone")

-- A DISABLED gate must not read like a satisfied one. unmetFor omits a
-- disabled gate exactly as it omits a met gate, so the old view rendered
-- "BADGES   DONE" for a player with zero badges and NEED BADGES switched
-- off. progressFor carries `enabled` through precisely to stop that.
local off = table.concat(
  Card.detailLines(Ladder, none, 4, progress(0, 4, 0, 35, 0, 120, false)), "\n")
T.check(off:find("BADGES   OFF", 1, true) ~= nil,
  "a switched-off gate reads OFF")
T.eq(off:find("DONE", 1, true), nil,
  "a switched-off gate never reads DONE at zero progress")

-- the widest row the clamp permits must still fit the budget
local huge = Card.detailLines(Ladder, none, 4,
  progress(999999, 999999, 999999, 999999, 999999, 999999))
widthCheck("clamped five-digit counts", huge)
T.check(table.concat(huge, "\n"):find("WILD WON 9999/9999", 1, true) ~= nil,
  "counts past four digits clamp rather than overflow the line")

-- a partly-supplied progress table must not crash the view
widthCheck("empty progress", Card.detailLines(Ladder, none, 4, {}))
widthCheck("nil progress", Card.detailLines(Ladder, none, 4, nil))

-- ------- CREDIT PAST is declared on the card, never silent
-- The credited portion is the one number on this screen the mod did not
-- watch happen. A WILD WON row quietly inflated by an estimate would be the
-- only untrustworthy figure here, so the view says so out loud.

local function withCredit(n)
  local p = progress(3, 4, 28, 35, 95, 120)
  p.wild.credited = n
  return p
end

local credited = table.concat(Card.detailLines(Ladder, none, 4, withCredit(27)), "\n")
T.check(credited:find("WILD WON 95/120", 1, true) ~= nil,
  "the wild row still shows the total")
T.check(credited:find("(27 CREDITED)", 1, true) ~= nil,
  "and the estimated portion is named")
widthCheck("with credit", Card.detailLines(Ladder, none, 4, withCredit(27)))

local uncredited = table.concat(Card.detailLines(Ladder, none, 4, withCredit(0)), "\n")
T.eq(uncredited:find("CREDITED", 1, true), nil,
  "zero credit adds no line at all")
T.eq(table.concat(Card.detailLines(Ladder, none, 4,
  progress(3, 4, 28, 35, 95, 120)), "\n"):find("CREDITED", 1, true), nil,
  "an absent credited field adds no line")

-- a switched-off wild gate reads OFF, so a credit against it is not
-- something to advertise
local offWild = progress(3, 4, 28, 35, 95, 120, false)
offWild.wild.credited = 27
T.eq(table.concat(Card.detailLines(Ladder, none, 4, offWild), "\n")
  :find("CREDITED", 1, true), nil,
  "no credit line while the wild gate is switched off")

-- the credited line is clamped like every other number on this screen
widthCheck("huge credit", Card.detailLines(Ladder, none, 4, withCredit(999999)))
T.check(table.concat(Card.detailLines(Ladder, none, 4, withCredit(999999)), "\n")
  :find("(9999 CREDITED)", 1, true) ~= nil,
  "a five-digit credit clamps rather than overflowing the line")

-- ------- the ladder hint on the next rung

Card.metCount = Rank.metCount
local hinted = Card.ladderRows(Ladder, { rank = 3, peakRank = 3, forfeited = {} },
  progress(3, 4, 40, 35, 95, 120))
T.eq(hinted[4].right, "1/3", "the next rung shows how many gates are met")
T.eq(hinted[4].label, "4 ???", "...without unmasking the rung")
T.eq(hinted[5].right, "", "rungs beyond the next one show no hint")
T.eq(hinted[6].right, "", "the top rung shows no hint")
for _, row in ipairs(hinted) do
  local width = cols(row.label) + cols(row.right) + 1
  T.check(width <= WIDTH,
    ("ladder row %q + %q is %d cols, budget is %d"):format(
      row.label, row.right, width, WIDTH))
end

-- with every gate switched off there is nothing to count, and no hint
local noGates = Card.ladderRows(Ladder, { rank = 3, peakRank = 3, forfeited = {} },
  progress(0, 4, 0, 35, 0, 120, false))
T.eq(noGates[4].right, "", "no hint when every gate is switched off")

-- omitting progress entirely keeps the old, hint-free ladder
local plain = Card.ladderRows(Ladder, { rank = 3, peakRank = 3, forfeited = {} })
T.eq(plain[4].right, "", "the ladder still renders with no progress supplied")

-- a forfeited rung's detail view never implies an active sponsorship,
-- whether the player is still below it or long past it. Both cases must
-- also fit the 18-column budget.
local belowPeak = { rank = 2, peakRank = 2, forfeited = { [4] = true },
                     lifetimeEarned = 0, accrued = 0, cycleSeconds = 1200 }
local belowLines = Card.detailLines(Ladder, belowPeak, 4, {})
T.check(#belowLines > 0, "a forfeited rung below peak still produces lines")
widthCheck("forfeited below peak", belowLines)
local belowText = table.concat(belowLines, "\n")
T.check(belowText:find("CLOSED", 1, true) ~= nil,
  "a forfeited rung below peak shows CLOSED")
T.eq(belowText:find("STIPEND", 1, true), nil,
  "a forfeited rung below peak shows no stipend")
T.eq(belowText:find("NEXT PAY", 1, true), nil,
  "a forfeited rung below peak shows no NEXT PAY")
T.eq(belowText:find(Ladder.get(4).sponsor, 1, true), nil,
  "a forfeited rung below peak never names the dead sponsor")

local abovePeak = { rank = 6, peakRank = 6, forfeited = { [4] = true },
                     lifetimeEarned = 999999, accrued = 0, cycleSeconds = 1200 }
local aboveLines = Card.detailLines(Ladder, abovePeak, 4, {})
T.check(#aboveLines > 0, "a forfeited rung above peak still produces lines")
widthCheck("forfeited above peak", aboveLines)
local aboveText = table.concat(aboveLines, "\n")
T.check(aboveText:find("CLOSED", 1, true) ~= nil,
  "a forfeited rung above peak shows CLOSED")
T.eq(aboveText:find("STIPEND", 1, true), nil,
  "a forfeited rung above peak shows no stipend")
T.eq(aboveText:find("NEXT PAY", 1, true), nil,
  "a forfeited rung above peak shows no NEXT PAY")
T.eq(aboveText:find(Ladder.get(4).sponsor, 1, true), nil,
  "a forfeited rung above peak never names the dead sponsor")

-- a reached rung names its sponsor somewhere; a masked one never does
local reached = table.concat(Card.detailLines(Ladder, full, 4, {}), "\n")
T.check(reached:find("GAME CORNER", 1, true) ~= nil,
  "a reached rung names its sponsor")
local masked = table.concat(Card.detailLines(Ladder, none, 4, {}), "\n")
T.eq(masked:find("GAME CORNER", 1, true), nil,
  "a masked rung never leaks its sponsor name")

-- out of range must not reach Metrics.requirements, which does not guard nil
T.eq(#Card.detailLines(Ladder, full, 99, {}), 0, "an unknown rank yields no lines")

-- ------- the clock formatter

T.eq(Card.formatClock(0), "00:00", "zero")
T.eq(Card.formatClock(372), "06:12", "six minutes twelve")
T.eq(Card.formatClock(1200), "20:00", "a full cycle")
T.eq(Card.formatClock(-5), "00:00", "negatives clamp to zero")

run.release()
T.finish("career_card_ui")
