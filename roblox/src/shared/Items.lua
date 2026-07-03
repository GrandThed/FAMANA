-- Static item definitions. MUST stay in sync with backend/src/items.js.

local Items = {}

Items.defs = {
	sword_basic = {
		id = "sword_basic",
		name = "Basic Sword",
		type = "weapon",
		weaponType = "melee",
		stackable = false,
		maxStack = 1,
		damage = 10,
	},
	axe_basic = {
		id = "axe_basic",
		name = "Basic Axe",
		type = "tool",
		stackable = false,
		maxStack = 1,
		toolType = "axe",
		gatherPower = 1,
	},
	pickaxe_basic = {
		id = "pickaxe_basic",
		name = "Basic Pickaxe",
		type = "tool",
		stackable = false,
		maxStack = 1,
		toolType = "pickaxe",
		gatherPower = 1,
	},
	sword_iron = {
		id = "sword_iron",
		name = "Iron Sword",
		type = "weapon",
		weaponType = "melee",
		stackable = false,
		maxStack = 1,
		damage = 20,
	},
	staff_basic = {
		id = "staff_basic",
		name = "Magic Staff",
		type = "weapon",
		weaponType = "ranged",
		stackable = false,
		maxStack = 1,
		damage = 15,
	},
	wood = {
		id = "wood",
		name = "Wood",
		type = "resource",
		stackable = true,
		maxStack = 50,
	},
	stone = {
		id = "stone",
		name = "Stone",
		type = "resource",
		stackable = true,
		maxStack = 50,
	},
	slime_goo = {
		id = "slime_goo",
		name = "Slime Goo",
		type = "resource",
		stackable = true,
		maxStack = 50,
	},
	goblin_ear = {
		id = "goblin_ear",
		name = "Goblin Ear",
		type = "resource",
		stackable = true,
		maxStack = 50,
	},
}

function Items.get(itemId)
	return Items.defs[itemId]
end

function Items.maxStackFor(itemId)
	local def = Items.defs[itemId]
	if not def then
		return 0
	end
	return def.stackable and def.maxStack or 1
end

return Items
