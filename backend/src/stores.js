// Store definitions (vendor trade lists), loaded from the git-tracked
// content file (content/stores.json). Prices are gold per unit; an entry
// may be buy-only (no sellPrice), sell-only (no buyPrice), or both.
// Vendor NPC placement lives Roblox-side (VendorService VENDOR_DEFS) —
// the backend owns the economy data, the game owns the world layout.
//
// Like items.js, validation fails the boot loudly on malformed content.

import fs from "node:fs";
import { ITEMS } from "./items.js";

const raw = JSON.parse(
  fs.readFileSync(new URL("../content/stores.json", import.meta.url), "utf8")
);

function fail(message) {
  throw new Error(`content/stores.json: ${message}`);
}

function validatePrice(where, value) {
  if (value !== undefined && (!Number.isInteger(value) || value < 1)) {
    fail(`${where} must be a positive integer`);
  }
}

for (const [key, store] of Object.entries(raw.stores)) {
  if (store.id !== key) fail(`store "${key}" has mismatched id "${store.id}"`);
  if (typeof store.name !== "string" || !store.name) fail(`store "${key}" needs a name`);
  if (store.buysGear !== undefined && typeof store.buysGear !== "boolean") {
    fail(`store "${key}" buysGear must be a boolean`);
  }
  if (!Array.isArray(store.trades) || store.trades.length === 0) {
    fail(`store "${key}" needs a non-empty trades list`);
  }
  const seen = new Set();
  for (const trade of store.trades) {
    const where = `store "${key}" trade "${trade.itemId}"`;
    if (!ITEMS[trade.itemId]) fail(`${where} references an unknown item`);
    if (seen.has(trade.itemId)) fail(`${where} is listed twice`);
    seen.add(trade.itemId);
    validatePrice(`${where} buyPrice`, trade.buyPrice);
    validatePrice(`${where} sellPrice`, trade.sellPrice);
    if (trade.barter !== undefined) {
      // Barter replaces the gold offer (either/or, VENDOR_UI.md §5.3).
      if (trade.buyPrice !== undefined) {
        fail(`${where} can't have both buyPrice and barter`);
      }
      if (!Array.isArray(trade.barter) || trade.barter.length === 0 || trade.barter.length > 4) {
        fail(`${where} barter must list 1-4 costs`);
      }
      for (const cost of trade.barter) {
        if (!cost || !ITEMS[cost.itemId]) fail(`${where} barter references an unknown item`);
        if (cost.itemId === trade.itemId) fail(`${where} barter can't cost the item itself`);
        if (!Number.isInteger(cost.qty) || cost.qty < 1 || cost.qty > 99) {
          fail(`${where} barter qty must be 1-99`);
        }
      }
    }
    if (trade.buyPrice === undefined && trade.sellPrice === undefined && trade.barter === undefined) {
      fail(`${where} needs a buyPrice, sellPrice, or barter`);
    }
  }
}

export const STORES = raw.stores;
