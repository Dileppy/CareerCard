# Changelog

All notable changes to this project are documented here.
The format follows Keep a Changelog and the versions match `manifest.json`.

## [1.0.1] - 2026-08-06

### Fixed
- The mod declared no `affects_link`, and an omitted field is read as TRUE
  (`src/link/Handshake.lua:43` tests `affects_link ~= false`). Every player
  who installed 1.0.0 was therefore treated as link-incompatible and could
  not trade or link battle with anyone who did not also have it, despite the
  mod changing no battle mechanics whatsoever. The manifest now declares
  `"affects_link": false`.

  The declaration is honest: the only link-relevant registry this mod
  touches is `pokemon`, and it only ever reads it to count species
  (`main.lua`). The load suite asserts both the declaration and the
  underlying fact, so a future change that starts writing to a link registry
  fails the tests rather than shipping a false claim.

## [1.0.0] - 2026-08-05

### Added
- Six rank sponsor ladder: MOM, PROF. OAK, BILL, GAME CORNER, SILPH CO.,
  PKMN LEAGUE.
- Stipend paid on the in-game playtime clock, default every 20 minutes.
- CAREER entry in the START menu with a ladder view and a per rank detail
  view showing what is still short of the next promotion.
- Promotion gates on badges, POKeDEX owned and wild encounters, all derived
  from the live game data rather than hardcoded totals.
- The GAME CORNER sponsorship ends permanently when TEAM ROCKET's hideout
  is cleared. If you held it, MOM resumes paying until SILPH CO. takes
  over; if you never did, the rung is simply skipped.
- Seven options including payday length, an overall pay rate, and
  individual switches for each promotion gate.
- A stable row id, `career_card.career`, so Gen 1 Modern UI can remember a
  pinned CAREER entry across label changes. Under that mod CAREER appears
  at START -> MOD MENUS -> CAREER by its design; see the README.

- The rung detail view reports your standing against each requirement as
  YOU / NEEDED (`WILD WON 95/120`) rather than a bare shortfall. The wild
  battle count in particular was displayed nowhere else, so "25 MORE"
  counted down from a number the player could never see.
- The next unreached rung shows how many of its three requirements are
  already met, so a masked row reads as something worth selecting. It stays
  masked otherwise, and rungs beyond it show nothing at all.
- CREDIT PAST, off by default, grants an estimate of wild battles fought
  before the mod was installed. No save records a wild battle count, so a
  mod installed part-way through a playthrough otherwise starts that gate
  at zero however long the player has played. The estimate counts POKeDEX
  species once each, is measured a single time on first sight of the save,
  is named on the card as a credited portion rather than folded silently
  into the total, and is removed cleanly if the option is switched back off.
- Promotions announce the raise on a second page: `PAY IS NOW / Y300 A
  PAYDAY`, using the effective figure after PAY RATE.

### Fixed
- The wild gate counted the encounter rather than the battle, so running
  away raised it. Walk into grass, flee, repeat, and the counter climbed
  without a single battle being fought, which is the opposite of what the
  gate exists to reward. Credit now lands on `battle.ended` and only for a
  win or a capture. Renamed WILD ENC to WILD WON, and NEED ENCOUNTS to
  NEED WILD WINS, to match what is actually measured.
- A promotion gate switched off in the options displayed as DONE, which was
  indistinguishable from a gate the player had actually satisfied. Disabled
  gates now read OFF. `Rank.unmetFor` omits a disabled gate exactly as it
  omits a met one, so the view is built from `Rank.progressFor` instead,
  which carries the switch through.
- The payday message rendered a blank where the amount belonged. The yen
  sign was written as a bare 0xA5 byte; the engine's font maps no glyph for
  it. Every yen in the mod is now a literal UTF-8 character, and the
  18-column width assertions count columns rather than bytes.
