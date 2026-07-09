# Deployment pipeline

How code and maps reach every published place, automatically. Map *authoring*
(Studio workflow, markers, exporting) is [`MAP_AUTHORING.md`](MAP_AUTHORING.md);
this doc is the pipeline that ships it.

## Principles

1. **The pipeline is the only writer to live places.** Studio is for
   authoring; publishes happen from the repo. A Studio publish to a live
   place is drift — the pipeline detects and warns about it (see §Ledger).
2. **Git is the source of truth.** A published build is always reproducible
   from a commit: the deploy script refuses dirty trees (`--force` to
   override, drafts only warn), and every build is stamped.
3. **Every deploy is recorded.** `BuildInfo.lua` inside the place says which
   commit it runs; the backend ledger says which version every place got,
   when, from which commit.
4. **Places update; servers migrate separately.** Publishing never kicks
   players — live servers keep the old version until they empty. Migration
   (`restartServers`) is an explicit action.

## The normal flow

```
commit (code and/or exported maps) → push to main
  → GitHub Actions (.github/workflows/deploy-places.yml)
      1. rebuild Secret.lua from the FAMANA_API_KEY repo secret
      2. stamp src/shared/BuildInfo.lua with commit + timestamp
      3. rojo build each place in roblox/places.json → publish via Open Cloud
      4. record each publish in the backend ledger (POST /deploys)
      5. warn on version drift (place changed outside the pipeline)
```

Path-filtered: only pushes touching `roblox/**` (or the script/workflow)
deploy. Backend-only pushes deploy only Railway, as before. One deploy runs
at a time (concurrency group).

**Migrating live servers:** run the workflow manually (Actions → Deploy
places → Run workflow) with `restart: true`, or locally
`node scripts/deploy-places.mjs --restart`. Restart only touches servers on
outdated versions (same as the dashboard's "Restart servers for updates");
players get Roblox's reconnect flow and their state is already saved
(60s autosave + save-on-leave).

**Local runs** still work and take the same guards:

| Command | Effect |
| --- | --- |
| `node scripts/deploy-places.mjs` | build + publish all places |
| `… cellB` | only named place(s) |
| `… --draft` | upload as Saved — test in Studio without going live |
| `… --restart` | after a 100%-successful publish, migrate live servers |
| `… --force` | deploy a dirty tree (breaks reproducibility — avoid) |

Keys for local runs live in the repo-root `.env` (gitignored):
`ROBLOX_API_KEY=<open cloud key>`. The backend ledger key is read from
`Secret.lua` automatically.

## CI setup (already done, for reference)

- Repo secrets `ROBLOX_API_KEY` + `FAMANA_API_KEY`
  (Settings → Secrets and variables → Actions).
- The Open Cloud key needs: **universe-places → Write** (publishing),
  **universe → Write** (restarts), and its IP allowlist set to `0.0.0.0/0`
  (GitHub runners have changing IPs).

## The ledger

Backend tables (`backend/src/schema.sql`): `places` — the registry, upserted
from `roblox/places.json` on every deploy, so **every place the pipeline
touches is tracked automatically**; `deploys` — append-only history
(version, type, commit, time). Endpoints behind `X-Api-Key`: `POST /deploys`,
`GET /deploys/latest?placeId=`, `GET /places` (registry + latest deploy —
the future dashboard's Places source).

**Drift check:** Roblox increments a place's version on every save/publish.
If a publish comes back more than +1 above the last *recorded* version,
something else wrote to the place since the pipeline last did — almost
always a Studio session. The deploy proceeds (repo wins by design) but warns
loudly, because unexported Studio map work was just overwritten. Ledger
outages never block a deploy; you just lose the check for that run.

## Rollback

`git revert` the bad commit and push — CI redeploys the previous code AND
maps, because both live in the repo. (Roblox's per-place version history on
the Creator Dashboard remains the emergency hatch, but reverting five places
by hand is the last resort, not the plan.)

## Adding a new place

1. Studio → File → Publish to Roblox → into the FAMANA experience → new place.
2. Register the PlaceId: `GridConfig.cells` (grid cell) or `GridConfig.places`
   (instance place, with a `role`).
3. Copy `roblox/cellA.project.json` → `<name>.project.json`, point its Map
   mount at `maps/<name>.rbxm`.
4. Add it to `roblox/places.json`.
5. Commit + push — CI deploys it, and the ledger starts tracking it.

## When something fails

- **Partial deploy** (some places FAILED): fixed versions stay live nowhere —
  the failed places just keep their previous version. Re-run the workflow
  (or `node scripts/deploy-places.mjs <failed places>`). `--restart` refuses
  to run after partial deploys, so versions never migrate half-updated.
- **409 Server is busy** after retries: the place is open in Studio — close
  it and re-run.
- **Drift warning**: check whether map work happened in Studio since the
  last deploy; if yes, re-author/export it (the overwritten version is in
  the place's version history on the Creator Dashboard).
