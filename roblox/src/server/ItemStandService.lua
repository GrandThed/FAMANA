-- Item display stands: a low-poly pedestal showing a slowly spinning copy of
-- an item. A ProximityPrompt on the pedestal lets players take a copy, which
-- spawns as a normal ground drop — pickup and persistence go through the
-- usual DropService/PlayerService flow, so stands never touch inventories
-- directly. Data-driven: add a stand via a STAND_DEFS entry.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtKit = require(Shared:WaitForChild("ArtKit"))
local ItemModels = require(Shared:WaitForChild("ItemModels"))
local Items = require(Shared:WaitForChild("Items"))
local DropService = require(script.Parent.DropService)

local ItemStandService = {}

local DISPLAY_SIZE = 2.2 -- max extent of the displayed copy, studs
local SPIN_SPEED = 0.8 -- radians/second turntable spin
local TAKE_COOLDOWN = 2 -- seconds between takes per stand
local PEDESTAL_TOP = 3.1 -- height of the pedestal cap above the ground

-- { itemId, position, facing? (degrees yaw; drops land in front, -Z) }
local STAND_DEFS = {
	{ itemId = "sword_basic", position = Vector3.new(2, 0, -34) },
	{ itemId = "sword_iron", position = Vector3.new(7, 0, -34) },
	{ itemId = "staff_basic", position = Vector3.new(12, 0, -34) },
	{ itemId = "bow_basic", position = Vector3.new(17, 0, -34) },
	{ itemId = "axe_basic", position = Vector3.new(-3, 0, -34) },
	{ itemId = "pickaxe_basic", position = Vector3.new(-8, 0, -34) },
}

local standFolder
local displays = {} -- { root (Part), center (Vector3), offset (Vector3) }

local function groundY(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { standFolder }
	local result = Workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -1000, 0), params)
	return result and result.Position.Y or 0
end

local function buildStand(def)
	local specs = ItemModels.get(def.itemId)
	if not specs then
		warn("[ItemStandService] no model for item " .. tostring(def.itemId))
		return
	end
	local itemDef = Items.get(def.itemId)

	local y = groundY(def.position.X, def.position.Z)
	local origin = CFrame.new(def.position.X, y, def.position.Z)
		* CFrame.Angles(0, math.rad(def.facing or 0), 0)

	local pedestal = ArtKit.build("ItemStand", origin, {
		{ name = "Base", size = Vector3.new(3, 0.5, 3), offset = Vector3.new(0, 0.25, 0), color = "stoneDark", primary = true },
		{ name = "Column", size = Vector3.new(1.5, 2.2, 1.5), offset = Vector3.new(0, 1.6, 0), rot = Vector3.new(0, 45, 0), color = "stone" },
		{ name = "Cap", size = Vector3.new(2.2, 0.4, 2.2), offset = Vector3.new(0, 2.9, 0), color = "stoneLight" },
	})
	pedestal.Parent = standFolder

	-- Fit the item copy into DISPLAY_SIZE and center it above the cap. The
	-- model's bounds center isn't its origin (grips sit at the origin), so
	-- the root is offset to make the turntable spin around the visual center.
	local probe = ItemModels.build(def.itemId)
	local boundsCFrame, boundsSize = probe:GetBoundingBox()
	probe:Destroy()
	local scale = DISPLAY_SIZE / math.max(boundsSize.X, boundsSize.Y, boundsSize.Z)
	local offset = boundsCFrame.Position * scale -- bounds center relative to the root
	local center = (origin * CFrame.new(0, PEDESTAL_TOP + (boundsSize.Y * scale) / 2 + 0.4, 0)).Position

	local root = Instance.new("Part")
	root.Name = "Display"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CFrame = CFrame.new(center - offset)
	ArtKit.weld(root, specs, scale)
	root.Parent = pedestal

	table.insert(displays, { root = root, center = center, offset = offset })

	-- Interaction: hold to take a copy; it lands as a drop in front of the stand.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take a copy"
	prompt.ObjectText = itemDef and itemDef.name or def.itemId
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = pedestal.Cap

	local lastTake = 0
	prompt.Triggered:Connect(function()
		local now = os.clock()
		if now - lastTake < TAKE_COOLDOWN then
			return
		end
		lastTake = now
		local front = (origin * CFrame.new(0, 0, -4)).Position
		DropService.spawn(def.itemId, 1, Vector3.new(front.X, groundY(front.X, front.Z), front.Z))
	end)
end

function ItemStandService.start()
	standFolder = Instance.new("Folder")
	standFolder.Name = "ItemStands"
	standFolder.Parent = Workspace

	for _, def in ipairs(STAND_DEFS) do
		buildStand(def)
	end

	-- Turntable: spin every display around its visual center.
	RunService.Heartbeat:Connect(function()
		local angle = os.clock() * SPIN_SPEED
		local spin = CFrame.Angles(0, angle, 0)
		for _, display in ipairs(displays) do
			display.root.CFrame = CFrame.new(display.center) * spin * CFrame.new(-display.offset)
		end
	end)
end

return ItemStandService
