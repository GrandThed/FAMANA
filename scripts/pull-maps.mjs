// Pulls each live place's authored Map folder down into roblox/maps/<name>/
// so Studio stays the source of truth for maps while git stays the source of
// truth for code. deploy-places.mjs calls pullMap() before every build; this
// file is also runnable standalone to refresh maps without deploying:
//
//   node scripts/pull-maps.mjs           # pull every place in places.json
//   node scripts/pull-maps.mjs cellA     # only the named place(s)
//
// How a pull works:
//   1. Download the live place file via the Open Cloud Asset Delivery API
//      (the ROBLOX_API_KEY needs the Asset Delivery permission).
//   2. `rojo syncback` extracts Workspace.Map into roblox/maps/<name>/ — a
//      directory of one .rbxm per top-level child of the Map folder. The
//      per-place project mounts that directory back as Workspace.Map, so the
//      next build reproduces the live map exactly.
//
// A live place WITHOUT a Map folder clears roblox/maps/<name>/ (the game then
// runs on the def-`spots` fallback, same as today). Maps are gitignored —
// they're pulled artifacts, not sources. Rollback for maps = the place's
// version history on the Creator Dashboard.
//
// Rojo constraint worth knowing (enforced with a clear error): the DIRECT
// children of the Map folder must have unique names. Group map content into
// a few uniquely-named Models ("World", "Markers", …) — duplicates INSIDE
// them are fine. See docs/MAP_AUTHORING.md.

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ROBLOX_DIR = path.join(ROOT, "roblox");
const BUILD_DIR = path.join(ROBLOX_DIR, "build");
const MAPS_DIR = path.join(ROBLOX_DIR, "maps");

// Downloads the current live place file. Returns the path to it.
async function downloadPlace(name, placeId, apiKey) {
  const meta = await fetch(`https://apis.roblox.com/asset-delivery-api/v1/assetId/${placeId}`, {
    headers: { "x-api-key": apiKey },
  });
  if (meta.status === 401 || meta.status === 403) {
    throw new Error(
      `HTTP ${meta.status} downloading the place — the API key is missing the Asset Delivery permission.\n` +
        "    Creator Dashboard → Open Cloud → API Keys → your key → Access Permissions →\n" +
        "    add the 'Asset Delivery' API system (Read) and save. The key value doesn't change."
    );
  }
  if (!meta.ok) {
    throw new Error(`asset-delivery HTTP ${meta.status}: ${await meta.text()}`);
  }
  const body = await meta.json();
  if (body.IsCopyrightProtected) {
    throw new Error("place is copyright-protected — cannot download");
  }
  if (!body.location) {
    throw new Error(`asset-delivery returned no download location: ${JSON.stringify(body)}`);
  }
  const file = await fetch(body.location);
  if (!file.ok) {
    throw new Error(`place download HTTP ${file.status}`);
  }
  fs.mkdirSync(BUILD_DIR, { recursive: true });
  const out = path.join(BUILD_DIR, `${name}.live.rbxl`);
  fs.writeFileSync(out, Buffer.from(await file.arrayBuffer()));
  return out;
}

// Extracts Workspace.Map from `placeFile` into roblox/maps/<name>/ via rojo
// syncback. Returns "pulled" or "no-map" (live place carries no Map folder —
// the maps dir is removed so builds fall back to def spots). Throws on
// anything else.
function extractMap(name, placeFile) {
  const mapDir = path.join(MAPS_DIR, name);
  // Start from a clean slate so the result mirrors the live Map exactly —
  // stale files from a previous pull must not resurrect deleted map content.
  fs.rmSync(mapDir, { recursive: true, force: true });
  fs.mkdirSync(mapDir, { recursive: true });

  const project = path.join(BUILD_DIR, `${name}.pull.project.json`);
  fs.writeFileSync(
    project,
    JSON.stringify({
      name: `pull-${name}`,
      tree: {
        $className: "DataModel",
        Workspace: { Map: { $path: `../maps/${name}` } },
      },
    })
  );

  const result = spawnSync(
    "rojo",
    ["syncback", project, "--input", placeFile, "--non-interactive"],
    { cwd: ROBLOX_DIR, encoding: "utf8" }
  );
  if (result.error && result.error.code === "ENOENT") {
    throw new Error("rojo not found on PATH — run `rokit install` in roblox/ first");
  }
  const stderr = result.stderr || "";
  if (stderr.includes("present only in a project file")) {
    // The live place has no Workspace.Map: legitimate (pre-map place, or the
    // map was deliberately deleted). No map dir -> the optional mount skips
    // Map entirely and services use their def-spots fallback.
    fs.rmSync(mapDir, { recursive: true, force: true });
    return "no-map";
  }
  if (stderr.includes("must have a unique name")) {
    throw new Error(
      "the Map folder has duplicate names among its DIRECT children — Rojo can't extract that.\n" +
        "    In Studio, group the map's contents into a few uniquely-named Models\n" +
        '    ("World", "Markers", …); duplicated names INSIDE those are fine.\n' +
        `    Rojo said: ${stderr.trim().split("\n")[0]}`
    );
  }
  if (result.status !== 0 || stderr.includes("[ERROR")) {
    throw new Error(`rojo syncback failed:\n${stderr || result.stdout}`);
  }
  return "pulled";
}

// Pull one place's map. Returns "pulled" | "no-map"; throws on failure.
// Deploys treat a throw as fatal FOR THAT PLACE: building without the live
// map would overwrite it, which is the one thing this pipeline must never do.
export async function pullMap(name, placeId, apiKey) {
  const placeFile = await downloadPlace(name, placeId, apiKey);
  return extractMap(name, placeFile);
}

// ---- standalone CLI ---------------------------------------------------------

const isMain =
  process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href;

if (isMain) {
  const envFile = path.join(ROOT, ".env");
  if (fs.existsSync(envFile)) {
    for (const line of fs.readFileSync(envFile, "utf8").split(/\r?\n/)) {
      const match = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/);
      if (match && process.env[match[1]] === undefined) {
        process.env[match[1]] = match[2].replace(/^["']|["']$/g, "");
      }
    }
  }
  const apiKey = process.env.ROBLOX_API_KEY;
  if (!apiKey) {
    console.error("Missing ROBLOX_API_KEY — set it in the repo-root .env.");
    process.exit(1);
  }
  const manifest = JSON.parse(fs.readFileSync(path.join(ROBLOX_DIR, "places.json"), "utf8"));
  const requested = process.argv.slice(2).filter((a) => !a.startsWith("--"));
  const names = requested.length > 0 ? requested : Object.keys(manifest.places);

  let failed = 0;
  for (const name of names) {
    const place = manifest.places[name];
    if (!place) {
      console.error(`Unknown place: ${name}`);
      failed += 1;
      continue;
    }
    process.stdout.write(`- ${name} (${place.placeId}): `);
    try {
      const status = await pullMap(name, place.placeId, apiKey);
      console.log(status === "pulled" ? `map pulled into roblox/maps/${name}/` : "live place has no Map folder");
    } catch (error) {
      failed += 1;
      console.log(`FAILED — ${error.message}`);
    }
  }
  if (failed > 0) process.exit(1);
}
