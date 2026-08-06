-- Standalone: luajit mods/career_card/tests/career_card_notify_test.lua
--
-- notify.lua's own header comment claims every string it produces respects
-- the engine's 18-column / 2-line text box budget. This suite is what
-- actually proves that, against every rank on the ladder and a spread of
-- amounts, instead of taking the claim on faith.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Ladder = dofile("mods/career_card/ladder.lua")
local Notify = dofile("mods/career_card/notify.lua")

local WIDTH = 18
local MAX_LINES = 2

-- Notify calls Notify.pushText(game, page); inject a capture closure so
-- this suite needs no real game object, no engine, no LOVE.
local captured
Notify.pushText = function(_, page) captured = page end

local game = {} -- a dummy, truthy game handle; say() only checks it exists

-- Columns, not bytes: the yen sign is a literal UTF-8 character here (as it
-- is throughout the engine), so it spans two bytes but one screen column.
-- Counting #s would over-report and fail a line that actually fits.
local function cols(s)
  local n = 0
  for i = 1, #s do
    local b = s:byte(i)
    if b < 0x80 or b > 0xBF then n = n + 1 end
  end
  return n
end

T.eq(cols("ABC"), 3, "plain ascii counts as itself")
T.eq(cols("¥100"), 4, "a UTF-8 yen counts as ONE column")
T.eq(#("¥100"), 5, "...though it is two bytes in memory")

-- \f is the engine's page break (src/render/TextBox.lua:4): wait for A,
-- clear, keep going. The budget is per PAGE, so split on \f before counting
-- lines, or a legal two-page message reads as a four-line overflow.
local function checkPage(label, text)
  T.check(type(text) == "string" and #text > 0, label .. ": produced a page")
  local pages = {}
  for page in (text .. "\f"):gmatch("(.-)\f") do pages[#pages + 1] = page end
  for p, page in ipairs(pages) do
    local tag = #pages > 1 and ("%s page %d"):format(label, p) or label
    local lines = {}
    for line in (page .. "\n"):gmatch("(.-)\n") do
      lines[#lines + 1] = line
    end
    T.check(#lines <= MAX_LINES,
      ("%s: %d lines exceeds the %d-line budget (%q)"):format(
        tag, #lines, MAX_LINES, page))
    for i, line in ipairs(lines) do
      T.check(cols(line) <= WIDTH,
        ("%s line %d: %q is %d cols, budget is %d"):format(
          tag, i, line, cols(line), WIDTH))
    end
  end
  return pages
end

-- The yen must be a real UTF-8 yen, not the bare 0xA5 byte, which maps to no
-- glyph and renders blank. This was seen live on device: the payday box showed
-- "MOM sent /  100 to spend!" with an empty square where the currency belongs.
-- Restore the capture closure afterwards; the suite below depends on it.
Notify.payday(game, "MOM", 100)
T.check(captured:find("\194\165", 1, true) ~= nil,
  "payday uses a UTF-8 yen (0xC2 0xA5), which the engine's font maps")
T.eq(captured:find("\165", 1, true), captured:find("\194\165", 1, true) + 1,
  "the only 0xA5 present is the trailing byte of that UTF-8 pair")
captured = nil

local AMOUNTS = { 0, 100, 12345, 999999 }

for n = 1, Ladder.count() do
  local record = Ladder.get(n)

  for _, amount in ipairs(AMOUNTS) do
    captured = nil
    Notify.payday(game, record.sponsor, amount)
    checkPage(("payday rank %d (%s) amount %d"):format(n, record.sponsor, amount),
      captured)
  end

  captured = nil
  Notify.promoted(game, record.title, record.sponsor)
  local bare = checkPage(
    ("promoted rank %d (%s / %s)"):format(n, record.title, record.sponsor),
    captured)
  T.eq(#bare, 1, ("promoted rank %d with no stipend stays one page"):format(n))

  -- the two-page form, across the whole PAY RATE range (50%% to 200%%) and
  -- the ceiling a scale option could produce. The second page is where the
  -- raise is stated, and it is the page that can overflow: "¥%d EACH PAYDAY"
  -- spends 12 columns before the first digit.
  for _, scaled in ipairs({ 0, 50, record.stipend, record.stipend * 2, 999999 }) do
    captured = nil
    Notify.promoted(game, record.title, record.sponsor, scaled)
    local pages = checkPage(
      ("promoted rank %d (%s) at %d"):format(n, record.title, scaled), captured)
    T.eq(#pages, 2, ("promoted rank %d at %d is two pages"):format(n, scaled))
    T.check(pages[1]:find(record.sponsor, 1, true) ~= nil,
      ("promoted rank %d page 1 names the sponsor"):format(n))
    T.check(pages[1]:find(record.title, 1, true) ~= nil,
      ("promoted rank %d page 1 names the title"):format(n))
    T.check(pages[2]:find(tostring(scaled), 1, true) ~= nil,
      ("promoted rank %d page 2 states the pay"):format(n))
    T.check(pages[2]:find("\194\165", 1, true) ~= nil,
      ("promoted rank %d page 2 uses a real UTF-8 yen"):format(n))
  end

  captured = nil
  Notify.lostSponsor(game, record.sponsor)
  checkPage(("lostSponsor rank %d (%s)"):format(n, record.sponsor), captured)
end

T.finish("career_card_notify")
