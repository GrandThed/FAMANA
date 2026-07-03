# Grid Inventory — Idea Dump

Working document for redesigning FAMANA's inventory from the current flat
20-slot list into an **Escape from Tarkov-style grid**. Nothing here is
decided; it's a place to dump ideas, mark what we're stealing from Tarkov,
what we're skipping, and what has to change in the codebase.

Current state (for reference): backend stores `(player_id, slot_index,
item_id, quantity)` with `slot_index` 0–19; `Config.inventoryCapacity = 20`;
`InventoryUI` renders a flat list; hotbar mirrors the first 6 slots.

---

## 1. What actually makes Tarkov's inventory *Tarkov*

Extracted core mechanics, roughly ordered by how load-bearing they are:

1. **Items have a footprint (W×H cells), not a slot.** A sword is 1×3, a
   pickaxe 2×3, wood might be 1×1. Space is the resource; the grid is the
   budget. This is *the* core idea — everything else hangs off it.
2. **Spatial placement matters.** You choose *where* an item goes. Packing is
   a mini-puzzle; a messy inventory wastes space. Emergent "inventory Tetris."
3. **Rotation.** Items can be placed horizontally or vertically (R key while
   dragging). Doubles packing options; makes odd shapes (1×4 staff) usable.
4. **Containers inside the grid.** A backpack is an item with its own
   sub-grid. Nesting rules prevent infinite recursion (no backpack in a
   backpack, or limited depth). Containers can *compress* (a 5×5 bag occupying
   4×4 outside) or just organize.
5. **Multiple distinct grids per character, not one bag.** Pockets (small,
   always available), backpack (big, an equippable item), rig/belt (quick
   access), secure container (never lost). Equipment slots (weapon, armor)
   sit *outside* the grid.
6. **Drag & drop as the primary verb**, with hover highlighting
   (green = fits, red = blocked), plus quality-of-life shortcuts
   (ctrl-click quick-move, auto-sort button).
7. **Stacking is per-cell.** Stackable items still occupy one footprint;
   quantity lives on the stack. Drag-onto-same-item merges; drag with a
   modifier splits.
8. **Item inspection / tooltips.** Hover shows name + stats; the grid tile
   shows an item icon that spans its footprint (this is why Tarkov icons are
   rendered per-item — our `ItemModels.preview` ViewportFrames already do
   exactly this).
9. **Weight as a second, softer limit** (movement penalties past thresholds)
   — space limits *what you carry*, weight limits *how much of the heavy
   stuff*.
10. **Loot containers in the world share the same UI** — a corpse, crate, or
    stash opens as another grid panel next to yours; moving loot is the same
    drag interaction everywhere.

### What we probably *don't* want from Tarkov

- Durability/condition per item instance (big data-model cost; not needed
  yet — but see "instance vs stack" below, it forces the same decision).
- Insurance / found-in-raid flags, ammo-in-magazine nesting, weapon modding
  grids — Tarkov-specific.
- Secure container as a *death-protection* mechanic only matters if FAMANA
  gets loot-drop-on-death. Park it.

---

## 2. Why this fits (or fights) FAMANA

**Fits:**
- Imperium AO / old-school MMO vibes reward inventory management as gameplay.
  Deciding whether to haul 50 wood or keep room for drops *is* content.
- We already render per-item 3D thumbnails (`ItemModels.preview`) — spanning
  a 2×3 tile with a viewport is a straight extension.
- Data-driven item defs make footprints one more stat: `size = {2, 3}`
  next to `reach` and `maxStack`, mirrored in `items.js`/`Items.lua` like
  everything else.

**Fights:**
- Backend `inventory.js` add/remove is stack-filling over a flat index; a grid
  needs 2D placement logic *server-side* (backend stays source of truth).
- Drops/gathering currently auto-add items. With a grid, "no room" becomes
  *shape-dependent* ("you have 3 free cells but not a 1×3 line"). Pickup UX
  needs an answer (see Open Questions).
- The hotbar mirrors "first 6 slots" — meaningless in a grid. Hotbar needs to
  become its own thing (assignment-based, or a dedicated belt grid).
