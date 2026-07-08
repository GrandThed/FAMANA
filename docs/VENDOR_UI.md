# Vendor UI Remodel — Tarkov-Style Trade Screen

> **Status (2026-07-08): implemented** — backend `/deal` route + barter
> content, `shared/ItemValue.lua`, `VendorService.StoreDeal`,
> `PlayerService.executeDeal`, and the client rebuild (`ItemTooltip` +
> `ItemGrid` + the three-pane `StoreUI`). Checklist step 8 (InventoryUI
> migration onto ItemGrid) is the remaining follow-up. Verify per §9.
> Implementation notes vs spec: price chips render bottom-LEFT (qty owns
> bottom-right, matching InventoryUI); barter stock chips show "⇄" with the
> exact costs in the tooltip; `removeItemAt` wasn't needed — positional
> sells ride the `/deal` payload and the backend's `removeAt` directly.

> Spec for rebuilding `client/StoreUI.lua` from the current list + detail
> panel into a three-pane trade screen modeled on Escape from Tarkov's
> trader view (reference screenshot in chat, 2026-07-07): the vendor's
> stock as an item grid on the left, a deal zone in the middle with one
> big DEAL button, and the player's own inventory grid on the right.
> Everything stays server-authoritative — the client builds a deal and
> asks; `VendorService` validates, prices, and settles it through ONE
> transactional backend call.

## 1. Goal & scope

- **One screen, no tabs.** Buy and sell live together: vendor stock left,
  your grid right, both feeding the central deal zone. The Buy/Sell tabs
  and the detail pane die.
- **Grid-native everywhere.** Stock, your pack, AND the deal zone render
  items as footprint-sized tiles (`Theme.Size.Cell` = 42px, item `size`
  W×H) with price chips, rarity strokes and the §6.5 hover tooltip. The
  deal zone is two real grids ("You give" / "You get") — items dropped
  in are auto-placed first-fit, Tarkov style.
- **Atomic batched deals.** The whole deal — gold delta, sells, buys,
  barter costs — settles in one backend transaction
  (`POST /player/:id/deal`). It all lands or none of it does; a failed
  deal leaves the zone intact.
- **Trait-value pricing for rolled gear** (§5): sell value grows
  superlinearly with each trait's points (`points^1.85` per line, §5.1),
  so concentrated rolls beat spread ones. This also makes rolled `meta`
  instances sellable at all — today the id-based remove deliberately
  skips them.
- **Barter trades**: a stock item may cost items instead of gold
  (`barter` on the trade def); its costs auto-enter "You give".
- **Quick-move**: shift-click moves the whole stack to the contextual
  destination (deal zone in the store; equipment slot in the inventory
  screen once it migrates onto `ItemGrid` — §6/§8).

Decided (2026-07-08): no stock limits/restock; deal zone is a real grid,
not a line cart (5×4 per side, confirmed); shift-click on vendor stock
adds ONE full stack regardless of gold; DEAL button copy is plain
"DEAL"; value exponent is 1.85 (§5.1); `ItemGrid` eventually replaces
InventoryUI's grid (consolidated, single implementation); no buyback
tab for now. Still out of scope: multi-vendor tabs, rearranging your
own pack inside the store screen.

## 2. Reference mapping (Tarkov → FAMANA)

| Tarkov element | FAMANA equivalent |
|---|---|
| Trader stock grid (left, price tag per tile) | Store's **buyable** trades packed into a grid, `buyPrice` (or barter icons) chip per tile |
| Deal zone + "DEAL!" button (center) | "You give" / "You get" grids, net-gold row, DEAL button |
| Player stash grid (right) | The `main` 10×30 grid (read + drag-to-sell; no rearranging in MVP) |
| Roubles | Gold (`◈`, `Gold` attribute; gold is the net row, never a tile) |
| Barter offers (items-for-items) | `barter` cost on a trade def (§5.3) |
| Ctrl-click quick-move | Shift-click whole-stack quick-move |
| Trader tabs along the bottom | Out of scope — one vendor per screen (`OpenStore` already scopes it) |

Sell-only trades (wood, stone, slime goo, goblin ear) never appear in
the stock pane — they surface as sell-price chips on the player's own
tiles, exactly like Tarkov shows what a trader pays for your loot.

