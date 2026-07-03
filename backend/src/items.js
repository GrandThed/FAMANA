// Static item definitions. Mirrored in the Roblox code (shared/Items.lua).
// Keep the two in sync by hand for the MVP.

export const ITEMS = {
  sword_basic: {
    id: "sword_basic",
    name: "Basic Sword",
    type: "weapon",
    weaponType: "melee",
    stackable: false,
    maxStack: 1,
    damage: 10,
    reach: 11, // studs the swing (and its focus/targeting) can connect
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
  },
  sword_iron: {
    id: "sword_iron",
    name: "Iron Sword",
    type: "weapon",
    weaponType: "melee",
    stackable: false,
    maxStack: 1,
    damage: 20,
    reach: 11,
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

export const INVENTORY_CAPACITY = 20;

export function getItem(itemId) {
  return ITEMS[itemId] || null;
}

export function maxStackFor(itemId) {
  const item = ITEMS[itemId];
  if (!item) return 0;
  return item.stackable ? item.maxStack : 1;
}
