# FAMANA Art Backlog — Style A (Faceted low-poly)

The game's art direction is **Style A: faceted low-poly** — visible irregular
triangle facets, flat colors (no textures), one mesh per asset. Reference file:
[`roblox/src/assets/StyleIterations/FAMANA_StyleIterations.blend`](../roblox/src/assets/StyleIterations/FAMANA_StyleIterations.blend)
(comparison renders live next to it). Game-ready exports live in
[`roblox/src/assets/StyleA/`](../roblox/src/assets/StyleA/) — one folder per
asset, OBJ + MTL, exported at **×3.5 scale (≈ studs)**, bottom-centered at the
origin, Y-up.

**Creature recipe** (proven on goblin/slime/wolf): overlap anatomy primitives →
voxel remesh into one body → decimate to ~1–2k irregular tris → flat shade;
eyes/teeth/cloth/gear stay separate colored parts, joined at the end.

## Done — exported to `assets/StyleA/`

| Asset | Game mapping | Tris |
|---|---|---|
| Goblin | `goblin` enemy (EnemyService) — club included, CoC-style approved look | ~3.9k |
| Slime | `slime` enemy | ~550 |
| TreeOak | `tree` node (GatheringService, yields wood) | ~300 |
| RockStone | `rock` node (yields stone) — plain variant | ~160 |
| RockCopper | `rock` node with copper-bonus flavor (proud orange crystals) | ~240 |
| RockIron | `iron_rock` node (yields iron_ore) | ~280 |
| RockCluster | decorative multi-rock cluster (copper + iron mixed) | ~580 |
| RockGold | future gold-ore node / rare vein | ~260 |
| TreePine | decor / future tree variant | ~140 |
| Stump | decor (felled-tree marker) | ~100 |
| Sword | `sword_basic` visual reference | ~80 |
| Staff | `staff_basic` (emissive orb crystal) | ~120 |
| Bow | `bow_basic` | ~120 |
| Axe | `axe_basic` | ~100 |
| Pickaxe | `pickaxe_basic` | ~90 |
| Forge | `simple_forge` station (emissive ember mouth) | ~160 |
| Chest | loot container / decor (not yet a game item) | ~150 |
| LogBench | decor seat | ~140 |
| Campfire | decor / candidate cooking station (emissive flames) | ~290 |

Also in the .blend but not exported: **Wolf** (~1.8k tris, `StyleA_Expanded`) —
ready if a wolf enemy gets added; v1/v2 goblins kept for reference only.

## Equipment catalog — DONE (uploaded + wired via MeshAssets.lua)

All 21 built 2026-07-11 in the .blend's `Equipment` collection (row y=-18):
`axe_copper` · `pickaxe_copper` · `sword_iron` · `sword_duelist` · the full
leather set (helmet/chest/gloves/legs/boots) · `helmet_bastion` ·
`chest_colossus` · `boots_evader` · all 6 rings/emblems + the 3 that had no
model (`emblem_light_priest`, `emblem_holy_avenger`, `emblem_oracle`).

## Camp + resource catalog — DONE (uploaded + wired)

Built 2026-07-12 in the .blend's `CampProps` collection (row y=-24): all camp
furniture meshes (tent, crafting table, cauldron, rug, lantern, trophy — chest
and forge reuse the earlier uploads), the tier-scaled campfire dressing, the
`hardwood_tree` node, and every remaining item model: `wood`, `hardwood`,
`stone`, `slime_goo`, `goblin_ear`, `torch`, `arrow`, `copper_ore`,
`iron_ore`, `copper_ingot`, `iron_ingot`, plus thumbnails for all seven
furniture items. Consumers wired mesh-first: CampFurnitureService (invisible
anchors sized like the old ArtKit primaries), CampService's campfire
(meshScale per tier; tier-2 tripod + tier-3 banners stay ArtKit accents),
CraftingService.buildTable, GatheringService hardwood_tree.

World content without a model:

- [ ] `hardwood_tree` node — needs a visually distinct tree (darker/denser than TreeOak)
- [ ] `crafting_table` station — has an ArtKit spec only; wants a Style-A mesh
- [ ] **Marla the Trader** (`general_goods` vendor) — humanoid NPC, biggest missing piece

## Tree pack + variant pools — DONE (2026-07-12)

The externally-generated `new_art_style/` pack (4 species) is conformed,
uploaded and wired: `tree` node = green oak ×3 variants, `hardwood_tree` =
autumn oak ×3; `conifer_tree` and `dead_tree` pools (×3 each) are loaded but
unwired — use them via authored-map decoration or future nodes/biomes.
World defs support `assetIds` variant arrays + random yaw per placement.
Style rules: [`ART_STYLE.md`](ART_STYLE.md).

## To upgrade — ArtKit remnants (all optional)

- [ ] NPCs: **Marla the Trader** (vendor) + quest givers — humanoid meshes,
  the last big visual identity piece (use the goblin's remesh pipeline)
- [ ] ItemStandService's stone pedestal, CampService zone posts/rails,
  BorderService/world dressing — minor procedural props, fine as ArtKit
- [ ] `acampada` (camp kit item) thumbnail, slime enemy (kept ArtKit by choice)

## Nice-to-have world props (no game system yet, pure ambience)

Crates & barrels · fences · a well · vendor market stall (for Marla) · signposts
· banners · bushes/grass clumps · mushrooms · ruins/wall pieces · small bridge ·
border/teleport markers for cell edges.

## Roblox uploads (Open Cloud)

All 19 assets are uploaded to Roblox as Model assets (FBX) under the key
owner's account. Asset ids live in
[`roblox/src/assets/StyleA/ROBLOX_ASSET_IDS.md`](../roblox/src/assets/StyleA/ROBLOX_ASSET_IDS.md)
(+ `roblox_asset_ids.json` for scripts). Re-upload / upload new assets with
`node scripts/upload_styleA_assets.mjs [NameFilter]` — it reads
`ROBLOX_API_KEY` from `.env`, skips names already in the manifest. Insert in
Studio via Toolbox → Inventory → My Models, or `InsertService:LoadAsset(id)`.

**The game loads these at boot.** `shared/MeshAssets.lua` maps game ids →
asset ids; `server/MeshAssetService.lua` inserts them on server start (item
models into `ReplicatedStorage.Assets` — the override folder ToolService/
ItemModels honor — world models into `ReplicatedStorage.MeshModels`, cloned
by EnemyService/GatheringService/CraftingService). Every consumer falls back
to its ArtKit look when a load fails, so Studio-without-asset-access keeps
working. To swap a model: re-upload, put the new id in `MeshAssets.lua`.

## Importing into Studio (manual OBJ route)

1. Studio → **Asset Importer** (Home → Import 3D) → pick the `.obj`.
2. Import as a single Model; Studio splits it into one MeshPart per material —
   keep them grouped, set a **PrimaryPart** (gameplay anchor; gathering nodes
   carry the `Depleted` attribute on it, see CLAUDE.md).
3. Scale is already ≈ studs (goblin ≈ 4.7). No rescale needed.
4. Emissive parts (staff orb, forge mouth, campfire flames) import as plain
   colors — set those MeshParts' `Material = Neon` in Studio to restore the glow.
