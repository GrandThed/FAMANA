// Checks every uploaded Style A asset's state (exists? moderation?) via
// Open Cloud. Usage: node scripts/check_assets.mjs
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const manifest = JSON.parse(readFileSync(join(ROOT, 'roblox', 'src', 'assets', 'StyleA', 'roblox_asset_ids.json'), 'utf8'));
const key = readFileSync(join(ROOT, '.env'), 'utf8').match(/^ROBLOX_API_KEY=(.+)$/m)?.[1]?.trim();

const states = {};
const problems = [];
for (const [name, id] of Object.entries(manifest)) {
  const res = await fetch(`https://apis.roblox.com/assets/v1/assets/${id}`, { headers: { 'x-api-key': key } });
  if (!res.ok) {
    problems.push(`${name} (${id}): HTTP ${res.status}`);
    continue;
  }
  const body = await res.json();
  const state = body.moderationResult?.moderationState || 'Unknown';
  states[state] = (states[state] || 0) + 1;
  if (state !== 'Approved') problems.push(`${name} (${id}): ${state}`);
}
console.log(`checked ${Object.keys(manifest).length} assets:`, JSON.stringify(states));
if (problems.length) console.log('attention:\n' + problems.join('\n'));
else console.log('all approved.');
