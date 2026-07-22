-- Shared Guild Research Catalog (Warframe Dojo Tech Tree Style).
-- Defines research labs, projects, material/gold requirements, recipe unlocks, and Guild XP rewards.

local GuildResearchCatalog = {}

GuildResearchCatalog.labs = {
	forge = {
		id = "forge",
		name = "Laboratorio de Forja y Armería",
		icon = "⚒️",
		description = "Investiga proyectos para sintetizar equipamiento de rasgos TFT avanzados y estaciones de maestría.",
		projects = {
			res_dual_blade = {
				id = "res_dual_blade",
				name = "Hoja de Fuego Místico",
				description = "Sintetiza la receta de una espada legendaria con rasgos Arcane + Juggernaut.",
				lab = "forge",
				cost = {
					wood = 40,
					iron_ingot = 20,
					gold = 300,
				},
				guildXp = 100,
				unlocksRecipe = "espadon_hierro",
			},
			res_rune_shield = {
				id = "res_rune_shield",
				name = "Escudo Rúnico de Protección",
				description = "Desbloquea la receta de un escudo que otorga puntos de Shieldmaster + Arcane.",
				lab = "forge",
				cost = {
					wood = 50,
					iron_ingot = 30,
					gold = 500,
				},
				guildXp = 150,
				unlocksRecipe = "escudo_runico",
			},
		},
	},
	alchemy = {
		id = "alchemy",
		name = "Laboratorio de Alquimia y Botánica",
		icon = "🧪",
		description = "Investiga destilados botánicos avanzados y recetas gastronómicas supremas.",
		projects = {
			res_titan_elixir = {
				id = "res_titan_elixir",
				name = "Elixir Titánico de Fuerza",
				description = "Destilado de hierbas medicinales que otorga un potente incremento de poder en batalla.",
				lab = "alchemy",
				cost = {
					hierba_roja = 15,
					hierba_azul = 15,
					gold = 400,
				},
				guildXp = 120,
				unlocksRecipe = "elixir_fuerza_suprema",
			},
			res_mystic_soup = {
				id = "res_mystic_soup",
				name = "Sopa de Mariscos Mística",
				description = "Receta gastronómica de gremio que otorga regeneración constante de maná y salud.",
				lab = "alchemy",
				cost = {
					trucha_plateada = 10,
					hierba_agil = 10,
					gold = 350,
				},
				guildXp = 100,
				unlocksRecipe = "sopa_pescado",
			},
		},
	},
	tactics = {
		id = "tactics",
		name = "Laboratorio de Estandartes y Tácticas",
		icon = "🚩",
		description = "Investiga estandartes de batalla que otorgan bonificaciones pasivas en área a todos los miembros.",
		projects = {
			res_prosperity_banner = {
				id = "res_prosperity_banner",
				name = "Estandarte de Prosperidad",
				description = "Otorga una bonificación pasiva del +15% de Oro ganado para todos los miembros del gremio.",
				lab = "tactics",
				cost = {
					wood = 60,
					copper_ingot = 20,
					gold = 600,
				},
				guildXp = 200,
				buff = "guild_gold_boost",
			},
			res_hunt_banner = {
				id = "res_hunt_banner",
				name = "Estandarte de Cacería",
				description = "Otorga una bonificación pasiva del +15% de Experiencia ganada en combate para todo el gremio.",
				lab = "tactics",
				cost = {
					wood = 60,
					iron_ingot = 20,
					gold = 800,
				},
				guildXp = 250,
				buff = "guild_xp_boost",
			},
		},
	},
}

function GuildResearchCatalog.getProject(projectId)
	for _, lab in pairs(GuildResearchCatalog.labs) do
		if lab.projects[projectId] then
			return lab.projects[projectId]
		end
	end
	return nil
end

return GuildResearchCatalog
