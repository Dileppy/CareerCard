# Career Card

Your mom believes in you, so she sends you money.

Career Card gives you a trainer salary that arrives on the in-game clock.
You start as a DEPENDENT on MOM's allowance. Earn badges, fill the POKeDEX
and meet enough wild POKeMON, and real Kanto figures take over your
sponsorship: PROF. OAK, BILL, the CELADON GAME CORNER, SILPH CO., and
finally the POKeMON LEAGUE.

A CAREER entry in the START menu shows the ladder, what you have earned,
when your next payday lands, and exactly where you stand against your next
promotion.

## Reading the card

Unreached rungs stay masked, but the next one up shows how many of its
three requirements you have already cleared. Select it to see your standing
against each one.

    CAREER LADDER            RANK 4
    +------------------+     +------------------+
    |1 DEPENDENT   Y100|     |???               |
    |2 FIELD AIDE  Y150|     |                  |
    |3 RESEARCHER  Y200|     |YOU / NEEDED      |
    |4 ???          0/3|     |BADGES   3/4      |
    |5 ???             |     |OWNED    28/35    |
    |6 ???             |     |WILD WON 95/120   |
    +------------------+     +------------------+

Only the next rung shows a hint, and it names no sponsor, title or stipend.
A gate you have switched off in the options reads OFF rather than counting
toward the promotion.

WILD WON counts wild POKeMON you defeated or caught. Running away does not
count, and neither does blacking out: the gate is there to reward engaging
with wild POKeMON, not walking into grass and fleeing.

## Installing part-way through a playthrough

Nothing in a POKeMON save records how many wild battles you have fought, so
a mod installed at 40 hours cannot know what you already did and starts the
wild gate at zero.

CREDIT PAST, off by default, grants an estimate for that. It counts the
species in your POKeDEX as one wild battle each, which is deliberately
conservative: 200 battles across 27 species reads as 27, because a POKeDEX
records a species once however many times you met it.

    WILD WON 28/25
      (27 CREDITED)

The card always names the credited portion, because it is the one number on
that screen the mod did not watch happen. The estimate is measured once,
the first time the mod sees your save, so it can never fold in play that
was already being counted properly. Switching the option back off removes
the credit and leaves exactly the battles the mod saw you win.

## The ladder

| Rank | Title | Sponsor | Stipend |
|---:|---|---|---:|
| 1 | DEPENDENT | MOM | 100 |
| 2 | FIELD AIDE | PROF. OAK | 150 |
| 3 | RESEARCHER | BILL | 200 |
| 4 | HEADLINER | GAME CORNER | 300 |
| 5 | CONTRACTOR | SILPH CO. | 400 |
| 6 | ACE TRAINER | PKMN LEAGUE | 500 |

Rank 4 is missable. The GAME CORNER is a TEAM ROCKET front, and if you
raid the hideout beneath it before you qualify, they never sign you - the
rung reads CLOSED on your card from then on, and BILL keeps paying you.

If they had already signed you, the collapse is felt. Your pay stops and
MOM carries you at 100 through LAVENDER, FUCHSIA and SAFFRON until SILPH
CO. picks you up.

MOM is the floor of the whole ladder, not a rung you graduate past. Lose a
sponsor and you land on her, never on nothing.

## Balance

Roughly 18,000 across a full playthrough. It matters when you cannot afford
POKe BALLS early and fades to flavour by SILPH CO., which is the point.
Every number is adjustable in the mod options, including the payday length
and an overall pay rate from 50% to 200%.

The clock measures time played, not time the game is left open. Pay accrues
per step and each step credits at most 30 seconds, so an hour parked with
the game running earns half a minute of wages.

PAYDAY MINS ranges from 1 to 120, not just the 20-minute default the
~18,000 target above assumes - setting it to 1 pays out roughly 40x faster
than documented. Shortening the cycle mid-run does not lose banked time:
whatever has already accrued toward the old, longer cycle carries over and
pays out in a lump against the new, shorter one as soon as it matures.

## Options

| Option | Default | What it does |
|---|---|---|
| ALLOWANCE | on | master switch |
| PAYDAY MINS | 20 | minutes of play per payday |
| PAY RATE | 100% | scales every stipend |
| PAYDAY POPUP | on | show the payday message |
| NEED BADGES | on | require the badge gate for promotion |
| NEED DEX | on | require the POKeDEX gate |
| NEED WILD WINS | on | require the wild battle gate |
| CREDIT PAST | off | credit play from before you installed the mod |

## Compatibility

Requires no special permissions and changes no battle mechanics, so it does
not move the link fingerprint. It reads the badge and species lists from
the live game data rather than assuming 8 and 151, so it stays correct
alongside mods that add species or change the badge set.

### Where is CAREER? (Gen 1 Modern UI)

With Gen 1 Modern UI installed, CAREER is not on the root START menu. That
mod deliberately collects entries added by other mods under a single MOD
MENUS entry, so CAREER lives at:

    START -> MOD MENUS -> CAREER

Highlight CAREER there and press SELECT to pin it onto the root START menu,
or turn off "START MOD MENUS" in Modern UI's own options to keep every mod
entry on a flat list. Career Card registers its row at the default hook
priority on purpose and will not fight for placement: whichever UI mod is
loaded gets to decide where the row is shown.

## License

MIT. See LICENSE.

Career Card ships no ROM-derived content. It reads the badge and species
lists from whatever the engine has loaded and contains no Nintendo assets,
text or data of any kind. You supply your own ROM to Gen1Recomp; this mod
neither includes one nor helps you obtain one.

By Dileppy. Built with human effort and the help of AI.
