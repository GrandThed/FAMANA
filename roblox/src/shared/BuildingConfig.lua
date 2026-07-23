-- Building Config (Rust-Style Modular Building System).
-- Defines structural modular building pieces (floors, walls, doors, windows, roofs) for Guild Headquarters.

local BuildingConfig = {}

BuildingConfig.GRID_SIZE = 12 -- 12-stud modular grid for 48x48 plots

BuildingConfig.PIECES = {
	piso_madera = {
		id = "piso_madera",
		name = "Piso de Madera",
		icon = "🟩",
		size = Vector3.new(12, 0.5, 12),
		cost = { wood = 4 },
		offset = Vector3.new(0, 0.25, 0),
		colorName = "trunk",
	},
	pared_madera = {
		id = "pared_madera",
		name = "Pared de Madera",
		icon = "🧱",
		size = Vector3.new(12, 10, 0.6),
		cost = { wood = 6 },
		offset = Vector3.new(0, 5, 0),
		colorName = "trunkDark",
	},
	puerta_madera = {
		id = "puerta_madera",
		name = "Pared con Puerta",
		icon = "🚪",
		size = Vector3.new(12, 10, 0.6),
		cost = { wood = 8 },
		offset = Vector3.new(0, 5, 0),
		colorName = "trunkDark",
		hasDoor = true,
	},
	pared_ventana = {
		id = "pared_ventana",
		name = "Pared con Ventana",
		icon = "🪟",
		size = Vector3.new(12, 10, 0.6),
		cost = { wood = 7 },
		offset = Vector3.new(0, 5, 0),
		colorName = "trunkDark",
		hasWindow = true,
	},
	techo_madera = {
		id = "techo_madera",
		name = "Techo de Madera",
		icon = "🏠",
		size = Vector3.new(12, 0.5, 12),
		cost = { wood = 5 },
		offset = Vector3.new(0, 10.25, 0),
		colorName = "trunk",
	},
	valla_madera = {
		id = "valla_madera",
		name = "Valla de Madera",
		icon = "🪵",
		size = Vector3.new(12, 4, 0.4),
		cost = { wood = 3 },
		offset = Vector3.new(0, 2, 0),
		colorName = "trunkDark",
	},
	piso_piedra = {
		id = "piso_piedra",
		name = "Piso de Piedra",
		icon = "⬛",
		size = Vector3.new(12, 0.5, 12),
		cost = { stone = 4 },
		offset = Vector3.new(0, 0.25, 0),
		colorName = "stoneDark",
		material = Enum.Material.Slate,
	},
	pared_piedra = {
		id = "pared_piedra",
		name = "Pared de Piedra",
		icon = "🏛️",
		size = Vector3.new(12, 10, 0.6),
		cost = { stone = 6 },
		offset = Vector3.new(0, 5, 0),
		colorName = "stoneDark",
		material = Enum.Material.Cobblestone,
	},
	puerta_piedra = {
		id = "puerta_piedra",
		name = "Puerta de Piedra",
		icon = "🚪",
		size = Vector3.new(12, 10, 0.6),
		cost = { stone = 8 },
		offset = Vector3.new(0, 5, 0),
		colorName = "stoneDark",
		material = Enum.Material.Cobblestone,
		hasDoor = true,
	},
	pared_ventana_piedra = {
		id = "pared_ventana_piedra",
		name = "Ventana de Piedra",
		icon = "🪟",
		size = Vector3.new(12, 10, 0.6),
		cost = { stone = 7 },
		offset = Vector3.new(0, 5, 0),
		colorName = "stoneDark",
		material = Enum.Material.Cobblestone,
		hasWindow = true,
	},
	valla_piedra = {
		id = "valla_piedra",
		name = "Cerca de Piedra",
		icon = "🧱",
		size = Vector3.new(12, 4, 0.6),
		cost = { stone = 3 },
		offset = Vector3.new(0, 2, 0),
		colorName = "stoneDark",
		material = Enum.Material.Cobblestone,
	},
	techo_piedra = {
		id = "techo_piedra",
		name = "Techo de Piedra",
		icon = "🏰",
		size = Vector3.new(12, 0.5, 12),
		cost = { stone = 5 },
		offset = Vector3.new(0, 10.25, 0),
		colorName = "stoneDark",
		material = Enum.Material.Slate,
	},
}

function BuildingConfig.getPiece(pieceId)
	return BuildingConfig.PIECES[pieceId]
end

return BuildingConfig
