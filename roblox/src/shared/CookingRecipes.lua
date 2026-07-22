-- Cooking & Alchemy recipe definitions.
-- Interacting with a cauldron ("olla_campamento") allows preparing food and brewing potions.

local CookingRecipes = {}

CookingRecipes.defs = {
	estofado_jabali = {
		id = "estofado_jabali",
		name = "Estofado de Jabalí",
		category = "cooking",
		result = { itemId = "estofado_jabali", quantity = 1 },
		ingredients = {
			{ itemId = "carne_jabali", quantity = 2 },
			{ itemId = "hierba_roja", quantity = 1 },
		},
	},
	pan_viaje = {
		id = "pan_viaje",
		name = "Pan de Viaje",
		category = "cooking",
		result = { itemId = "pan_viaje", quantity = 2 },
		ingredients = {
			{ itemId = "trigo", quantity = 2 },
		},
	},
	pocion_salud_mayor = {
		id = "pocion_salud_mayor",
		name = "Poción de Salud Mayor",
		category = "alchemy",
		result = { itemId = "pocion_salud_mayor", quantity = 1 },
		ingredients = {
			{ itemId = "hierba_roja", quantity = 2 },
		},
	},
	pocion_mana = {
		id = "pocion_mana",
		name = "Poción de Maná",
		category = "alchemy",
		result = { itemId = "pocion_mana", quantity = 1 },
		ingredients = {
			{ itemId = "hierba_azul", quantity = 2 },
		},
	},
	elixir_velocidad = {
		id = "elixir_velocidad",
		name = "Elixir de Velocidad",
		category = "alchemy",
		result = { itemId = "elixir_velocidad", quantity = 1 },
		ingredients = {
			{ itemId = "hierba_agil", quantity = 2 },
		},
	},
}

function CookingRecipes.get(id)
	return CookingRecipes.defs[id]
end

function CookingRecipes.list()
	local out = {}
	for _, def in pairs(CookingRecipes.defs) do
		table.insert(out, def)
	end
	return out
end

return CookingRecipes
