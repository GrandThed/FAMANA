// Static item definitions. Mirrored in the Roblox code (shared/Items.lua).
// Keep the two in sync by hand for the MVP.
//
// `size` is the grid footprint [width, height] in inventory cells.
// Armor/rings carry a `slot` matching an EQUIPMENT_SLOTS entry.

export const ITEMS = {
  sword_basic: {
    id: "sword_basic",
    name: "Basic Sword",
    type: "weapon",
    weaponType: "melee",
    stackable: false,
    maxStack: 1,
    damage: 10,
    reach: 10, // studs the swing (and its focus/targeting) can connect
    size: [1, 3],
  },
  axe_basic: {
    id: "axe_basic",
    name: "Basic Axe",
    type: "tool",
    stackable: false,
    maxStack: 1,
    toolType: "axe",
    gatherPower: 1,
    reach: 12,
    size: [2, 3],
  },
  pickaxe_basic: {
    id: "pickaxe_basic",
    name: "Basic Pickaxe",
    type: "tool",
    stackable: false,
    maxStack: 1,
    toolType: "pickaxe",
    gatherPower: 1,
    reach: 12,
    size: [2, 3],
  },
  sword_iron: {
    id: "sword_iron",
    name: "Iron Sword",
    type: "weapon",
    weaponType: "melee",
    stackable: false,
    maxStack: 1,
    damage: 20,
    reach: 10,
    size: [1, 3],
  },
  staff_basic: {
    id: "staff_basic",
    name: "Magic Staff",
    type: "weapon",
    weaponType: "ranged",
    stackable: false,
    maxStack: 1,
    damage: 15,
    reach: 60,
    manaCost: 25, // mana spent per cast; blocked when mana is too low
    size: [1, 4],
  },
  wood: {
    id: "wood",
    name: "Wood",
    type: "resource",
    stackable: true,
    maxStack: 50,
    size: [1, 1],
  },
  stone: {
    id: "stone",
    name: "Stone",
    type: "resource",
    stackable: true,
    maxStack: 50,
    size: [1, 1],
  },
  slime_goo: {
    id: "slime_goo",
    name: "Slime Goo",
    type: "resource",
    stackable: true,
    maxStack: 50,
    size: [1, 1],
  },
  goblin_ear: {
    id: "goblin_ear",
    name: "Goblin Ear",
    type: "resource",
    stackable: true,
    maxStack: 50,
    size: [1, 1],
  },

  // ---- armor (paper-doll equipment; combat stats come later) --------------
  helmet_leather: {
    id: "helmet_leather",
    name: "Leather Helmet",
    type: "armor",
    slot: "head",
    stackable: false,
    maxStack: 1,
    size: [2, 2],
  },
  chest_leather: {
    id: "chest_leather",
    name: "Leather Tunic",
    type: "armor",
    slot: "chest",
    stackable: false,
    maxStack: 1,
    size: [2, 3],
  },
  gloves_leather: {
    id: "gloves_leather",
    name: "Leather Gloves",
    type: "armor",
    slot: "hands",
    stackable: false,
    maxStack: 1,
    size: [2, 2],
  },
  legs_leather: {
    id: "legs_leather",
    name: "Leather Leggings",
    type: "armor",
    slot: "legs",
    stackable: false,
    maxStack: 1,
    size: [2, 2],
  },
  boots_leather: {
    id: "boots_leather",
    name: "Leather Boots",
    type: "armor",
    slot: "feet",
    stackable: false,
    maxStack: 1,
    size: [2, 2],
  },

  // ---- rings ---------------------------------------------------------------
  ring_vitality: {
    id: "ring_vitality",
    name: "Ring of Vitality",
    type: "ring",
    slot: "ring",
    stackable: false,
    maxStack: 1,
    size: [1, 1],
  },
  ring_focus: {
    id: "ring_focus",
    name: "Ring of Focus",
    type: "ring",
    slot: "ring",
    stackable: false,
    maxStack: 1,
    size: [1, 1],
  },
};

// Items a brand-new player starts with.
export const STARTER_ITEMS = [
  { itemId: "sword_basic", quantity: 1 },
  { itemId: "staff_basic", quantity: 1 },
  { itemId: "axe_basic", quantity: 1 },
  { itemId: "pickaxe_basic", quantity: 1 },
];

// The permanent starter kit (tools/weapons) is reconciled on every load so
// existing players pick up newly-added starter gear (e.g. the pickaxe).
export const STARTER_EQUIPPABLES = STARTER_ITEMS.filter((entry) => {
  const def = ITEMS[entry.itemId];
  return def && (def.type === "weapon" || def.type === "tool");
});

// The main inventory grid: fixed width, rows grow with backpack tiers
// later. Mirrored in Roblox shared/Config.lua.
export const GRID = { width: 10, height: 30 };

// Paper-doll equipment slots. A slot's index is its `x` in the `equipment`
// container (y = 0). Mirrored in Roblox shared/Items.lua.
export const EQUIPMENT_SLOTS = [
  "weapon",
  "offhand",
  "head",
  "chest",
  "hands",
  "legs",
  "feet",
  "back",
  "ring1",
  "ring2",
];

// Whether an item def may sit in the given equipment slot.
export function slotAccepts(slotName, def) {
  if (!def) return false;
  if (slotName === "weapon" || slotName === "offhand") {
    return def.type === "weapon" || def.type === "tool";
  }
  if (slotName === "ring1" || slotName === "ring2") return def.type === "ring";
  if (slotName === "back") return def.type === "backpack";
  return def.type === "armor" && def.slot === slotName;
}

export function getItem(itemId) {
  return ITEMS[itemId] || null;
}

export function maxStackFor(itemId) {
  const item = ITEMS[itemId];
  if (!item) return 0;
  return item.stackable ? item.maxStack : 1;
}

// Footprint [w, h] of an item as placed (swapped when rotated).
export function sizeFor(itemId, rotated) {
  const item = ITEMS[itemId];
  const [w, h] = (item && item.size) || [1, 1];
  return rotated ? [h, w] : [w, h];
}
