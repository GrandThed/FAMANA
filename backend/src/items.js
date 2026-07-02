// Static item definitions. Mirrored in the Roblox code (shared/Items.lua).
// Keep the two in sync by hand for the MVP.

export const ITEMS = {
  sword_basic: {
    id: "sword_basic",
    name: "Basic Sword",
    type: "weapon",
    stackable: false,
    maxStack: 1,
    damage: 10,
  },
  axe_basic: {
    id: "axe_basic",
    name: "Basic Axe",
    type: "tool",
    stackable: false,
    maxStack: 1,
    toolType: "axe",
    gatherPower: 1,
  },
  pickaxe_basic: {
    id: "pickaxe_basic",
    name: "Basic Pickaxe",
    type: "tool",
    stackable: false,
    maxStack: 1,
    toolType: "pickaxe",
    gatherPower: 1,
  },
  sword_iron: {
    id: "sword_iron",
    name: "Iron Sword",
    type: "weapon",
    stackable: false,
    maxStack: 1,
    damage: 20,
  },
  wood: {
    id: "wood",
    name: "Wood",
    type: "resource",
    stackable: true,
    maxStack: 50,
  },
  stone: {
    id: "stone",
    name: "Stone",
    type: "resource",
    stackable: true,
    maxStack: 50,
  },
  slime_goo: {
    id: "slime_goo",
    name: "Slime Goo",
    type: "resource",
    stackable: true,
    maxStack: 50,
  },
  goblin_ear: {
    id: "goblin_ear",
    name: "Goblin Ear",
    type: "resource",
    stackable: true,
    maxStack: 50,
  },
};

// Items a brand-new player starts with.
export const STARTER_ITEMS = [
  { itemId: "sword_basic", quantity: 1 },
  { itemId: "axe_basic", quantity: 1 },
  { itemId: "pickaxe_basic", quantity: 1 },
];

// The permanent starter kit (tools/weapons) is reconciled on every load so
// existing players pick up newly-added starter gear (e.g. the pickaxe).
export const STARTER_EQUIPPABLES = STARTER_ITEMS.filter((entry) => {
  const def = ITEMS[entry.itemId];
  return def && (def.type === "weapon" || def.type === "tool");
});

export const INVENTORY_CAPACITY = 20;

export function getItem(itemId) {
  return ITEMS[itemId] || null;
}

export function maxStackFor(itemId) {
  const item = ITEMS[itemId];
  if (!item) return 0;
  return item.stackable ? item.maxStack : 1;
}
