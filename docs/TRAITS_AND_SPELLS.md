# Traits (Rasgos) & Subclass Spells

Design + status doc for the stats overhaul kicked off from the "Rasgos" board
(TFT-style trait system on equipment + subclass spells per class).

Two halves:

1. **Traits on equipment** — designed, NOT implemented yet. This doc captures
   the rules as understood, every open question, and a recommended starter set
   so testing can begin with minimal plumbing.
2. **Subclass spells** — implemented (first pass). Everything on the board's
   right side is castable in game today, plus the hotbar systems around it.
   See [What shipped](#part-2--subclass-spells-implemented).

---

## Part 1 — Trait system (design)

### The idea (as understood)

- Every piece of equipment (weapons, armor, rings) carries **traits** with
  levels, like TFT origins/classes.
- Every item has an **item level**; the sum of its trait levels **equals** the
  item level (e.g. a level 7 sword = Ojo de Lince 4 + Manos Ágiles 3). Random
  rolls make almost every item unique.
- The player's **total per trait** (summed across equipped items) is compared
  against that trait's **thresholds** — you get the highest tier you reached,
  TFT-style (points between thresholds do nothing extra).
- A player **cannot equip an item whose level is above their own level**.
- UI: a TFT-style trait panel beside the inventory showing every trait you
  have points in — active tiers lit, inactive ones grayed but still described.

### Trait catalog (transcribed from the board — numbers are placeholders)

**Ofensivos**

| Trait | Thresholds (trait level → effect) |
|---|---|
| Ojo de Lince (crit) | 1→+10% · 4→+20% · 7→+30% · 10→+35% · 13→+40% · 16→+50% · 20→+65% · 22→+90% crít |
| Manos Ágiles (vel. ataque) | 1→+10% · 4→+20% · 7→+30% · 10→+35% · 13→+40% · 16→+50% · 20→+65% · 22→+90% vel. ataque |
| Perseverancia (duración de habilidad) | 3→+5% · 7→+10% · 11→+15% |

**Defensivos**

| Trait | Thresholds |
|---|---|
| Matón (vida + regen) | 2→+20% vida, 2%/s · 5→+35%, 2%/s · 8→+50%, 4%/s · 11→+65%, 4%/s · 16→+80%, 6%/s · 22→+100%, 6%/s |
| Bastión (armadura + res. mágica) | 2→10 · 5→25 · 8→40 · 11→80 · 16→110 |
| Evasión (esquiva) | 5→5% · 7→7% · 9→9% · 11→11% · 13→13% · 15→15% · 17→17% |
| Guardián (escudos a aliados) | 2→10% prob. de escudar a un aliado al ser golpeado · 5→20% · 8→aura +8 armadura en área · 11→30% · 16→aura +15 · 22→el escudo también cura vida faltante |

**Utilidad**

| Trait | Tiers |
|---|---|
| Rodar | 1→rodar simple, 0.3s iframes · 3→rodar simple, 0.5s iframes · 5→rodar invisible, 0.5s iframes, pierde agro |
| Dash | 1→dash simple · 3→dash + vel. movimiento · 5→dash atraviesa enemigos |
| Regeneración de maná | (sin números aún) |
| Habilidades de recolección | (sin números aún) |

### Open questions

**From the board itself**
- ¿Se pueden combinar subclases? (spell side — today: test mode grants ALL
  schools of your class; see Part 2)
- ¿Intentamos que cada clase tenga 1 subclase ofensiva, 1 defensiva, 1 más
  balanceada? (Centinela is already the knight's defensive one; mage has three
  offensive ones — Invocador could lean defensive/utility.)
- ¿Subclases prismáticas? (rare/special subclasses à la TFT prismatic traits?)

**Roll rules (needed before implementing the generator)**
- How many traits can one item roll? Suggestion: 1–2 for levels 1–6, 2–3
  above. 12 traits × 1 point each on a level 12 item would feel like noise.
- Minimum points per rolled trait (suggest ≥2 so a roll always "counts"
  toward a real threshold eventually)?
- Are trait pools **weighted by slot**? (armor → defensive bias, weapons →
  offensive, rings → anything, boots → utility?) Can a sword roll Matón?
- Can the same trait appear twice on one item? (Suggest no.)
- Do weapons keep their base stats (damage/reach/mana) **plus** traits, or do
  traits replace stats entirely? Suggest: base stats stay, traits are extra.
- Item level source: does a drop's item level come from the mob's level
  (±1–2)? From the zone/cell? Vendor items fixed level?

**Player-level gating**
- "Cannot equip above your level" — which level, given per-class tracks? The
  **active class's** level is the obvious answer, but then: what happens when
  you switch to a lower-level class while wearing high items? Options:
  auto-unequip (brutal), traits deactivate but item stays (recommended), or
  block the switch.
- Does the gate apply only on equip, or continuously?

**Combat model gaps (traits reference stats that don't exist yet)**
- **Armor / magic resistance** (Bastión, Centinela passive): no armor stat
  exists. Recommended formula: `reduction = armor / (armor + 100)` (42 armor ≈
  30% less damage) — this is what the Centinela spell passive already uses.
  Does "resistencia mágica" need to be a separate stat vs enemy magic damage
  (no enemy casts magic yet)?
- **Attack speed** (Manos Ágiles): today swings are gated by a fixed 0.4s
  debounce (`ToolService.SWING_COOLDOWN`) — attack speed = scaling that (and
  eventually animation speed).
- **Evasion**: needs a dodge roll on enemy hits (and a "Miss!" indicator).
- **Ability duration** (Perseverancia): scale `Effects` durations on apply.
- **Guardián**: needs an ally-shield concept (temp HP) and an aura system —
  and a definition of "aliado" (party? everyone nearby? guild later?).
- **Rodar/Dash**: needs an active-movement + iframe system, and a decision on
  where the ability lives (hotbar slot? dedicated key like Space/Q?). Also:
  iframes vs which attacks — melee only, or zones too?
- Stacking rules between trait bonuses and subclass passives (both give
  +% damage). Recommend: additive within a category, then multiply categories.

**Persistence (the big one)**
- Random-rolled traits make items **unique instances** — today
  `inventory_items` rows are just `item_id + quantity` and identical items
  stack/merge. Rolled items need a per-row `meta JSONB` (traits, itemLevel),
  must never stack, and every path that touches items (add/move/sort/drop
  pickup, vendor buy/sell, admin panel item grants) must carry the meta.
  That's a real backend migration — schedule it as its own step.
- Do vendors sell rolled items? Do rolled items have sell prices scaled by
  level?

**UI**
- Trait panel placement: side of the inventory panel (left column already has
  equipment + effects; a third section or a tab?). HUD mini-strip of active
  traits during combat?
- Tooltip on items must show their traits + how each contributes ("Bastión
  +3 → total 8/11").

### Recommended path to start testing (no backend migration)

**Phase A — fixed-trait items (recommended first step).** Put a hand-authored
`traits` map + `itemLevel` on a few item **defs** (`backend/content/items.json`
+ the `Items.lua` mirror). No schema change — identical items are still
identical. This exercises 90% of the system: aggregation, thresholds, the
trait UI, level gating, and the first trait effects, all with the content
pipeline that already exists.

Starter test set (sums always equal item level; kit designed so combining
pieces crosses thresholds):

| Item | Slot | Item lvl | Traits |
|---|---|---|---|
| Anillo del Matón | ring | 2 | Matón 2 |
| Anillo del Lince | ring | 3 | Ojo de Lince 3 |
| Casco de Bastión | head | 5 | Bastión 3 · Matón 2 |
| Espada del Duelista | weapon | 7 | Ojo de Lince 4 · Manos Ágiles 3 |
| Peto del Coloso | chest | 8 | Matón 5 · Bastión 3 |
| Botas del Evasor | feet | 9 | Evasión 5 · Matón 4 |

Full kit totals: Matón 13 (tier 11 ✓), Bastión 6 (tier 5 ✓), Ojo de Lince 7
(tier 7 ✓), Manos Ágiles 3 (below 4 ✗ — visible as "3/4" in the UI), Evasión
5 (tier 5 ✓). Perfect for verifying partial progress display.

First trait effects to wire (all have pipelines ready after the spell work):
1. **Ojo de Lince** → add to the crit chance in `EnemyService.computePlayerDamage`.
2. **Bastión** → a `registerDamageTakenMult` hook (armor formula above).
3. **Matón** → MaxHealth mult in `HealthService` + regen amount.
4. **Manos Ágiles** → scale `SWING_COOLDOWN` per player in `ToolService`.
5. **Evasión** → dodge roll where enemies call `TakeDamage`.
6. **Perseverancia** → duration mult in `EffectService.apply`.

Defer to later phases: Guardián, Rodar/Dash, recolección, mana regen trait.

**Phase B** — random roll generator + `meta JSONB` migration (items become
unique). **Phase C** — utility/active traits (movement system) + Guardián.

---

## Part 2 — Subclass spells (implemented)

Everything below is live in the codebase as of this pass.

### The spells

Unlocks follow the board: base at class level 1, second active at 10,
ultimate at 20. Passives (the board's +X% lines) apply automatically at
1/5/10/15/20 and boost **both spells and weapon swings**. All numbers are
first-pass and live in [`roblox/src/shared/Spells.lua`](../roblox/src/shared/Spells.lua).

| School (class) | Lvl 1 | Lvl 10 | Lvl 20 | Passive |
|---|---|---|---|---|
| Piromante (mago) | Bola de Fuego — projectile + splash | Muro de Llamas — flame wall zone | SuperNova — huge self AoE | +10…55% d.mágico |
| Arcano (mago) | Proyectil Arcano — fast/cheap bolt | Lluvia Arcana — zone on target | Tormenta Arcana — big zone | +10…50% d.mágico |
| Invocador (mago/invocador) | Invocar Familiar — pet that orbits + shoots | 2nd familiar (passive) · Lluvia Arcana at 15 | Gran Familiar — big angry pet | +6…35% d.mágico |
| Berserker (caballero) | Grito de Batalla — +daño físico buff | Golpe Salvaje — heavy strike | Frenesí — big damage + speed buff | +10…50% d.físico |
| Centinela (caballero) | Provocar — taunt + guard buff | Lealtad de Acero — armor buff (allies too) | Baluarte — 50% damage taken, allies too | +8…42 armadura |
| Justiciero (caballero) | Golpe Aturdidor — strike + stun | Juicio — AoE + mini-stun | Veredicto — huge strike + long stun | +10…35% d.físico |
| Francotirador (ranger) | Disparo Certero — precision shot (needs focus) | — | — | — |
| Trampero (ranger) | Trampa — **placeholder, not castable** | — | — | — |
| Explorador (ranger) | Sprint — speed buff | — | — | — |

The three ranger spells are **proposals** (the board only says
burst/CC/movement) — rename/redesign freely. Ultimates without board names
got working titles: Tormenta Arcana, Gran Familiar, Baluarte, Veredicto.

**Current unlock mode ("all schools"):** a player knows every spell of every
school of their *active* class at their class level — no subclass picking yet
(that's the board's own open question). When you decide, restricting is just
filtering `Spells.schoolsFor()` by a chosen subclass; same-stat passives
already take the max, not the sum, so test mode isn't overpowered.

### Systems built (and where to extend)

- **`shared/Spells.lua`** — schools, spell defs, unlock levels, passives,
  recommended-order helper, `spell:<id>` hotbar-bind helpers. Adding a spell =
  a def + a school entry; it unlocks, toasts, auto-places, renders and casts
  with zero extra wiring if it uses an existing behavior.
- **`server/SpellService.lua`** — cast validation (known → target → mana →
  cooldown, nothing charged on a whiff), 7 behaviors (`projectile`, `zone`
  box/disc with damage ticks, `strike` + stun, `aoe`, `buff` + ally radius,
  `taunt`, `summon` familiars that orbit and auto-attack), cooldowns mirrored
  as `SpellCd_<id>` attributes, unlock pushes on the Level/Class attributes
  (so admin-panel level edits unlock spells live too).
- **`EnemyService`** grew a public combat API: `computePlayerDamage` (class ×
  effects × passives × crit), `enemiesNear` / `focusedTarget` /
  `nearestTarget`, `dealSpellDamage`, `stun`, `taunt`, plus
  `registerDamageMult` / `registerDamageTakenMult` hooks — the same hooks the
  trait system should use for Ojo de Lince/Bastión (see Phase A).
- **`EffectService`/`Effects.lua`** — effects can now carry `damageMults` and
  `damageTakenMult` (Grito, Frenesí, Guardia, Lealtad, Baluarte, Sprint), and
  effect walkspeed finally respects the class's own walkspeed.
- **Hotbar (`HudUI` + `HotbarBinds` + `SpellsClient`)** — slots 3–0 accept
  spell binds; spell slots show the school-colored icon, a draining cooldown
  veil with seconds, and dim when mana is short or the spell belongs to a
  class you're not playing. Pressing the key (or clicking) casts.
- **Auto-place on unlock** — a newly unlocked spell lands in the next free
  hotbar slot; on a fresh profile the whole known list is seeded in
  recommended order. Full hotbar = not placed (v1: no replacement).
- **Recommendation system v1** — `hotbarPriority` on each def orders the
  loadout (bread-and-butter damage first, then AoE/buffs, utility, ultimates);
  the server sends the sorted list in every `SpellsChanged` push. v2 ideas:
  score by damage-per-mana and cooldown coverage, detect playstyle from the
  equipped weapon (melee vs bow vs staff), always keep 1 defensive; suggest
  replacements when something strictly better unlocks ("¡Mejora encontrada!").
- **Default binds** — fresh profiles start with the axe on key 3 and the
  pickaxe on key 4 (seeded server-side in `PlayerService.loadProfile`).
- **1/2 equips from the inventory** — hovering a weapon/tool in the grid and
  pressing 1 (weapon) or 2 (offhand) equips it; the current occupant swaps
  back to the first free grid spot (blocked with a message if the grid is
  full).

### Known gaps / open questions on the spell side

- Spell binds can't be **rearranged or removed** yet (items rebind by
  hovering; spells have no equivalent). Probably: drag between hotbar slots.
- No **spellbook UI**: you can't read descriptions of spells in game (defs
  have `description` ready). Natural home: the future trait/spell panel next
  to the inventory.
- Muro de Llamas is a straight wall **box zone**; Trampa needs a trap system
  (placed trigger); no knockback primitive exists for SuperNova.
- Stuns have no visual on the enemy (a `Stunned` attribute + client stars
  would be cheap).
- Should ultimates auto-replace the basic spell at 20 if the hotbar is full?
- Mana costs assume the class's mana pool (knight max is 60 — his kit is
  priced cheap). Rebalance with real play.
- Casting ignores the equipped weapon (a mage can fireball wielding a
  pickaxe). Require a weapon type per school? (Disparo Certero probably wants
  the bow.)

### Testing tips

- Level a class instantly from the **admin dashboard** Progress editor
  (gold/level/xp/class apply live — unlocks fire immediately thanks to the
  Level-attribute listener). Set level 10/15/20 to walk the whole unlock
  ladder in minutes.
- Studio without HTTP works: spells are all Luau-side; you just get the
  temporary profile (binds/level not persisted).