## 3. Layout (authored at 1280×720, `UIKit.autoScale`)

Window ~**1120×620**, centered, `UIKit.stylePanel` + `addShadow`.
Title bar: store name (Display), vendor name (muted), `closeButton`.

```
┌──────────────────────────────────────────────────────────────────┐
│  GENERAL GOODS · Marla the Trader                            [X] │
├──────────────────┬───────────────────┬───────────────────────────┤
│  STOCK           │  YOU GIVE         │  YOUR PACK        ◈ 1 240 │
│ ┌──┬──┬──┬──┐    │ ┌──┬──┬──┬──┬──┐  │ ┌──┬──┬──┬──┬──┬──┬──┬──┐ │
│ │▒▒│▒▒│▒▒│▒▒│    │ │██│▒▒│  │  │  │  │ │▒▒│▒▒│  │  │▒▒│  │  │  │ │
│ │◈120 ◈40 …  │    │ │50│  │  │  │  │  │ │◈2 │◈2 │  … 10 cols …  │ │
│ ├──┴──┴──┴──┤    │ └──┴──┴──┴──┴──┘  │ ├──┴──┴─────────────────┤ │
│ │ 8 cols,    │    │  YOU GET          │ │ 10×30, ~11 rows       │ │
│ │ scrolls    │    │ ┌──┬──┬──┬──┬──┐  │ │ visible, scrolls      │ │
│ └────────────┘    │ │▒▒│  │  │  │  │  │ └───────────────────────┘ │
│                   │ └──┴──┴──┴──┴──┘  │                           │
│                   │  Net    pay ◈ 20  │                           │
│                   │  [     DEAL     ] │                           │
│                   │  status line      │                           │
└──────────────────┴───────────────────┴───────────────────────────┘
```

- **Stock pane (left, ~350px):** 8-column grid, scrollable. Tiles are
  packed client-side by first-fit in `stores.json` trade order (curated
  order = shelf layout; the packing is display-only, nothing persists).
  Tile = `ItemModels.preview` viewport + rarity stroke/glow + a price
  chip (`Theme.Text.Xs`, `Semantic.Currency` on Ink900 @ ~20%
  transparency) bottom-right. Barter trades show mini item icons + qty
  instead of a gold chip.
- **Deal pane (center, ~250px):** two 5-wide × 4-tall grids under
  "YOU GIVE" / "YOU GET" headers, then the net-gold row, the DEAL
  button (`UIKit.primaryButton`), and the status line (keep
  `ERROR_TEXT`). Deal tiles carry a quantity badge; barter-cost tiles
  carry a small lock badge (they belong to a "You get" item and can't
  be edited directly).
- **Player pane (right, ~450px):** the `main` grid, 10 wide, ~11 rows
  visible, scrollable — same tile visuals as InventoryUI. Header: gold
  readout. Tiles the store buys get a `sellPrice` chip (formula value
  for rolled gear); everything the store does NOT buy renders dimmed
  (~50% transparency) with a "Not traded here" tooltip line. Quantities
  already committed to the deal show ghosted on the source tile.
- Sharp corners, one ember accent (the DEAL button), tooltips identical
  to the inventory's (§6). `docs/UI.md` §8's vendor line gets rewritten
  to this layout.

## 4. Interactions

