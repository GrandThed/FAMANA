-- Low-poly models for every item, in ArtKit spec format. One catalog serves
-- both sides: the server builds held Tools from it (ToolService) and the
-- client renders inventory/hotbar thumbnails from it (ViewportFrames).
--
-- Conventions:
--   * The FIRST spec is the grip/primary part and must sit at the origin
--     (no offset) — for equippables it becomes the Tool's Handle and the
--     hand holds its center.
--   * Equippables stand along +Y (up when held); remaining offsets are
--     relative to the first part.
--   * Colors come from ArtKit.Palette — no inline RGB here.

local ArtKit = require(script.Parent.ArtKit)

local V = Vector3.new

local ItemModels = {}

ItemModels.defs = {
	-- ---- weapons ----------------------------------------------------------

	sword_basic = {
		{ name = "Grip", size = V(0.32, 1.1, 0.32), color = "trunkDark" },
		{ name = "Wrap1", size = V(0.38, 0.16, 0.38), offset = V(0, -0.25, 0), color = "trunk" },
		{ name = "Wrap2", size = V(0.38, 0.16, 0.38), offset = V(0, 0.2, 0), color = "trunk" },
		{ name = "Pommel", size = V(0.44, 0.34, 0.44), offset = V(0, -0.72, 0), rot = V(0, 45, 0), color = "steelDark" },
		{ name = "Guard", size = V(1.5, 0.22, 0.5), offset = V(0, 0.66, 0), color = "steelDark" },
		{ name = "Blade", size = V(0.55, 2.5, 0.16), offset = V(0, 2.0, 0), color = "steel" },
		{ name = "Fuller", size = V(0.16, 2.3, 0.2), offset = V(0, 1.95, 0), color = "steelDark" },
		{ name = "Tip", size = V(0.34, 0.6, 0.14), offset = V(0, 3.55, 0), color = "steel" },
	},

	sword_iron = {
		{ name = "Grip", size = V(0.34, 1.2, 0.34), color = "trunkDark" },
		{ name = "Wrap1", size = V(0.4, 0.16, 0.4), offset = V(0, -0.28, 0), color = "trunk" },
		{ name = "Wrap2", size = V(0.4, 0.16, 0.4), offset = V(0, 0.22, 0), color = "trunk" },
		{ name = "Pommel", size = V(0.5, 0.4, 0.5), offset = V(0, -0.78, 0), rot = V(0, 45, 0), color = "gold" },
		{ name = "Guard", size = V(1.7, 0.26, 0.55), offset = V(0, 0.72, 0), color = "gold" },
		{ name = "GuardL", size = V(0.3, 0.4, 0.6), offset = V(-0.85, 0.72, 0), color = "gold" },
		{ name = "GuardR", size = V(0.3, 0.4, 0.6), offset = V(0.85, 0.72, 0), color = "gold" },
		{ name = "Blade", size = V(0.65, 2.9, 0.2), offset = V(0, 2.25, 0), color = "steel" },
		{ name = "Fuller", size = V(0.18, 2.7, 0.24), offset = V(0, 2.2, 0), color = "steelDark" },
		{ name = "Tip", size = V(0.4, 0.7, 0.18), offset = V(0, 4.05, 0), color = "steel" },
	},

	staff_basic = {
		{ name = "Shaft", size = V(0.28, 4.6, 0.28), color = "trunkDark" },
		{ name = "GripWrap", size = V(0.36, 0.8, 0.36), offset = V(0, -0.7, 0), color = "trunk" },
		{ name = "Butt", size = V(0.38, 0.28, 0.38), offset = V(0, -2.35, 0), color = "gold" },
		{ name = "Collar", size = V(0.42, 0.3, 0.42), offset = V(0, 1.75, 0), rot = V(0, 45, 0), color = "gold" },
		{ name = "ProngL", size = V(0.2, 0.9, 0.2), offset = V(-0.32, 2.25, 0), rot = V(0, 0, 15), color = "trunkDark" },
		{ name = "ProngR", size = V(0.2, 0.9, 0.2), offset = V(0.32, 2.25, 0), rot = V(0, 0, -15), color = "trunkDark" },
		{ name = "Orb", shape = "Ball", size = V(0.85, 0.85, 0.85), offset = V(0, 2.8, 0), color = "magic", material = Enum.Material.Neon },
	},

	-- ---- tools -------------------------------------------------------------

	axe_basic = {
		{ name = "Shaft", size = V(0.36, 3, 0.36), color = "trunk" },
		{ name = "Butt", size = V(0.44, 0.3, 0.44), offset = V(0, -1.6, 0), color = "trunkDark" },
		{ name = "Binding", size = V(0.5, 0.55, 0.5), offset = V(0, 1.2, 0), color = "trunkDark" },
		{ name = "HeadCore", size = V(0.9, 0.7, 0.3), offset = V(0.45, 1.35, 0), color = "steelDark" },
		{ name = "Blade", size = V(0.5, 1.15, 0.24), offset = V(1.0, 1.35, 0), color = "steel" },
		{ name = "Poll", size = V(0.35, 0.5, 0.32), offset = V(-0.5, 1.35, 0), color = "steelDark" },
	},

	pickaxe_basic = {
		{ name = "Shaft", size = V(0.36, 3, 0.36), color = "trunk" },
		{ name = "Butt", size = V(0.44, 0.3, 0.44), offset = V(0, -1.6, 0), color = "trunkDark" },
		{ name = "Binding", size = V(0.5, 0.5, 0.5), offset = V(0, 1.1, 0), color = "trunkDark" },
		{ name = "HeadCore", size = V(0.8, 0.42, 0.4), offset = V(0, 1.42, 0), color = "steelDark" },
		{ name = "ArmL", size = V(1.0, 0.32, 0.32), offset = V(-0.85, 1.32, 0), rot = V(0, 0, 15), color = "steel" },
		{ name = "TipL", size = V(0.45, 0.24, 0.24), offset = V(-1.5, 1.12, 0), rot = V(0, 0, 15), color = "steelDark" },
		{ name = "ArmR", size = V(1.0, 0.32, 0.32), offset = V(0.85, 1.32, 0), rot = V(0, 0, -15), color = "steel" },
		{ name = "TipR", size = V(0.45, 0.24, 0.24), offset = V(1.5, 1.12, 0), rot = V(0, 0, -15), color = "steelDark" },
	},

	-- ---- resources (inventory thumbnails, ground drops) --------------------

	wood = {
		{ name = "LogA", shape = "Cylinder", size = V(2.2, 0.7, 0.7), color = "trunk", rot = V(0, 15, 0) },
		{ name = "LogB", shape = "Cylinder", size = V(1.9, 0.6, 0.6), offset = V(0.1, 0.55, 0.1), rot = V(0, -25, 0), color = "trunkDark" },
	},

	stone = {
		{ name = "ChunkA", size = V(1.4, 1.0, 1.2), rot = V(6, 25, -4), color = "stone" },
		{ name = "ChunkB", size = V(0.9, 0.7, 0.8), offset = V(0.6, 0.35, -0.3), rot = V(-10, -35, 8), color = "stoneDark" },
		{ name = "ChunkC", size = V(0.6, 0.5, 0.6), offset = V(-0.6, 0.3, 0.4), rot = V(0, 50, 12), color = "stoneLight" },
	},

	slime_goo = {
		{ name = "BlobA", shape = "Ball", size = V(1.1, 1.1, 1.1), color = "slime", transparency = 0.25 },
		{ name = "BlobB", shape = "Ball", size = V(0.7, 0.7, 0.7), offset = V(0.45, 0.3, 0.15), color = "slime", transparency = 0.25 },
		{ name = "BlobC", shape = "Ball", size = V(0.5, 0.5, 0.5), offset = V(-0.4, 0.35, -0.2), color = "slime", transparency = 0.25 },
	},

	goblin_ear = {
		{ name = "EarBase", size = V(0.45, 0.6, 0.25), rot = V(0, 0, 20), color = "goblin" },
		{ name = "EarTip", shape = "Wedge", size = V(0.25, 0.7, 0.45), offset = V(-0.25, 0.55, 0), rot = V(0, 0, 30), color = "goblin" },
		{ name = "EarInner", size = V(0.24, 0.35, 0.28), offset = V(0.05, -0.05, 0), rot = V(0, 0, 20), color = "goblinDark" },
	},
}

function ItemModels.get(itemId)
	return ItemModels.defs[itemId]
end

-- Builds an anchored display model at the origin (thumbnails, drops).
function ItemModels.build(itemId)
	local specs = ItemModels.defs[itemId]
	if not specs then
		return nil
	end
	return ArtKit.build(itemId, CFrame.new(), specs)
end

-- Fills a ViewportFrame with the item's model, auto-framed by its bounding
-- box. Clears any previous preview. Returns true if the item has a model.
function ItemModels.preview(viewport, itemId)
	viewport:ClearAllChildren()
	local model = itemId and ItemModels.build(itemId)
	if not model then
		return false
	end
	model.Parent = viewport

	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local center = boundsCFrame.Position
	local distance = boundsSize.Magnitude * 1.5 + 0.5
	-- Slightly above and to the right, looking at the center.
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0.45, 0.3, 1).Unit * distance, center)
	return true
end

return ItemModels
