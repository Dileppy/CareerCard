# Manual verification checklist

The automated suites cover logic headlessly but render no pixels. Run this
on a device that has Gen1Recomp installed with a ROM imported.

## Parity with the mod disabled

- [ ] Disable `career_card` in the F10 mod manager.
- [ ] START menu has no CAREER row.
- [ ] Walk for 20 minutes; no payday box appears, money does not change.

## The Career Card

- [ ] Re-enable the mod. START menu shows CAREER directly above SAVE. (The
      Trainer Card row, which carries your name, sits above CAREER.)
- [ ] CAREER opens the ladder. Rank 1 reads `1 DEPENDENT` with the stipend
      on the right; ranks 2-6 read `???` with no stipend.
- [ ] Select rank 1: the detail view shows RANK 1, DEPENDENT, SPONSOR on its
      own row with MOM beneath it, then STIPEND, EVERY, EARNED, NEXT PAY.
- [ ] B returns to the ladder. B again closes back to the START menu.
- [ ] Select an unreached rung: it shows `???` and a shortfall breakdown,
      and never names the sponsor.

## Payday

- [ ] Set PAYDAY MINS to 1 in the mod options.
- [ ] Walk continuously for one minute. A text box appears and money
      increases by exactly the current stipend.
- [ ] Stand completely still for two minutes, then take one step. No payday
      fires. (Idle time is capped at 30 seconds per step, so two minutes
      parked credits half a minute, nowhere near a full cycle.)
- [ ] Enter a battle with a payday due, finish it, then take a step. The
      payday arrives after the battle, not during it.
- [ ] Restore PAYDAY MINS to 20.

## Text fits the screen

Check at the smallest window size the device supports. No line may wrap or
run past the right edge.

- [ ] Every line of the detail view, at rank 4 (GAME CORNER) and rank 6
      (PKMN LEAGUE) specifically - those two sponsor names are the longest
      and previously overflowed.
- [ ] The payday text box.
- [ ] The promotion text box.