- Roblox UI: no native drag-drop; we build it from `InputBegan` +
  `GuiObject.AbsolutePosition` math. Doable, but it's the biggest client task.

---

## 3. Target layout (decided)

Two-column inventory screen:

```
+--------------------+---------------------------------------------+
|  PLAYER EQUIPMENT  |  UTILITIES:  [Sort]  [ ... ]    Gold: 1,234 |
|                    +---------------------------------------------+
|      [helmet]      |                                             |
| [weapon]  [chest]  |            ITEMS GRID                       |
| [offhand] [gloves] |            10 wide x 30 tall                |
| [ring 1]  [legs]   |            (vertical scroll)                |
| [ring 2]  [boots]  |                                             |
|      [back]        |            "basic backpack" size —          |
+--------------------+            bigger packs = more rows         |
|  EFFECTS           |                                             |
|  (buffs/debuffs)   |                                             |
|  [icon][icon][..]  |                                             |
+--------------------+---------------------------------------------+
```

- **Left column (top): equipment paper doll.** Dragging an item onto a slot
  equips it. Slot list (decided): **helmet, chest, gloves, legs, boots,
  weapon, offhand, back, ring ×2**. Armor/ring items don't exist yet — asset
  specs in §8.
- **Left column (bottom): effects panel.** Active buffs/debuffs as icons with
  timers. *New system* — nothing tracks effects today. Decided starting
  point: build the buff/debuff framework with one real effect — a **slowness
  debuff applied when a slime hits you** (walkspeed reduction with a timer,
  icon in this panel).
