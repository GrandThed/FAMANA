# FAMANA — Roblox client/server

Luau game code, synced into Roblox Studio with [Rojo](https://rojo.space)
(version pinned in [`rokit.toml`](rokit.toml)). Talks to the live backend
(`../backend`) over HttpService.

> Full environment setup (Rokit, the Rojo Studio plugin, VSCode, the daily
> dev loop) lives in [`docs/GETTING_STARTED.md`](../docs/GETTING_STARTED.md).
> This file is a map of the code plus the publishing steps.

## Structure

[`default.project.json`](default.project.json) maps the three source folders
into the game tree:

```
src/
├── shared/   -> ReplicatedStorage.Shared    (visible to client + server)
│   ├── Config.lua       # HP/mana constants, defaultReach, inventory grid dims
│   ├── Items.lua        # item defs — mirror of backend/src/items.js (keep in sync)
│   ├── Effects.lua      # buff/debuff defs + Effect_<id> attribute scheme
│   ├── Remotes.lua      # RemoteEvent/Function factory (works both sides)
│   ├── GridConfig.lua   # grid cells keyed by PlaceId, neighbors, themes
│   ├── ArtKit.lua       # low-poly design frame: palette + build/weld helpers
│   └── ItemModels.lua   # per-item model specs → Tools, thumbnails, ground drops
├── server/   -> ServerScriptService.Server  (server only — trusted)
│   ├── init.server.lua      # entry point, starts the services
│   ├── Secret.lua           # YOUR API KEY (gitignored — see below)
│   ├── BackendConfig.lua    # backend base URL
│   ├── BackendService.lua   # HttpService wrapper (auth, JSON, errors)
│   ├── PlayerService.lua    # load/save/cache, inventory writes, gold
│   ├── HealthService.lua    # HP restore, regen, death respawn
│   ├── ManaService.lua      # live (non-persisted) mana + regen
│   ├── EffectService.lua    # live buffs/debuffs (e.g. slime slow)
│   ├── ToolService.lua      # equippable Tools + activation hooks
│   ├── TargetService.lua    # server-validated focus target per player
│   ├── GatheringService.lua # resource nodes (trees → wood, rocks → stone)
│   ├── EnemyService.lua     # data-driven enemies (slimes, goblins)
│   ├── DropService.lua      # loot → magnetic ground drops + throw-out remote
│   ├── ItemStandService.lua # pedestals showing a spinning takeable item
│   ├── WorldService.lua     # per-cell world theming
│   ├── BorderService.lua    # grid border walls + teleport handoff
│   └── AdminSyncService.lua # polls backend events → live admin edits in-game
└── client/   -> StarterPlayer.StarterPlayerScripts.Client
    ├── init.client.lua        # entry point
    ├── HudUI.lua              # health/mana orbs + 10-slot hotbar (1/2 weapons, 3–0 binds)
    ├── InventoryUI.lua        # grid inventory screen (toggle with B)
    ├── HotbarBinds.lua        # session-only quick-bind registry
    ├── NotificationUI.lua     # toasts from the Notify remote
    ├── BorderFadeUI.lua       # fade to black on cell teleport
    ├── ShiftLockController.lua# cursor lock; frees cursor when inventory open
    ├── TargetingController.lua# RMB focus by equipped tool (sword/axe/pickaxe)
    ├── ChatConfig.lua         # docks the chat window bottom-left
    └── ClientState.lua        # shared aiming / inventoryOpen flags
```

## One-time setup

1. **Install the toolchain + Studio plugin** — see
   [`docs/GETTING_STARTED.md`](../docs/GETTING_STARTED.md) §3 (Rokit installs
   the pinned Rojo; `rojo plugin install` adds the Studio plugin).
2. **The API key** — create `src/server/Secret.lua` returning your backend
   `API_KEY` (this file is gitignored so the secret never gets committed):
   ```lua
   return "your-api-key-here"
   ```
   `BackendService` reads it and sends it as the `X-Api-Key` header. It lives
   in `ServerScriptService`, so it is **never** replicated to clients.
3. **Enable HTTP** in Studio: Home → Game Settings → Security →
   **Allow HTTP Requests** = ON. Without it the game silently falls back to a
   temporary, non-persisted profile.

## Running it

```bash
cd roblox
rojo serve          # then click "Connect" in the Rojo Studio plugin
```

Press **Play** in Studio. On join, your HP, gold, and inventory load from the
backend. Press **B** for the inventory: equipment paper doll + effects on the
left, the scrollable 10×30 drag-and-drop grid on the right (R rotates while
dragging, 3–0 quick-bind hover items to the hotbar, drag an item outside the
panel to throw it on the ground). HP, cell, and position autosave every 60s
and on leave; inventory changes persist immediately.

> The backend URL is set in `src/server/BackendConfig.lua`.

## Two-cell grid (publishing required)

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

Then launch the **published** game (not Studio), walk east into the border
wall in Cell A → you teleport to Cell B, arriving at its west edge with your HP
and inventory intact. See [`docs/BORDER_TESTING.md`](../docs/BORDER_TESTING.md)
for the full test checklist.

> In Studio, the border wall still appears; touching it just fades the screen
> out and back in (teleport is a no-op locally).
