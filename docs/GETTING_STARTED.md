# Getting started — dev environment & workflow

How to go from a fresh clone to editing FAMANA code in VSCode and playtesting it
in Roblox Studio, with live syncing via Rojo.

If you just want the short version: install Rokit → `rokit install` → install
the Rojo Studio plugin → create `Secret.lua` → enable HTTP in Studio →
`rojo serve` → Connect → Play.

---

## 1. What the moving pieces are

This project is **not** edited inside Roblox Studio. All Luau source lives in
this git repo under [`roblox/src/`](../roblox/src/), and a tool called **Rojo**
streams it into Studio:

```
VSCode (edit .lua files)          Roblox Studio (playtest)
        │                                 ▲
        ▼                                 │
  roblox/src/  ──►  rojo serve  ──►  Rojo Studio plugin
                    (local server,    (connects to it and applies
                     port 34872)       the files into the game tree)
```

- **Rojo CLI** — a command-line program that watches the filesystem and serves
  the project to Studio.
- **Rojo Studio plugin** — a plugin *inside* Roblox Studio that connects to
  that server and keeps the game tree in sync.
- **Rokit** — a toolchain manager (like `nvm` for Roblox tools). It reads
  [`roblox/rokit.toml`](../roblox/rokit.toml) and installs the exact Rojo
  version this repo is pinned to (**7.7.0**), so everyone runs the same tool.
- **`default.project.json`** — tells Rojo *where* each folder goes in the game:

  | Filesystem                | In Studio                                       |
  |---------------------------|-------------------------------------------------|
  | `roblox/src/shared/`      | `ReplicatedStorage.Shared` (client + server)    |
  | `roblox/src/server/`      | `ServerScriptService.Server` (server only)      |
  | `roblox/src/client/`      | `StarterPlayer.StarterPlayerScripts.Client`     |

  File naming drives the instance type: `Foo.lua` → ModuleScript,
  `init.server.lua` → the folder becomes a Script (server entry point),
  `init.client.lua` → LocalScript (client entry point).

The **sync is one-way: filesystem → Studio.** Anything you type into a script
inside Studio gets overwritten on the next sync. Scripts are edited in VSCode,
always. (Placing non-script things in the Workspace by hand in Studio is fine —
Rojo only manages the trees listed above.)

## 2. Prerequisites

- **Roblox Studio** — install from <https://create.roblox.com> and log in.
- **VSCode** — <https://code.visualstudio.com>.
- **Git** — you presumably have it, since you cloned this.
- **Node.js 18+** — only needed if you want to run the *backend* locally
  (usually you don't; the game talks to the live Railway deployment).

## 3. One-time setup

### 3.1 Install Rokit

Rokit is a single binary. On Windows, in PowerShell:

```powershell
# Download the latest release zip for Windows from
# https://github.com/rojo-rbx/rokit/releases  (rokit-*-windows-x86_64.zip),
# unzip it, then run:
.\rokit.exe self-install
```

Then **restart your terminal** so `rokit` (and the tool shims it creates) are
on your PATH.

### 3.2 Install the pinned Rojo

```powershell
cd roblox
rokit install
```

This reads `rokit.toml` and installs Rojo 7.7.0. Verify with:

```powershell
rojo --version   # → Rojo 7.7.0
```

> Rokit installs *shims*: the `rojo` command works anywhere, but resolves to
> the version pinned by the nearest `rokit.toml` — so run rojo commands from
> inside `roblox/`.

### 3.3 Install the Rojo plugin into Roblox Studio

Easiest way — let the CLI do it:

```powershell
cd roblox
rojo plugin install
```

Alternatively, get it from the Creator Store: open Studio → Toolbox →
Creator Store → Plugins → search "Rojo" (by evaera) → install. Either way, a
**Rojo** button appears in Studio's **Plugins** tab.

### 3.4 Create `Secret.lua` (required — the game won't persist without it)

The Roblox server authenticates to the backend with an API key. The file that
holds it is **gitignored** and must be created by hand on every fresh clone:

Create `roblox/src/server/Secret.lua` containing exactly:

```lua
return "the-actual-api-key"
```

The value is the backend's `API_KEY` (it's in the Railway project's
environment variables — Railway dashboard → famana-backend → Variables).
`BackendService` sends it as the `X-Api-Key` header on every request. It lives
in `ServerScriptService`, so it never replicates to clients. **Never commit it.**

### 3.5 VSCode extensions (recommended)

The repo doesn't enforce any, but these make Luau development sane:

- **Luau Language Server** (`JohnnyMorganz.luau-lsp`) — autocomplete,
  go-to-definition, type checking for Luau. Point it at
  `roblox/default.project.json` (setting: *Luau LSP → Sourcemap: Rojo Project
  File*) so it understands `game.ReplicatedStorage.Shared` style requires.
