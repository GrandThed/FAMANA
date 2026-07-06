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
  balanceada? (Sentinel is already the knight's defensive one; mage has three
  offensive ones — Invoker could lean defensive/utility.)
- ¿Subclases prismáticas? (rare/special subclasses à la TFT prismatic traits?)
- **Decided:** wielding a weapon is NOT required to cast its school's spells,
  but equipment will contribute trait/school **points** (see the next
  question).

**Equipment → trait points (decided 2026-07-06)**
- Trait points come ONLY from equipment (weapons included). Each equipped
  paper-doll piece contributes its points to its trait(s); totals accumulate
  across the whole doll — Brawler 20 is meant to be assembled from several
  pieces (e.g. Lvl 5 helmet + Lvl 3 shield with Brawler = 8 points, matching
  the `docs/TRAITS.md` proposal).
- Spell schools are untouched by items: class level alone drives spell
  unlocks and school passives. Class level's only other job is gating which
  item levels actually count (below).

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

**Player-level gating (decided 2026-07-06)**
- The gate is continuous and non-destructive: an item above your ACTIVE
  class's level (e.g. after switching to a lower-level class) stays equipped
  but goes **inert** — a red square over its paper-doll slot, zero trait
  points, zero stats — and wakes back up once your level allows it again.
  Nothing is ever auto-unequipped.
- Small leftover: can you slot an over-level item in the first place?
  Recommend yes (it just starts inert), so there's exactly one rule.

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

### Phase A — SHIPPED (fixed-trait items, no backend migration)

Traits are live: hand-authored `traits` + `itemLevel` sit on item **defs**
(`backend/content/items.json` + the `Items.lua` mirror — no schema change,
identical items stay identical). The pieces:

- **`shared/Traits.lua`** — the catalog (Lynx Eye, Agile Hands, Perseverance,
  Brawler, Bastion, Evasion — board thresholds, English ids), plus
  aggregation (`totalsFor` sums equipped non-inert pieces), threshold
  resolution, the inert check, and tooltip label helpers.
