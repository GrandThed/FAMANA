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
  `src/items.js` (mirrored in Luau — keep in sync).
- Tables auto-migrate on Railway deploy via `preDeployCommand: npm run migrate`
  (see `railway.json`). Railway env vars: `DATABASE_URL` (reference to the
  Postgres plugin) + `API_KEY`.

Local dev: `cd backend && npm install && npm run dev` (needs `DATABASE_URL` +
`API_KEY`; see `.env.example`).

Routes (all but `/health` require `X-Api-Key`): `GET /health`, `GET /player/:id`,
`POST /player`, `POST /player/:id/save`, `GET|POST /player/:id/inventory[...]`.

## Roblox (`roblox/`) — Rojo + Rokit

Synced into Studio with **Rojo 7.7.0** (pinned in `rokit.toml`). Structure maps
`src/shared` → `ReplicatedStorage.Shared`, `src/server` → `ServerScriptService`,
`src/client` → `StarterPlayerScripts` (see `default.project.json`).

Run: `cd roblox && rojo serve`, connect via the Rojo Studio plugin.

**Server services** (`src/server/`, started by `init.server.lua`):
`WorldService` (per-cell theming) · `PlayerService` (load/save/cache +
`onInventoryChanged` hook) · `HealthService` (HP restore, regen, respawn) ·
`ToolService` (equippable Tools + `registerActivated` hook) · `GatheringService`
(trees → wood) · `EnemyService` (slimes + `onKilled` hook) · `DropService`
(ground loot) · `BorderService` (grid teleport handoff).

**Client** (`src/client/`): `HealthUI`, `InventoryUI` (toggle button + `I` key),
`BorderFadeUI`.

**Shared** (`src/shared/`): `Config` (HP/inventory constants), `Items` (mirror
of backend defs), `Remotes` (RemoteEvent/Function factory), `GridConfig` (cells
keyed by PlaceId, neighbors, border geometry, per-cell themes).

### Conventions
- Systems decouple via hooks, not cross-requires:
  `ToolService.registerActivated(itemType, fn)`, `EnemyService.onKilled(fn)`,
  `PlayerService.onInventoryChanged(fn)`.
- New gameplay that grants items must go through `PlayerService.addItem/
  removeItem` so it persists and the UI/tools stay in sync.
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
