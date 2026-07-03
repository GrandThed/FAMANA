# CLAUDE.md

Guidance for Claude Code (and humans) working in this repo.

## What this is

**FAMANA** — an Imperium-AO-style **grid MMO** on Roblox, backed by an external
service on Railway. The world is split into grid cells; each cell is a separate
Roblox **Place** and players teleport across cell borders with their full state
intact.

- **Roblox client/server (Luau)** in [`roblox/`](roblox/) — authoritative for
  real-time gameplay (combat, movement, gathering).
- **Backend (Node.js + Fastify + PostgreSQL)** in [`backend/`](backend/),
  deployed to Railway — the **source of truth for persistent data** (HP,
  inventory, position, current cell). Roblox talks to it over HttpService; the
  Roblox client never talks to it directly.

Full design lives in [`SPECIFICATION.md`](SPECIFICATION.md). Build history is in
the git log; the MVP was built in 7 steps (see that file's §10).

## Architecture at a glance

```
Roblox Place (Cell A)  ─┐                        ┌─ PostgreSQL
Roblox Place (Cell B)  ─┼─ HTTPS (X-Api-Key) ─►  Fastify API  ─┤  (Railway)
   (same code, differ  ─┘   server-only            (Railway)   └─
    by game.PlaceId)
```

- **Authority split:** Roblox server owns live gameplay; the backend owns
  persistence. Inventory changes write through to the backend immediately;
  HP/position autosave every 60s and on leave/teleport.
- **Security:** every backend request carries `X-Api-Key`. Clients never call
  the backend — only Roblox servers do.

## Backend (`backend/`)

Fastify + `pg` (raw SQL, ESM). Live at
`https://famana-backend-production.up.railway.app`.

- Entry: [`src/server.js`](backend/src/server.js). Auth hook in `src/auth.js`.
- Persistence: `src/playerService.js`, `src/inventory.js` (transactional
  add/remove with stack-filling). Schema in `src/schema.sql`; item defs in
  `src/items.js` (mirrored in Luau — keep in sync). `loadPlayer` reconciles the
  starter kit (tools/weapons) on every load, so existing players pick up
  newly-added starter gear.
- **Admin dashboard** (`/admin`): `src/adminService.js` (reads + audited
  mutations), `src/adminAuth.js` (signed-cookie sessions via Node `crypto`,
  separate from the game's `X-Api-Key`), `src/routes/admin.js`, static SPA in
  `admin-web/`. Enabled only if `ADMIN_PASSWORD` is set. See
  [`docs/ADMIN_DASHBOARD.md`](docs/ADMIN_DASHBOARD.md).
- **Live admin→game push** (polling): `src/events.js` — admin item mutations
  enqueue a `player_events` row (same transaction); the game drains them via
  `POST /player/events`. See the Roblox `AdminSyncService` below.
- Tables auto-migrate on Railway deploy via `preDeployCommand: npm run migrate`
  (see `railway.json`). Railway env vars: `DATABASE_URL` (reference to the
  Postgres plugin) + `API_KEY`; optional `ADMIN_PASSWORD` / `ADMIN_SESSION_SECRET`.

Local dev: `cd backend && npm install && npm run dev` (needs `DATABASE_URL` +
`API_KEY`; see `.env.example`).

Routes: `GET /health` (public); admin under `/admin` (own session auth);
everything else requires `X-Api-Key`: `GET /player/:id`, `POST /player`,
`POST /player/:id/save`, `GET|POST /player/:id/inventory[...]`,
`POST /player/events` (drain queued events for online players).

## Roblox (`roblox/`) — Rojo + Rokit

Synced into Studio with **Rojo 7.7.0** (pinned in `rokit.toml`). Structure maps
`src/shared` → `ReplicatedStorage.Shared`, `src/server` → `ServerScriptService`,
`src/client` → `StarterPlayerScripts` (see `default.project.json`).

Run: `cd roblox && rojo serve`, connect via the Rojo Studio plugin.

**Server services** (`src/server/`, started by `init.server.lua`):
`WorldService` (per-cell theming) · `PlayerService` (load/save/cache +
`onInventoryChanged` hook + `refreshInventory`) · `HealthService` (HP restore,
regen, respawn) · `ManaService` (live, non-persisted mana in `Mana`/`MaxMana`
Player attributes; steady regen; `trySpend` gates staff casts) ·
`ToolService` (equippable Tools + `registerActivated` hook) ·
`GatheringService` (data-driven resource nodes: trees→wood, rocks→stone) ·
`EnemyService` (data-driven enemies: slimes, goblins + `onKilled` hook) ·
`DropService` (loot tables → ground drops) · `BorderService` (grid teleport
handoff) · `AdminSyncService` (polls `/player/events` every 4s → refreshes
inventory + fires `Notify` for live admin edits).

**Client** (`src/client/`): `HudUI` (Diablo-style health + mana orbs and a
hotbar of item sockets, bottom of screen), `InventoryUI` (toggle button + `B`
key), `BorderFadeUI`, `NotificationUI` (toasts from the `Notify` remote),
`ShiftLockController` (cursor lock + character faces camera; frees cursor when
inventory open), `TargetingController` (RMB focuses by equipped tool within
reach — sword→enemies, axe→trees, pickaxe→rocks), `ClientState` (shared
`aiming` / `inventoryOpen` flags).

**Shared** (`src/shared/`): `Config` (HP/mana/inventory constants +
`defaultReach` fallback + `hotbarSize`) · `Items` (mirror of backend defs; each
equippable carries its own `reach` stat; the staff carries a `manaCost`) ·
`Remotes`
(RemoteEvent/Function factory) · `GridConfig` (cells keyed by PlaceId, neighbors,
border geometry, per-cell themes).

### Conventions
- Systems decouple via hooks, not cross-requires:
  `ToolService.registerActivated(itemType, fn)`, `EnemyService.onKilled(fn)`,
  `PlayerService.onInventoryChanged(fn)`.
- Content is **data-driven**: add a resource node via a `NODE_DEFS` entry (+
  builder) in `GatheringService`; add an enemy via an `ENEMY_DEFS` entry in
  `EnemyService`; add an item to `items.js` **and** `Items.lua`.
- New gameplay that grants items must go through `PlayerService.addItem/
  removeItem` so it persists and the UI/tools stay in sync.
- Tool/weapon reach is a per-item `reach` stat on the def; server combat/gather
  and client focus all read that single value (`Config.defaultReach` is only a
  fallback). Ranged weapons (`weaponType = "ranged"`) require a focused target.
- Item ids/defs must match between `backend/src/items.js` and
  `roblox/src/shared/Items.lua`.

## Critical gotchas

- **`Secret.lua` is gitignored.** `roblox/src/server/Secret.lua` returns the
  backend `API_KEY`. It's required for backend calls but never committed. A
  fresh clone must recreate it.
- **Enable HTTP in Studio** (Game Settings → Security → Allow HTTP Requests) or
  the game silently falls back to a temporary, non-persisted profile.
- **Teleport needs a published game.** `TeleportService` does nothing in Studio
  playtest — the border handoff can only be tested live. In Studio the border
  just fades out and back in (fail-safe). See
  [`docs/BORDER_TESTING.md`](docs/BORDER_TESTING.md).
- **PlaceIds** for the two cells live in `GridConfig.cells`; both places must be
  published with the same, filled-in config.
- **World state is in-memory per server** (trees/enemies reset on restart, not
  shared across the grid). Persisting it is deliberately post-MVP.

## Git / workflow

- Default branch `main`, remote `github.com/GrandThed/FAMANA-backend`.
- Commit at logical checkpoints; end commit messages with the Co-Authored-By
  trailer.
- Don't commit secrets (`.env`, `Secret.lua`) — both are gitignored.
