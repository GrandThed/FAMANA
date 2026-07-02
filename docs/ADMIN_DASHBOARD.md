# Admin Dashboard — Design & Build Spec

A web panel to administer the game from the backend: list players, view a
dashboard, inspect a player's inventory, and add/remove items or edit stats.
This is a **spec to build against** — not yet implemented.

## Goals

- See **all players** and search/sort them.
- A **dashboard** with at-a-glance stats (player count, per-cell distribution,
  recently active, item totals).
- Open a **player detail** view: HP, cell, position, full inventory.
- **Mutate** player data safely: add/remove items, set HP, move to a cell,
  (optionally) reset or delete a player.
- Everything audited and access-controlled — this is powerful tooling.

## Where it lives

Add to the existing `backend/` service so it shares the DB and item defs:

```
backend/
├── src/
│   ├── routes/
│   │   ├── admin.js        # NEW: admin API (see endpoints below)
│   │   └── ...
│   ├── adminAuth.js        # NEW: session/login guard for the panel
│   └── ...
└── admin-web/              # NEW: the dashboard front-end (static SPA)
    └── ...
```

Two viable front-end approaches:
1. **Server-rendered (simplest):** Fastify + a template engine
   (`@fastify/view` + EJS/Handlebars) + `@fastify/static`. No build step, ships
   with the API. Good for an internal tool.
2. **SPA (nicer UX):** a small React/Vue app built to static files, served by
   `@fastify/static`, talking to the admin JSON API. More setup, better tables.

**Recommendation:** start with approach 1 (server-rendered) for speed; graduate
to a SPA if the tooling grows.

## Authentication (do this first — it's the whole risk)

The admin panel must **not** use the game's `X-Api-Key` (that's shared with
Roblox servers). Separate auth:

- A dedicated `ADMIN_PASSWORD` (or a small `admin_users` table with hashed
  passwords via `bcrypt`) set as a Railway variable.
- Login issues a signed session cookie (`@fastify/secure-session` or
  `@fastify/jwt`). All `/admin/*` routes require a valid session.
- Enforce **HTTPS only** (Railway provides it), `httpOnly` + `sameSite` cookies.
- Rate-limit the login route (`@fastify/rate-limit`).
- Optional: IP allowlist for `/admin/*`.

> Never expose player-mutation endpoints without auth. Treat this like a bank
> admin — least privilege, audit everything.

## API endpoints (new, all under `/admin`, session-guarded)

| Method | Route | Purpose |
|---|---|---|
| POST | `/admin/login` | Exchange password → session cookie |
| POST | `/admin/logout` | Clear session |
| GET | `/admin/stats` | Dashboard aggregates (see below) |
| GET | `/admin/players?query=&cell=&limit=&offset=&sort=` | Paginated player list |
| GET | `/admin/players/:id` | Full player + inventory |
| PATCH | `/admin/players/:id` | Update `health`, `maxHealth`, `cell`, `position` |
| POST | `/admin/players/:id/items` | Add item `{ itemId, quantity }` |
| DELETE | `/admin/players/:id/items` | Remove item `{ itemId, quantity }` |
| DELETE | `/admin/players/:id` | Delete a player (guarded, confirm) |
| GET | `/admin/items` | Item catalog (from `items.js`) for pickers |

Reuse the existing transactional `inventory.js` `addItem`/`removeItem` so admin
edits obey the same stacking/room rules as gameplay.

### `/admin/stats` shape (example)

```json
{
  "players": { "total": 128, "byCell": { "A": 74, "B": 54 } },
  "activity": { "activeLast24h": 41, "newLast7d": 19 },
  "items": { "wood": 5120, "slime_goo": 880 }
}
```

Backed by SQL aggregates, e.g.:

```sql
-- players per cell
SELECT cell, COUNT(*) FROM players GROUP BY cell;
-- total quantity per item
SELECT item_id, SUM(quantity) FROM inventory_items GROUP BY item_id;
-- recently active
SELECT COUNT(*) FROM players WHERE updated_at > now() - interval '24 hours';
```

Add an index on `players.updated_at` if activity queries get heavy.

## Pages / UX

1. **Login** — password field → session.
2. **Dashboard** (`/admin`) — stat cards (total players, per-cell split, active
   24h, item totals) + a small "recent players" table.
3. **Players** (`/admin/players`) — searchable, sortable, paginated table
   (id, username, cell, HP, updated_at). Row → detail.
4. **Player detail** (`/admin/players/:id`):
   - Header: username, id, cell, HP (editable), position.
   - Inventory grid: each slot shows item + qty, with **−/＋** controls and an
     "add item" picker (dropdown of `/admin/items` + quantity).
   - Danger zone: reset HP, move cell, delete player (with confirm modal).

## Live effect on players who are online

The DB is the source of truth, but a **currently-connected** Roblox server holds
an in-memory cache of that player's profile — so an admin edit won't show in-game
until they rejoin/reload. Options (increasing effort):

1. **MVP:** edits apply on the player's next load (rejoin / cell change). Note
   this in the UI ("applies on next login").
2. **Push:** a backend→Roblox channel via Roblox **MessagingService** or an
   Open Cloud messaging call, so live servers refresh a cached profile on edit.
   (Bigger; revisit when needed.)

## Safety & auditing

- Wrap every mutation in a DB transaction (already the pattern in `inventory.js`).
- Add an `admin_audit` table: `{ id, actor, action, target_player, detail jsonb,
  created_at }` — log every add/remove/edit/delete.
- Confirm destructive actions (delete/reset) with a modal + typed confirmation.
- Validate `itemId` against the catalog; reject unknown items and non-positive
  quantities (the existing `inventory.js` already does this).

## Build order (suggested)

1. Admin auth (login/session, `ADMIN_PASSWORD`, guard middleware).
2. Read-only endpoints: `/admin/players`, `/admin/players/:id`, `/admin/stats`.
3. Server-rendered pages for dashboard + list + detail (read-only).
4. Mutations: item add/remove, HP/cell edit (+ audit log).
5. Danger zone (delete/reset) with confirmation.
6. (Later) live push to online players via MessagingService.

## Related

- Reuses `backend/src/inventory.js`, `backend/src/items.js`,
  `backend/src/db.js`, `backend/src/schema.sql`.
- Keep item ids consistent with `roblox/src/shared/Items.lua`.
