# FAMANA — Roblox client/server

Luau game code, synced into Roblox Studio with [Rojo](https://rojo.space).
Talks to the live backend (`../backend`) over HttpService.

## Structure

```
src/
├── shared/   -> ReplicatedStorage.Shared   (visible to client + server)
│   ├── Config.lua      # HP/inventory/cell constants (NOT secret)
│   ├── Items.lua       # item defs, mirrored from backend/src/items.js
│   └── Remotes.lua     # RemoteEvent/Function factory (works both sides)
├── server/   -> ServerScriptService.Server (server only — trusted)
│   ├── init.server.lua     # entry point, starts the services
│   ├── BackendConfig.lua    # backend base URL
│   ├── BackendService.lua   # HttpService wrapper (auth, JSON, errors)
│   ├── PlayerService.lua     # load on join / save on leave / autosave
│   ├── HealthService.lua     # HP restore, regen, death respawn
│   └── Secret.lua            # YOUR API KEY (gitignored — see below)
└── client/   -> StarterPlayer.StarterPlayerScripts.Client
    ├── init.client.lua  # entry point
    ├── HudUI.lua        # health + mana orbs and hotbar
    └── InventoryUI.lua  # 20-slot inventory panel (toggle with B)
```

## One-time setup

1. **Install Rojo** (CLI + the Studio plugin): https://rojo.space/docs/v7/getting-started/installation/
2. **The API key** — create `src/server/Secret.lua` returning your backend
   `API_KEY` (this file is gitignored so the secret never gets committed):
   ```lua
   return "your-api-key-here"
   ```
   `BackendService` reads it and sends it as the `X-Api-Key` header. It lives in
   `ServerScriptService`, so it is **never** replicated to clients.
3. **Enable HTTP** in Studio: Home → Game Settings → Security →
   **Allow HTTP Requests** = ON. (Required for the game to reach the backend.)

## Running it

```bash
cd roblox
rojo serve          # then click "Connect" in the Rojo Studio plugin
```

Press **Play** in Studio. On join, your character's HP + inventory load from the
backend; the sword + axe show up in the inventory panel (press **I**). HP, cell,
and position autosave every 60s and on leave.

> The backend URL is set in `src/server/BackendConfig.lua`.

## Step 7: two-cell grid (publishing required)

`TeleportService` only works in a **published** game, not Studio playtest. Both
cells run this same code and self-identify by their **PlaceId**.

1. **Publish Cell A** (the start place): Studio → File → Publish to Roblox.
   Create a new Experience if you don't have one.
2. **Create Cell B** in the *same* Experience: Creator Dashboard → your
   Experience → Places → Create Place. (Or Studio: File → Publish to Roblox As →
   Create new Place under the same Experience.)
3. Get both **Place IDs** (Creator Dashboard → each Place → Copy ID, or
   `print(game.PlaceId)` in Studio while that place is open).
4. Put them in [`src/shared/GridConfig.lua`](src/shared/GridConfig.lua):
   ```lua
   A = { placeId = <cell A id>, neighbors = { east = "B" } },
   B = { placeId = <cell B id>, neighbors = { west = "A" } },
   ```
5. **Publish the identical content to BOTH places** (with GridConfig filled in):
   Sync via Rojo, then File → Publish to Roblox As → Cell A, and again → Cell B.
   The code behaves per-cell automatically via PlaceId.
6. **Enable teleports between them:** Creator Dashboard → Experience → each
   Place must belong to the same Experience (they do if created as above).

Then launch the **published** game (not Studio), walk east into the blue border
wall in Cell A → you teleport to Cell B, arriving at its west edge with your HP
and inventory intact.

> In Studio, the border wall still appears; touching it just logs a warning
> (teleport is a no-op locally).
