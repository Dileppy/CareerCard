-- Turns a snapshot of player progress into a rank number.
--
-- Pure: no mod object, no engine, no LOVE. Callers inject the ladder and
-- metrics modules onto Rank.ladder / Rank.metrics before use.
--
-- Rank 1 (MOM) is a floor with no requirements, so evaluate never returns
-- zero. That is the design thesis expressed as an invariant: sponsors come
-- and go, your mom does not.

local Rank = {}

Rank.ladder = nil
Rank.metrics = nil

local function meets(record, st, totals, gates)
  local req = Rank.metrics.requirements(record, totals)
  if gates.badges ~= false and (st.badges or 0) < req.badges then return false end
  if gates.dex ~= false and (st.owned or 0) < req.dexOwned then return false end
  if gates.wild ~= false and (st.wild or 0) < req.wild then return false end
  return true
end

-- Walk up from the floor and stop at the first rung the player cannot
-- reach. A forfeited rung is skipped rather than treated as a wall, so
-- losing the GAME CORNER does not pin the player below SILPH CO.
--
-- Losing a sponsor you actually HELD drops you to MOM rather than to
-- whoever paid you before them. That is the point of the collapse: the
-- floor catches you, not your previous boss. `st.heldWhenLost` is what
-- distinguishes the two cases: main.lua's forfeitGameCorner records the
-- FACT of having held the rung at the moment it was forfeited, keyed by
-- rank number, the same shape as `forfeited`.
--
-- This used to be inferred from st.peakRank (the highest rank ever
-- reached), but a peak is not proof of having held THIS rung: it also
-- rises from toggling a gate off and back on, or from a mod that adds
-- species and rescales the gates downward under a player already past
-- them. Either path could leave peakRank high with rank 4 never actually
-- held, and the old inference wrongly demoted those players to MOM the
-- moment rank 4 forfeited. Recording the fact at the moment of loss avoids
-- the guesswork entirely.
function Rank.evaluate(st, totals, gates)
  st = st or {}
  gates = gates or {}
  local forfeited = st.forfeited or {}
  local heldWhenLost = st.heldWhenLost or {}
  local best, top = 1, 1
  for n = 2, Rank.ladder.count() do
    local record = Rank.ladder.get(n)
    if meets(record, st, totals, gates) then
      top = n
      if not forfeited[n] then best = n end
    else
      break
    end
  end
  if forfeited[top] and heldWhenLost[top] then return 1 end
  return best
end

-- What is still short for a given rung, for the card's progress view.
-- A met gate is absent from the table rather than zero, so the UI can
-- distinguish "done" from "needs none".
function Rank.unmetFor(record, st, totals, gates)
  st = st or {}
  gates = gates or {}
  local req = Rank.metrics.requirements(record, totals)
  local out = {}
  if gates.badges ~= false then
    local short = req.badges - (st.badges or 0)
    if short > 0 then out.badges = short end
  end
  if gates.dex ~= false then
    local short = req.dexOwned - (st.owned or 0)
    if short > 0 then out.dexOwned = short end
  end
  if gates.wild ~= false then
    local short = req.wild - (st.wild or 0)
    if short > 0 then out.wild = short end
  end
  return out
end

-- The full standing for a rung: what the player HAS beside what the rung
-- ASKS FOR, per gate. unmetFor answers "how much further"; this answers
-- "where am I", which is the question the card could not previously answer
-- at all -- a bare "25 MORE" never revealed the encounter count it was
-- counting down from.
--
-- `enabled` carries the gate switch through to the UI on purpose. unmetFor
-- omits a disabled gate exactly as it omits a satisfied one, so a card
-- rendering from unmetFor alone showed "DONE" for a gate the player had
-- switched off at zero progress. A disabled gate is not a met gate and must
-- not read like one.
function Rank.progressFor(record, st, totals, gates)
  st = st or {}
  gates = gates or {}
  local req = Rank.metrics.requirements(record, totals)
  return {
    badges   = { have = st.badges or 0, need = req.badges,
                 enabled = gates.badges ~= false },
    dexOwned = { have = st.owned or 0,  need = req.dexOwned,
                 enabled = gates.dex ~= false },
    wild     = { have = st.wild or 0,   need = req.wild,
                 enabled = gates.wild ~= false },
  }
end

-- How many of the enabled gates are satisfied, for the ladder's at-a-glance
-- hint. Returns met, total. A rung with every gate switched off reports
-- 0, 0; the caller decides whether that is worth drawing.
function Rank.metCount(progress)
  local met, total = 0, 0
  for _, key in ipairs({ "badges", "dexOwned", "wild" }) do
    local gate = progress[key]
    if gate and gate.enabled then
      total = total + 1
      if gate.have >= gate.need then met = met + 1 end
    end
  end
  return met, total
end

return Rank
