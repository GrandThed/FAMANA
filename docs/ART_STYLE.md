# FAMANA Visual Style Guide — Geometric Low Poly

The world-art style, distilled from the visual-style-guide poster and the
[`new_art_style/`](../new_art_style/) tree pack (see its README for a worked
example of the pipeline). UI style lives separately in [`UI.md`](UI.md).

## The five rules

1. **Geometric low-polycount.** Big flat polygons, bold silhouettes. Budget
   guide: props 100–600 tris, gathering nodes 300–3k, creatures 500–4k.
   Detail comes from *shapes*, never from surface noise.
2. **Sharp edges, defined planar facets.** Flat shading everywhere — the
   facet look comes from the normals. No subdivision smoothing, no bevels
   for their own sake. Slight vertex jitter makes facets read hand-sculpted.
3. **Flat color planes.** One plain color per material, no textures, no
   gradients painted into the mesh. Every color comes from the shared
   palette (`shared/MeshAssets.lua` → `MeshAssets.palette`); in Blender,
   materials are named after their palette key (`fam_*` / `m_tree_*`) —
   that name is what colors the part in game.
4. **Defined by light, not lines.** Zero outlines, zero cel-shading.
   Adjacent facets separate through shading alone — keep material colors
   far enough apart in value that planes read under the game's sun.
   Emissive accents (`*_emit` materials) become Neon in game and carry
   PointLights (staff orb, forge mouth, campfire, lantern).
5. **Clean viewport.** SmoothPlastic everywhere (the pipeline enforces it),
   sober palette with ONE accent per asset (an ember, a crystal, a gem).
   Scale is studs: 1 Blender meter × 3.5; a character is ~5 studs, the
   goblin 4.7, oaks ~16, the conifer ~23.

## Variants over repetition

Natural things (trees, rocks) ship as **variant pools** — the same species
with small differences (±10% non-uniform scale, a few degrees of trunk
twist, re-seeded jitter), never different silhouettes. The mesh loader
picks a random variant per placement plus a random yaw, so no two nodes
match. Three variants per species is the sweet spot.

## Pipeline (the short version)

1. Model in Blender at meters, Z-up, front facing −Y, origin at the base.
   One object; materials named after palette keys.
2. Export via the baked-FBX script pattern (`famana_*_items.py` in %TEMP%,
   documented in memory + `ART_BACKLOG.md`): bake rotation/scale into
   vertices, split one object per material, bottom-center.
3. Upload: `node scripts/upload_styleA_assets.mjs <Name>` → id lands in the
   manifest; add it to `shared/MeshAssets.lua` (+ palette entries if new).
4. The game does the rest: `MeshAssetService` loads, recolors by material
   name, glows the `*_emit` parts, and every consumer falls back to ArtKit
   if the load fails.

## References

- Poster + concepts: `new_art_style/` (Gemini concept images, tree pack)
- Style comparisons and renders: `roblox/src/assets/StyleIterations/`
- Working file: `FAMANA_StyleIterations.blend` (collections: Iter_* history,
  StyleA_Expanded, Equipment, CampProps, NewTrees)