- **Rojo — Roblox Studio Sync** (`evaera.vscode-rojo`) — optional; lets you
  start/stop `rojo serve` from the VSCode command palette instead of a
  terminal. Purely convenience.
- **StyLua** (`JohnnyMorganz.stylua`) — optional Luau formatter.

### 3.6 Open the place in Studio and flip two settings

The repo has no `.rbxl` file — the "place" lives on Roblox. Open Studio and
either open the published FAMANA place (File → Open from Roblox), or for a
scratch environment create a new **Baseplate**. Then:

1. **Enable HTTP:** Home → Game Settings → Security → **Allow HTTP Requests**
   = ON. Without this the game *silently* falls back to a temporary in-memory
   profile — everything appears to work, but nothing saves. If you see
   `[BackendService]` warnings in the Output window about HTTP being disabled,
   this is why.
2. (New place only) File → **Publish to Roblox** once, so Game Settings are
   editable and the place has a PlaceId.

## 4. The daily development loop

This is what a normal session looks like:

1. **Start the sync server** (leave it running the whole session):

   ```powershell
   cd roblox
   rojo serve
   ```

   It prints something like `Rojo server listening on port 34872`.

2. **Connect Studio:** in Studio, Plugins tab → **Rojo** button → the panel
   shows `localhost:34872` → click **Connect**. The panel turns green and the
   `Shared` / `Server` / `Client` trees appear (or update) in the Explorer.

3. **Edit in VSCode.** Every save syncs into Studio within a second or so —
   no rebuild, no reconnect. You'll see instances update live in the Explorer.

4. **Playtest:** press **Play** (F5) in Studio. On join, your character loads
   HP/inventory/position from the backend. Check the **Output** window
   (View → Output) — server prints appear there, and `[BackendService]` errors
   are your first stop when persistence misbehaves.

5. **Iterate:** Stop (Shift+F5) → edit in VSCode → the change is already
   synced → Play again. You do *not* restart `rojo serve` between playtests;
   scripts only re-execute on a fresh Play, so a Stop/Play cycle is needed for
   code changes to take effect.

6. **Commit** from the repo root as usual. Studio itself holds nothing worth
   saving except Workspace scenery — the code of record is git.

### Testing against a local backend (optional)

By default the game hits the live Railway backend
(`https://famana-backend-production.up.railway.app`, set in
[`BackendConfig.lua`](../roblox/src/server/BackendConfig.lua)). That's fine for
day-to-day work. To test backend changes end-to-end instead:

```powershell
cd backend
npm install
# create .env from .env.example (needs DATABASE_URL + API_KEY)
npm run dev
```

Then point `BackendConfig.lua` at your local URL — but note Roblox's
HttpService **cannot reach `localhost`**; you need a tunnel
(e.g. `ngrok http 3000`) and to use the tunnel URL. Remember to revert
`BackendConfig.lua` before committing, and make `Secret.lua` match your local
`API_KEY`.

## 5. Things that will bite you (gotchas)

- **Editing scripts in Studio.** They get clobbered by the next Rojo sync.
  Muscle-memory rule: code → VSCode, world/scenery → Studio.
- **HTTP off = silent no-persistence.** See §3.6. Symptom: everything plays
  fine, nothing survives a rejoin.
- **`Secret.lua` missing** on a fresh clone → every backend call 401s. See §3.4.
- **Border teleports don't work in Studio.** `TeleportService` is a no-op in
  playtest — the border fades and puts you back. Testing the cell handoff
  requires the published game; see [`BORDER_TESTING.md`](BORDER_TESTING.md).
- **Two places, one codebase.** Both grid cells must be published with
  identical code and a filled-in `GridConfig.lua` (PlaceIds). Publishing flow
  is in [`roblox/README.md`](../roblox/README.md) §"Step 7".
- **World state resets on server restart** (trees, enemies, ground drops).
  That's by design for the MVP — only the backend data (HP, gold, inventory,
  position) persists.
- **Keep item defs in sync.** Any item change touches both
  `backend/src/items.js` *and* `roblox/src/shared/Items.lua`.

## 6. Quick reference

| I want to…                    | Do this                                            |
|-------------------------------|----------------------------------------------------|
| Start syncing                 | `cd roblox && rojo serve`, then Connect in Studio  |
| Update tools after a pull     | `cd roblox && rokit install`                       |
| Reinstall the Studio plugin   | `cd roblox && rojo plugin install`                 |
| Run the backend locally       | `cd backend && npm run dev` (needs `.env`)         |
| See server logs while playing | Studio → View → Output                             |
| Toggle the inventory in-game  | **B** (hotbar: 1/2 weapons, 3–0 quick binds)       |