**Adding to the deal** (every route auto-places first-fit in the
target grid — unrotated first, rotated if that's the only fit):
- Click a stock tile → +1 into "You get". **Shift-click → one full
  stack** (def stack size; 1 for gear), regardless of gold — DEAL just
  stays disabled while unaffordable.
- Click a player tile → +1 into "You give". **Shift-click → the whole
  stack.** Drag into the deal pane → the whole stack.
- Drag a stock tile into the deal pane → +1 (drag has no natural
  quantity on the unlimited side).
- Rolled instances (`meta` present) always move as quantity 1, carry
  their grid position, and show the "[Lv N]" tier-colored label.
- Adding a barter item to "You get" auto-adds its cost tiles (locked)
  to "You give"; each extra unit scales the costs. Costs come out of
  your pack — the deal validates you own them.
- Same plain item id merges into one deal tile per side (badge grows);
  distinct rolled instances stay distinct tiles. If the deal grid can't
  fit the footprint, the add is refused with a status nudge.

**Editing the deal**
- Click a deal tile → popover: `− n +`, "All", remove `×`. Sells clamp
  to owned (main grid only), buys to 99 (`MAX_TRADE_QUANTITY`).
- Drag a tile out of the deal grid → removes it (its locked barter
  costs follow their "You get" item).

**The DEAL button**
- Label shows the settlement: `DEAL — PAY ◈ 20` / `DEAL — GET ◈ 130`.
- Disabled (ghost) when the zone is empty, net gold is short, or a
  barter cost is missing; the net row turns `Semantic.Danger`.
- Success: zone clears; grids/gold refresh through the existing
  `InventoryUpdated` push + `Gold` attribute; server sends the Notify
  toast. Failure: the WHOLE deal was rolled back (§5.4) — the zone
  stays as-is and the status line maps the error.

**Lifecycle**
- Opens on `OpenStore` (unchanged), zone always starts empty.
- New `ClientState.storeOpen` flag; `ShiftLockController` frees the
  cursor when `inventoryOpen or storeOpen`.
- Exclusive with the inventory screen: opening one closes the other.
- Client auto-closes past ~20 studs from the vendor (watch every 0.5s);
  the server's `MAX_TRADE_DISTANCE = 16` check stays authoritative.

## 5. Pricing, barter & protocol

### 5.1 Trait-value formula — `shared/ItemValue.lua`

One shared module so the chip, the deal tile, the net row and the
server all agree:

```
value(entry) = max(FLOOR, round( K × Σ over lines (points_i ^ EXP) ))
EXP = 1.85 (decided) · K = 3, FLOOR = 5 (tune vs goblin farm income)
```

- Raising EACH line to 1.85 separately (not the sum) rewards
  concentration. Reference values at K = 3:

| Lines | Σ p^1.85 | Value |
|---|---|---|
| Brawler 3 (e.g. Lynx Eye +3) | 7.6 | 23g |
| Brawler 4 | 13.0 | 39g |
| Brawler 5 + Bastion 1 | 20.6 | 62g |
| Brawler 5 + Bastion 3 | 27.3 | 82g |
| Brawler 6 | 27.5 | 83g |
| 8 + 4 + 3 (big legendary) | 67.5 | 202g |

  Ordering matches the design examples: 6 concentrated beats 5+3
  spread (by a hair — the crossover exponent is ≈1.82, so never tune
  below that), and Brawler 4 is +70% over 3 — more, but not double.
  Implementation rule: sum the lines in floating point and round ONCE
  at the end — per-line rounding erases the concentration edge (at
  K = 1, Brawler 6 and 5+3 both round to 28).
- Trait lines and school-point lines count identically — the roll
  already treats them as one budget. Rarity/itemLevel need no explicit
  term: rarity's bonus points + extra lines ARE the points.
- Lines come from `Traits.entryInfo` (meta overrides def), so the
  formula also prices def-fixed trait gear.
- **Sell-price resolution** (identical in StoreUI and VendorService):
  rolled instance (`meta`) → `ItemValue` IF the store has `buysGear =
  true` (new optional store field; `general_goods` sets it); else a
  listed trade `sellPrice` wins — INCLUDING for listed items whose def
  carries starter trait points (sword_iron's berserker +1 must not
  floor its curated 40g); else unlisted def-trait gear → `ItemValue`
  under `buysGear`. Otherwise not sellable here. Vendors never SELL
  rolled gear, so `buyPrice` is untouched.

### 5.2 Backend — `POST /player/:id/deal`

New route (X-Api-Key, same trust model as `addGold`/inventory today:
the Roblox server computes prices, the backend settles). One
transaction, all-or-nothing:

```
{ "goldDelta": -20,
  "removes": [ { "itemId": "wood", "quantity": 50 },
               { "containerId": "main", "x": 3, "y": 7 } ],
  "adds":    [ { "itemId": "sword_iron", "quantity": 1 } ] }
→ 200 { "ok": true, "gold": 1220, "inventory": [...] }
→ 409 { "error": "no_gold" | "no_items" | "no_space" | "bad_move" }
```

Composes the existing transactional primitives in `src/inventory.js`
(`removeItem` id-based, `removeAt` positional, `addItem` strict — all
already take a `client`); gold checks `gold + goldDelta >= 0` on the
players row. Any failure rolls the whole transaction back.

### 5.3 Barter trades — `stores.json`

```json
{ "itemId": "ring_vitality",
  "barter": [ { "itemId": "slime_goo", "qty": 25 },
              { "itemId": "goblin_ear", "qty": 10 } ] }
```
A trade carries `barter` OR `buyPrice`, never both, and an itemId
appears in at most one trade entry (`Stores.trade` is first-match) —
so giving an item a barter REPLACES its gold offer. Dual-cost offers
(player picks gold or mats) would need a `payWith` field on buy
lines; future extension. `backend/src/stores.js` validates: barter
ids exist in the item defs, qty 1..99, the either/or rule.
`Stores.lua` mirror carries the same entries.

**Starting barters** (general_goods — a seed list to expand later).
Pricing guideline: the cost's total sell value lands at ~80–90% of the
item's old gold price, so farming the mats beats paying gold; raw
material exchanges tax ~50%:

| You get | You give | Cost worth | Notes |
|---|---|---|---|
| ring_vitality | 25 slime_goo + 10 goblin_ear | 125g (was ◈150) | farm-gated ring |
| ring_focus | 25 slime_goo + 10 goblin_ear | 125g (was ◈150) | farm-gated ring |
| stone ×1 | 2 wood | 4g (stone sells 2g) | material exchange — a buy route stone never had |

Both rings deliberately lose their 150g gold offers (the either/or
rule); deleting the barter reverts that if it plays badly.

### 5.4 `StoreDeal` remote (replaces `StoreTrade`)

```lua
-- request (client → VendorService)
{ storeId = "general_goods",
  lines = {
    { side = "buy",  itemId = "sword_iron", quantity = 1 },
    { side = "sell", itemId = "wood", quantity = 50 },
    { side = "sell", itemId = "ring_lynx", x = 3, y = 7 }, -- rolled: positional, qty 1
  } }
-- response: { ok = true } | { ok = false, error = "no_gold" | ... }
```

VendorService: validate shape (≤ 24 lines), `nearVendor`, every line
tradable with the right side (buy → `buyPrice`/`barter`; sell →
`sellPrice` or `buysGear` + trait lines), quantities, positional lines
resolve to a matching main-grid entry. Then PRICE the deal
(trade prices + `ItemValue` + barter costs expanded into removes),
build the `{goldDelta, removes, adds}` plan, and settle it via
`PlayerService.executeDeal` (§7). No partial execution exists anymore —
the response is binary and the client keeps the zone on failure.
`StoreTrade` is deleted with the old UI.

New `ERROR_TEXT` codes: `bad_line` ("That trade isn't valid anymore"),
`too_many_lines` ("Deal too large").

## 6. Client architecture

Two extractions make all three panes cheap, then StoreUI is a rebuild:

1. **`client/ItemTooltip.lua`** — lift InventoryUI's §6.5 tooltip
   (rarity-tinted stroke, name/level/type rows, trait lines, stat line)
   into a module both screens require: `ItemTooltip.show(gui, entryOrDef,
   screenPos)` / `.hide()`. InventoryUI switches to it in the same PR —
   it's the regression test that the extraction is faithful.
2. **`client/ItemGrid.lua`** — the one grid view (destined to replace
   InventoryUI's grid too — consolidation decided): takes a column
   count and entries `{ itemId, quantity, x?, y?, meta?, price?,
   dimmed?, locked? }`, renders footprint tiles (viewport thumb, rarity
   stroke, qty badge, price chip, lock badge), diffs tiles across
   updates, and exposes `onClick(entry, shift)` / `onDragOut` / hover
   callbacks plus `placeFirstFit(entry)` (unrotated-then-rotated
   packing — used by the stock pane's shelf layout AND the deal grids'
   auto-placement). Within-grid drag/rotate lands with the InventoryUI
   migration (§8 step 8), not before.
3. **`client/StoreUI.lua`** — rebuilt: three panes, deal state (two
   ItemGrids + line records `{ side, itemId, quantity, x?, y?, meta?,
   barterFor? }`), quantity popover, DEAL via `StoreDeal`. Keeps:
   `OpenStore` wiring, `InventoryUpdated` + `RequestInventory`
   inventory mirror, `Gold` attribute readout, `ERROR_TEXT` mapping.

`ClientState.storeOpen` + the ShiftLockController read and the
InventoryUI/StoreUI mutual-close are the only touches outside these
files. Quick-bind/equip hover keys stay inventory-only.

## 7. Server changes

- **`VendorService`**: `handleTrade` → the `StoreDeal` handler (§5.4).
  Vendor building, prompts, `VENDOR_DEFS`, `nearVendor` unchanged.
- **`PlayerService.executeDeal(player, plan)`**: calls
  `POST /player/:id/deal`, on success swaps in the returned inventory +
  gold (cache, `Gold` attribute, `onInventoryChanged`, client push —
  the `refreshInventory` path), maps 409 codes through.
- **Backend**: the `/deal` route + handler (§5.2); `stores.js` barter
  validation (§5.3). `content/stores.json` + `Stores.lua` gain
  `buysGear` and the first barter entries.

## 8. Implementation checklist

1. Backend: `POST /player/:id/deal` + `stores.js` barter/`buysGear`
   validation (verify: `node -e "import('./src/stores.js')"` and a
   local `/deal` smoke test with rollback cases).
2. `shared/ItemValue.lua` + unit sanity in a Studio command bar (the
   §5.1 examples) · `PlayerService.executeDeal` ·
   `VendorService.StoreDeal` (keep `StoreTrade` alive until step 5).
3. `ItemTooltip.lua` extraction + InventoryUI switched to it (no visual
   change — screenshot-compare the Lynx Ring tooltip).
4. `ItemGrid.lua`: tiles, chips, badges, diffing, `placeFirstFit`,
   click/shift/drag-out hooks.
5. StoreUI rebuild: three panes, deal grids, click/shift-click routes,
   popover, DEAL; delete `StoreTrade`.
6. Drag & drop (stock → deal, pack → deal, deal → out) + barter locked
   tiles + barter chips on stock tiles.
7. Polish: dimming + "Not traded here", ghosted committed quantities,
   auto-close on walk-away, `ClientState.storeOpen` cursor wiring.
8. **InventoryUI migration onto `ItemGrid`** (adds within-grid drag +
   rotate + shift-click auto-equip quick-move) — after the store ships.
9. Docs: CLAUDE.md (routes line, StoreUI/VendorService/new modules),
   UI.md §8 vendor layout, this file's status.

## 9. Verification

- `luau-analyze` on every touched Luau file; backend content validation
  via the import checks in step 1.
- Manual, in Studio at Marla:
  1. Buy 1 sword + sell 50 wood in one deal → net settles, toast fires,
     grids refresh; check the backend `gold`/inventory match.
  2. Net short on gold → DEAL disabled; remove the buy tile → enabled.
  3. Fill the pack, buy a 2×2 piece alongside a valid sell → 409
     `no_space`, NOTHING changed (gold and sold items intact), zone
     preserved.
  4. Rolled goblin drop: pack tile shows the `ItemValue` chip
     (badge math matches the §5.1 table), sells via shift-click, meta
     row gone after the deal; a spread roll prices below a concentrated
     roll of the same level.
  5. Barter item: adding it auto-adds locked costs, missing costs
     disable DEAL, success removes costs + grants the item atomically.
  6. Shift-click: vendor tile → full stack regardless of gold; pack
     tile → whole stack; popover clamps at owned/99; deal grid refuses
     adds when full.
  7. Tooltips on all three panes match the inventory's; dimmed
     non-traded tiles say so.
  8. Open inventory (B) while trading → store closes (and vice versa);
     walk 20+ studs away → panel closes itself; small viewport →
     `autoScale` keeps all panes usable.

## 10. Open questions

1. **Value tuning** — the exponent is locked at 1.85; K = 3 / FLOOR = 5
   are still first-pass, so check a goblin-farming session's gold/hour
   before locking them. If the exponent ever gets retuned, stay above
   ≈1.82 or concentrated rolls stop beating spread ones (§5.1).
2. **Barter economy check** — do the §5.3 seed barters play well
   (rings farm-gated, wood→stone exchange), and which items join the
   list next?
