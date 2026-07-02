# Border Handoff — Test Plan

How to verify the grid teleport (Cell A ↔ Cell B) once the game is launchable.
The code is complete; this is the checklist for the live test.

## Why it can't be tested in Studio

`TeleportService` only runs in a **published** game. In Studio playtest the
border wall still appears and detects you, but the teleport is a no-op — you'll
see `[BorderService] Teleport ... failed` in the Output and the screen fades out
then back in. That's expected and proves everything *up to* the teleport works.

## Prerequisites

- [ ] Both places belong to the **same Experience** (`10435243310`).
- [ ] `roblox/src/shared/GridConfig.lua` has the real PlaceIds:
      - Cell A `130890869057243`, Cell B `96623482055191`.
- [ ] The **identical, configured** code is published to **both** places
      (File → Publish to Roblox As → Cell A, then again → Cell B).
- [ ] The Experience is launchable by you (blocked today by the new-creator
      "make public" cooldown — retry after it lifts, or once Friends/Public is
      allowed).
- [ ] Backend is up: `GET /health` returns `{"status":"ok","db":"up"}`.

> After re-publishing, use **⋯ → Reiniciar servidores** (Restart servers) on
> both places so live servers pick up the new code.

## Core test — happy path

1. Launch **Cell A** (the start place) from the Roblox client.
2. Confirm you're in A: **green ground**, floating **"CELL A"** sign.
3. Create some state to prove it carries over:
   - Chop a tree → gain **Wood**.
   - Kill a slime → pick up **Slime Goo**.
   - Take a hit so your HP is not full.
4. Open the inventory (button/`I`) and note the exact counts + HP.
5. Walk **east** into the blue border wall.
   - **Expected:** screen fades to black → short Roblox load → you arrive.
6. Confirm you're in B: **brown ground**, **"CELL B"** sign, and you spawn at
   the **west edge** (not on top of the border).
7. Open the inventory: **Wood, Slime Goo, and HP match** what you had in A. ✅
8. Walk **west** into B's border wall → you return to **Cell A**, arriving at
   its **east edge**, state still intact.

## What each result tells you

| Symptom | Likely cause |
|---|---|
| "Teleport failed" in Output, no teleport | Running in Studio, OR PlaceId wrong/0 in GridConfig |
| Teleports but Cell B looks like Cell A / empty | Cell B wasn't re-published with the filled-in config |
| Arrive on top of the border and bounce back | Entry inset too small — raise `ENTRY_INSET` in GridConfig |
| Inventory empty after crossing | Backend unreachable in the destination (check HTTP enabled + `Secret.lua` + `/health`) |
| HP reset to full | Save-before-teleport didn't run, or destination created a new profile (UserId mismatch) |
| Stuck on black screen | Should be impossible — fade is fail-safe; if seen, check `BorderFadeUI` |

## Edge cases to check

- [ ] **Rapid re-cross:** immediately walk back through the border you arrived
      at — should return cleanly (arrival inset prevents instant re-trigger).
- [ ] **Cross mid-combat:** get hit, then cross — HP should persist at its
      reduced value, regen resumes in the new cell.
- [ ] **Full inventory carry:** fill several slots, cross — all slots intact.
- [ ] **Two players:** both cross around the same time — each keeps their own
      state (no mix-ups).
- [ ] **Backend down during cross:** stop the backend, cross — HP save fails
      gracefully; inventory (already persisted) is still correct on arrival.

## Tuning knobs (`roblox/src/shared/GridConfig.lua`)

- `HALF` — half-width of a cell (border wall distance from center).
- `ENTRY_INSET` — how far inside the opposite border you arrive.
- `ENTRY_Y` — spawn height on arrival (raise if characters clip the ground).

## Related

- Handoff code: `roblox/src/server/BorderService.lua`, arrival positioning in
  `roblox/src/server/PlayerService.lua`, fade in
  `roblox/src/client/BorderFadeUI.lua`.