- **Right column (top): utilities bar.** Sort button (server-side repack) and
  **gold** readout. Gold is a `players.gold` column on the backend (not a
  grid item — it doesn't take space); Roblox owns it live (like health) and
  autosave persists it. Mirrored to a `Gold` Player attribute for UI. Later:
  vendors/trade, admin-dashboard editing.
- **Right column (main): the items grid.** Fixed **10 cells wide**, vertical
  scroll, **30 rows** for the basic backpack (300 cells). Width staying fixed
  at 10 keeps every footprint/placement mental model stable; progression
  grows **rows**, not columns.

### Hotbar (decided — Tarkov-style)

The HUD hotbar keys work like Tarkov's quick binds:

- **Keys 1 and 2 are reserved for the main weapons** — whatever sits in the
  weapon and offhand equipment slots. Not reassignable.
- **Keys 3–0 are player-assigned quick binds**: hover an item in the grid and
  press 3–0 to bind it to that key. **Only tools and consumables** can be
  bound (no weapons — those live on 1/2; no resources).
- Binds are references to grid items, not copies — if the item leaves the
  grid, the bind empties. Pressing a bound key equips/uses the item.

## 4. Idea dump (unfiltered)

- Footprints for current items: sword 1×3, iron sword 1×3, axe 2×3 (or 1×3?),
  pickaxe 2×3, staff 1×4, wood 1×1 ×50, stone 1×1 ×50, goo 1×1, ear 1×1.
  Resources as 1×1 high-stack keeps gathering forgiving.
- **Backpacks as progression**: with the fixed-10-wide layout, a bigger pack
  = more *rows* in the main grid (basic 30 → bigger tiers add rows). Crafted
  from gathered materials — gives gathering→crafting a purpose and makes
  inventory space a *reward*. Simpler than Tarkov's bag-with-sub-grid: the
  equipped back-slot item just *sets the grid height*.
- **Equipment slots = the paper doll** (see §3): moving the sword to the
  weapon slot = equipping. Merges inventory and equip UX.
- Belt/rig = the hotbar: a 6×1 quick-access strip; only items on the belt
  appear in the HUD hotbar and can be hot-equipped. Solves the "first 6
  slots" hack elegantly.
- Rotation: store as a boolean `rotated` per placed item; R while dragging.
- Auto-sort button (server-computed repack) — cheap goodwill feature.
- Quick-move (ctrl-click): server finds first fitting spot — reuses the same
  placement search as pickups.
- Ground drops could open as a tiny 1-item grid, or stay ProximityPrompt
  auto-pickup with a "make room" toast on shape failure.
- Weight later, if ever — mana/HP orbs HUD could gain a subtle encumbrance
  tint rather than a third bar.
- Shared-UI loot panels set up future features for free: chests, corpses,
  trade windows, bank stash in a town cell are all "second grid panel."
- Cell-themed stash idea: a persistent per-player stash *per grid cell*
  (bank building) — spatial economy across the world grid. (Way post-MVP,
  but the grid-inventory data model should not preclude it: keep a
  `container_id`/`owner` concept rather than hardcoding "the player's grid".)

---

## 5. Data model sketch (backend = source of truth)

Replace `slot_index` with placement:

```sql
inventory_items (
  player_id,
  container_id,   -- 'main' | 'equipment' | 'belt' | future: stash id
  x, y,           -- top-left cell of the footprint
  rotated,        -- boolean
  item_id,
  quantity
)
```

Plus, per the §3 layout:

- `players.gold BIGINT NOT NULL DEFAULT 0` — **implemented**. Currency lives
  on the player row, not in the grid. Follows the health authority model:
  Roblox server mutates it live (`PlayerService.addGold/spendGold`), the
  `Gold` Player attribute drives UI, autosave/leave persists it via the save
  endpoint. Admin dashboard editing (+ audit) is a follow-up.
- Equipment slots can be modeled as `container_id = 'equipment'` with `x` =
  slot enum index and a 1×1 "footprint" — keeps one table/one move API for
  grid↔equip drags.
- Effects: **not** in this table. Live server state first (like Mana);
  persistence only if effects should survive teleports/logout.

- Server validates every placement: footprint (from item def + rotation) must
  be in bounds and not overlap any other footprint in that container.
- `addItem` becomes **find-first-fit**: scan positions (try unrotated, then
  rotated), fill partial stacks first — same spirit as today's stack-filling,
  now in 2D. Keep it in the transaction like today.
- New op alongside add/remove: **`moveItem`** (container, x, y, rotated →
  container, x, y, rotated) including split/merge of stacks. This is the new
  verb the UI drives; add/remove stay for gameplay grants.
- **Instance vs stack — decided: no instance ids.** Backpack tiers set grid
  rows instead of nesting sub-grids, so per-item instances are unnecessary.
- Migration for existing players: repack their flat slots via find-first-fit
  on first load (reuse `loadPlayer`'s reconcile pass).

## 6. Rough scope tiers

- **Done:** gold stat (backend `players.gold` column + save/load +
  `PlayerService.addGold/spendGold` + `Gold` Player attribute).
- **V1 (the core loop):** the §3 layout shell (two columns) with the main
  10×30 grid + footprints + rotation + drag-drop + server `moveItem` +
  find-first-fit pickups + migration + full equipment paper doll (all §3
  slots visible; weapon/offhand functional first). Sort button + gold
  readout. Tarkov-style hotbar (1/2 = weapons, 3–0 = quick binds). Effects
  panel + buff/debuff framework with the slime slowness debuff.
- **V2:** armor/ring items live (assets in §8, then defense/bonus stats in
  combat), quick-move, split stacks, backpack tiers = grid rows, admin
  dashboard gold editing.
- **V3:** more effects (potions/food), world loot containers sharing the UI,
  vendors/trade using gold.
- **Someday:** weight, per-cell stash/banks, trade windows.

## 7. Decisions (all open questions resolved)

1. **Grid size: 10×30** (downsized from the 10×50 first pass — 300 cells
   keeps some space pressure while staying roomy).
2. **Pickup failure:** the drop simply stays on the ground — no toast, no UI.
   For stackables, pick up as much as fits (partial pickup).
3. **Hotbar:** Tarkov-style quick binds (see §3): keys 1/2 reserved for the
   equipped main weapons; keys 3–0 bindable from the grid, tools and
   consumables only.
4. **Paper doll:** all standard armor pieces — helmet, chest, gloves, legs,
   boots — plus weapon, offhand, back, and **two ring slots**.
5. **Effects:** implement the buff/debuff system now, starting with a
   **slowness debuff applied when a slime hits you**.
6. **Instance ids:** not needed (backpack tiers = grid rows, no sub-grids).
7. **Mobile/gamepad:** out of scope.

## 8. Asset spec: armor & rings (to build)

The paper doll needs items to fill it. First set: a **leather tier** of the
five armor pieces plus two rings. Everything follows the existing item
pipeline — no new systems needed for the *assets* (combat stats come later).

### Checklist for each new item (existing conventions)

1. Add the def to `backend/src/items.js` **and** `roblox/src/shared/Items.lua`
   (ids/defs must match — see CLAUDE.md).
2. Add the model to `roblox/src/shared/ItemModels.lua` as an ArtKit spec list:
   - first spec = primary part at the origin (no `offset`);
   - colors are `ArtKit.Palette` keys only — no inline RGB;
   - that one spec list automatically serves inventory/hotbar thumbnails
     (`ItemModels.preview`) and ground drops (DropService). Armor is never a
     held Tool, so grip orientation doesn't matter — model it to read well in
     a thumbnail (front facing −Z works well with the preview camera).
3. Optional: an `ItemStandService` pedestal or admin grant to test in-game.

### Palette additions needed (ArtKit.Palette)

Leather has no palette entry yet. Proposed (flat, matches the muted look):

```lua
-- armor / trinkets
leather = Color3.fromRGB(146, 96, 56),
leatherDark = Color3.fromRGB(104, 66, 38),
ruby = Color3.fromRGB(200, 62, 70),
sapphire = Color3.fromRGB(64, 112, 200),
```

(`gold`, `steel`, `steelDark` already exist and cover buckles/bands.)

### Item defs (new `type = "armor"` / `"ring"`, with a `slot` field)

| id | name | slot | footprint (W×H) | notes |
|---|---|---|---|---|
| `helmet_leather` | Leather Helmet | `head` | 2×2 | |
| `chest_leather` | Leather Tunic | `chest` | 2×3 | biggest piece |
| `gloves_leather` | Leather Gloves | `hands` | 2×2 | modeled as a pair |
| `legs_leather` | Leather Leggings | `legs` | 2×2 | |
| `boots_leather` | Leather Boots | `feet` | 2×2 | modeled as a pair |
| `ring_vitality` | Ring of Vitality | `ring` | 1×1 | gold band + ruby |
| `ring_focus` | Ring of Focus | `ring` | 1×1 | steel band + sapphire |

All `stackable = false, maxStack = 1`. Both rings use `slot = "ring"` and fit
either ring slot. Stats deliberately deferred — add `defense` (armor) and
attribute bonuses (rings: vitality → max HP, focus → max mana) when equipment
affects combat; the defs just need `type`/`slot` for the paper doll to accept
them.

### Model sketches (ArtKit spec guidance, chunky low-poly)

- **helmet_leather** — dome from 2–3 stacked blocks: a wide `leather` skull
  block, a `leatherDark` brow band slightly larger, small `steelDark` rivet
  cubes at the temples. ~1.2 studs across.
- **chest_leather** — `leather` torso block (~1.4×1.6×0.7), `leatherDark`
  shoulder blocks on top corners, a vertical `leatherDark` lacing strip on
  the front, `gold` buckle cube.
- **gloves_leather** — two mirrored mitts: `leather` hand blocks with
  `leatherDark` cuff blocks, offset ±0.5 on X so the pair reads in one tile.
- **legs_leather** — waist block + two leg columns in `leather`, `leatherDark`
  belt band with a `gold` buckle.
- **boots_leather** — two mirrored boots: `leather` shaft column + a
  forward-jutting `leatherDark` foot block each (wedge for the toe reads
  nicely).
- **ring_vitality / ring_focus** — small torus faked with 4 thin blocks in a
  square (or one `Cylinder` rotated upright), `gold`/`steel` band; a `ruby`/
  `sapphire` gem cube (rot 45°) on top, `material = Neon` for a soft glint.
  Keep tiny (~0.5 studs) — it's a 1×1 tile.

Enemy/loot integration idea (later): goblins drop leather scraps → craft the
set; rings as rare drops or first vendor items (gold sink).