- **`server/SynergyService.lua`** — recomputes totals on every inventory /
  Level / Class change, replicates them as the `TraitPoints` attribute
  (JSON), and registers stat hooks: crit (EnemyService), dodge
  (EnemyService, with a "Dodge!" popup on evaded hits), armor →
  `100/(100+armor)` damage-taken mult, swing cooldown (ToolService — the
  cooldown now also gates damage, so click spam can't beat attack speed),
  buff duration (EffectService), max HP mult + always-on %HP/s regen
  (HealthService, refreshed live on gear changes).
- **Gating** — inert rule as decided: `itemLevel` above the ACTIVE class
  level → the piece stays equipped but contributes nothing; the paper doll
  shows a red veil + "Lv N" on it, and item tooltips say "INERT until Lv N".
- **UI** — trait entries join the TFT tracker below the schools (only traits
  you have points in; lit when the first threshold is active, "8/11" counts,
  hover for the full threshold list). Item tooltips list item level + trait
  points.
- **Test gear** — six stands on a second row behind the weapon stands:

| Item (id) | Slot | Item lvl | Traits |
|---|---|---|---|
| Brawler Ring (`ring_brawler`) | ring | 2 | Brawler 2 |
| Lynx Ring (`ring_lynx`) | ring | 3 | Lynx Eye 3 |
| Bastion Helm (`helmet_bastion`) | head | 5 | Bastion 3 · Brawler 2 |
| Duelist Sword (`sword_duelist`) | weapon | 7 | Lynx Eye 4 · Agile Hands 3 |
| Colossus Chestplate (`chest_colossus`) | chest | 8 | Brawler 5 · Bastion 3 |
| Evader Boots (`boots_evader`) | feet | 9 | Evasion 5 · Brawler 4 |

Full kit totals: Brawler 13 (tier 11 ✓), Bastion 6 (tier 5 ✓), Lynx Eye 7
(tier 7 ✓), Agile Hands 3 (below 4 ✗ — shows as "3/4"), Evasion 5 (tier 5
✓). Good coverage of active tiers AND partial progress. Note the kit needs
class level 9 to fully wake up — level up via the admin panel to test the
inert rule both ways.

Still deferred: Guardián (ally shields/auras), Rodar/Dash (movement +
iframes), gathering + mana-regen traits.

**Phase B** — random roll generator + per-instance `meta JSONB` migration
(items become unique; see the TRAITS.md corrections for every path that must
become trait-aware). **Phase C** — utility/active traits (movement system) +
Guardián.

---

## Part 2 — Subclass spells (implemented)

Everything below is live in the codebase as of this pass.

### The spells

Everything is in **English** now (game language decision); the board's
Spanish names are kept in parentheses for mapping. Unlocks follow the board:
base at class level 1, second active at 10, ultimate at 20. Passives (the
board's +X% lines) apply automatically at 1/5/10/15/20 and boost **both
spells and weapon swings**. All numbers are first-pass and live in
[`roblox/src/shared/Spells.lua`](../roblox/src/shared/Spells.lua).

| School (class) | Lvl 1 | Lvl 10 | Lvl 20 | Passive |
|---|---|---|---|---|
| Pyromancer / Piromante (mage) | Fireball — projectile + splash | Flame Wall — burning wall zone | SuperNova — huge self AoE | +10…55% magic dmg |
| Arcanist / Arcano (mage) | Arcane Missile — fast/cheap bolt | Arcane Rain — zone on target | Arcane Storm — big zone | +10…50% magic dmg |
| Invoker / Invocador (mage/summoner) | Summon Familiar — pet that orbits + shoots | 2nd familiar (passive) · Arcane Rain at 15 | Grand Familiar — big angry pet | +6…35% magic dmg |
| Berserker (knight) | Battle Cry — +physical dmg buff | Savage Strike — heavy strike | Frenzy — big damage + speed buff | +10…50% physical dmg |
| Sentinel / Centinela (knight) | Provoke — taunt + guard buff | Steel Loyalty — armor buff (allies too) | Bulwark — 50% damage taken, allies too | +8…42 armor |
| Justicar / Justiciero (knight) | Stunning Strike — strike + stun | Judgment — AoE + mini-stun | Verdict — huge strike + long stun | +10…35% physical dmg |
| Sniper / Francotirador (ranger) | Deadeye Shot — precision shot (needs focus) | — | — | — |
| Trapper / Trampero (ranger) | Snare Trap — slow zone in front of you | — | — | — |
| Scout / Explorador (ranger) | Sprint — speed buff | — | — | — |

The three ranger spells are **proposals** (the board only says
burst/CC/movement) — rename/redesign freely. Ultimates without board names
got working titles: Arcane Storm, Grand Familiar, Bulwark, Verdict.
**Decided:** ultimates are separate spells, they never replace the basic one.

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
  box/disc with damage and/or slow ticks, `strike` + stun, `aoe`, `buff` +
  ally radius, `taunt`, `summon` familiars that orbit and auto-attack),
  cooldowns mirrored as `SpellCd_<id>` attributes, unlock pushes on the
  Level/Class attributes (so admin-panel level edits unlock spells live too).
- **`EnemyService`** grew a public combat API: `computePlayerDamage` (class ×
  effects × passives × crit), `enemiesNear` / `focusedTarget` /
  `nearestTarget`, `dealSpellDamage`, `stun`, `slow` (strongest mult wins,
  refreshes duration), `taunt`, plus `registerDamageMult` /
  `registerDamageTakenMult` hooks — the same hooks the trait system should
  use for Ojo de Lince/Bastión (see Phase A). Stunned enemies show spinning
  💫 stars, slowed ones a 🐌 (server-side billboards, like their name tags);
  slow scales walk speed and stretches the pause between slime hops.
- **`EffectService`/`Effects.lua`** — effects can now carry `damageMults` and
  `damageTakenMult` (Battle Cry, Frenzy, On Guard, Steel Loyalty, Bulwark,
  Sprint), and effect walkspeed finally respects the class's own walkspeed.
- **Hotbar (`HudUI` + `HotbarBinds` + `SpellsClient`)** — slots 3–0 accept
  spell binds; spell slots show the school-colored icon, a draining cooldown
  veil with seconds, and dim when mana is short. A spell your current class
  doesn't know stays bound but renders **gray** (icon faded, gray stroke) —
  switch back to that class and it lights up again.
- **Three hotbar pages** — the button at the right end of the bar cycles
  pages 1→2→3 (number + dots show the active one). Only bind slots 3–0 swap;
  keys 1/2 always mirror the paper doll. The whole structure ({ active,
  pages }) persists with the profile (the backend's `hotbar_binds` JSONB
  takes the new shape as-is; old flat saves migrate to page 1 on load).
- **TFT-style subclass tracker (`SpellTrackerUI`)** — left screen edge, one
  entry per school of your class with class level vs next threshold
  ("7/10"). Hovering opens a tooltip with the full level timeline (reached
  tiers bright, future gray) and the school's spells; hover a spell row and
  press 3–0 to bind it to that key (works mid-play — the mouse is never
  locked; `ClientState.spellHover` keeps the same keypress from also
  casting). This doubles as the spellbook: descriptions per level live here.
- **Empty-slot spell picker** — clicking an empty hotbar slot pops a list of
  your known spells growing upward from that slot; clicking a row binds it
  there. Together with the tracker this covers rearranging/rebinding spells.
- **Auto-place on unlock** — a newly unlocked spell lands in the next free
  hotbar slot (page 1 first, then 2, then 3); on a fresh profile the whole
  known list is seeded in recommended order **into page 1**, right after the
  default axe (key 3) and pickaxe (key 4).
- **Recommendation system v1** — `hotbarPriority` on each def orders the
  loadout (bread-and-butter damage first, then AoE/buffs, utility, ultimates);
  the server sends the sorted list in every `SpellsChanged` push. v2 ideas:
  score by damage-per-mana and cooldown coverage, detect playstyle from the
  equipped weapon (melee vs bow vs staff), always keep 1 defensive; suggest
  replacements when something strictly better unlocks ("Upgrade found!").
- **1/2 equips from the inventory** — hovering a weapon/tool in the grid and
  pressing 1 (weapon) or 2 (offhand) equips it; the current occupant swaps
  back to the first free grid spot (blocked with a message if the grid is
  full).

### Decisions taken (2026-07-06 review)

- Game language is **English** (spell/school/effect names, toasts). Class
  names and the class picker UI are still Spanish — see open questions.
- Ultimates are **separate spells**; they never replace the basic one.
- No weapon requirement to cast. Traits come **only from equipment**
  (weapons included); class level only gates item level; over-level
  equipment goes inert with a red square (see Part 1).
- Unknown-class spell binds stay on the hotbar, **grayed**.
- **3 hotbar pages**, swapped from the right end of the bar or with **`X`**;
  **no** auto page switch on class change. Saved server-side; all defaults
  land on page 1.
- Enemy **stun and slow** are real primitives with on-enemy 💫/🐌 marks and
  a **remaining-duration bar** under each mark; the player's HUD effects
  strip rows drain a bar too. Snare Trap ships as a visible slow zone (v1 of
  the Trapper's kit).
- CC on **players** has diminishing returns: the same debuff reapplied
  within 8s lands at 100% → 50% → 25% duration (floor 25%), and a shortened
  reapply never cuts an already-running timer. Enemies have no diminishing
  returns for now.
- Mana costs stay as they are.

### Known gaps / open questions on the spell side

- Snare Trap is a **visible** slow zone; a real hidden, one-shot trigger trap
  is still future work. No knockback primitive exists for SuperNova.
- Rest of the game is still Spanish (class names Caballero/Arquero/Mago/
  Invocador, class picker, some UI). Translate everything for consistency?
- Do enemies eventually need diminishing returns too? (A stun-chain can
  perma-lock a single mob — fun vs. degenerate once bosses exist.)

### Testing tips

- Level a class instantly from the **admin dashboard** Progress editor
  (gold/level/xp/class apply live — unlocks fire immediately thanks to the
  Level-attribute listener). Set level 10/15/20 to walk the whole unlock
  ladder in minutes.
- Studio without HTTP works: spells are all Luau-side; you just get the
  temporary profile (binds/level not persisted).
