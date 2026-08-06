-- Payday and promotion text boxes.
--
-- Gen 1 text boxes take at most 18 columns and 2 lines per page (the engine's
-- own TextBox.paginate(text, 18)). Every format string below is checked
-- against every rank on the ladder in tests/career_card_notify_test.lua, not
-- just eyeballed, because the two 11-character sponsor names ("GAME CORNER",
-- "PKMN LEAGUE") and the 11-character top title ("ACE TRAINER") are what
-- overflow first.
--
-- Delivery is safe by construction: main.lua only calls into this from the
-- world.stepped heartbeat, so a box can only ever appear while the player
-- is walking in the overworld.

local Notify = {}

-- injected by main.lua so this module never requires src.* itself
Notify.pushText = nil

local function say(game, page)
  if not (Notify.pushText and game) then return end
  Notify.pushText(game, page)
end

function Notify.payday(game, sponsor, amount)
  say(game, ("%s sent\n¥%d to spend!"):format(sponsor, amount))
end

-- Two pages, split on \f (src/render/TextBox.lua:4 -- page break, wait for
-- A, clear). The raise is the whole reward for a promotion and the message
-- used to omit it, so a player learned their new title and had to open the
-- card to find out what it paid. `stipend` is the effective figure, already
-- through PAY RATE, so the box never promises a number the payday will not
-- match.
function Notify.promoted(game, title, sponsor, stipend)
  local page = ("%s\nRANK: %s"):format(sponsor, title)
  if stipend then
    -- "A PAYDAY", not "EACH PAYDAY". The longer wording fits every stipend
    -- this ladder can currently produce (500 at the 10x PAY RATE ceiling),
    -- but only because two unrelated caps happen to line up; a six-figure
    -- figure overflows it by one column. The ladder is data and the scale
    -- cap lives in another file, so the string carries its own headroom
    -- rather than depending on both staying where they are.
    page = page .. ("\fPAY IS NOW\n¥%d A PAYDAY"):format(stipend)
  end
  say(game, page)
end

-- The player keeps being paid after this: MOM catches them at 100, she is
-- not fired along with the sponsor. "Your pay has stopped" was never true
-- once that design landed, so this no longer claims it.
function Notify.lostSponsor(game, sponsor)
  say(game, ("%s\nclosed. MOM pays."):format(sponsor))
end

return Notify
