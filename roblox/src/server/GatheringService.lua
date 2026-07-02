-- Tree resource nodes. Spawns trees in the world; swinging an axe near one
-- harvests wood into the player's inventory (persisted via the backend).
-- Trees deplete to a stump and regrow after a delay. In-memory per server
-- (per the MVP spec) -- tree state is not persisted.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))
local PlayerService = require(script.Parent.PlayerService)
local ToolService = require(script.Parent.ToolService)

local GatheringService = {}

-- Fixed tree spots for this cell (X/Z; ground Y is found by raycast).
local TREE_SPOTS = {
	Vector3.new(20, 0, 12),
	Vector3.new(28, 0, 18),
	Vector3.new(16, 0, 24),
	Vector3.new(34, 0, 8),
	Vector3.new(24, 0, 30),
}

local WOOD_CAPACITY = 5
local GATHER_RANGE = 12
local GATHER_COOLDOWN = 1
local RESPAWN_TIME = 60

local trees = {} -- { model, trunk, leaves, wood, base = Vector3 }
local lastGather = {} -- [userId] = os.clock()
local resourceFolder

local function groundY(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { resourceFolder }
	local result = Workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -1000, 0), params)
	return result and result.Position.Y or 0
end

local function setDepleted(tree, depleted)
	if depleted then
		tree.leaves.Transparency = 1
		tree.trunk.Size = Vector3.new(2, 2, 2)
		tree.trunk.Position = tree.base + Vector3.new(0, 1, 0)
		tree.trunk.Color = Color3.fromRGB(80, 55, 32)
	else
		tree.leaves.Transparency = 0
		tree.trunk.Size = Vector3.new(2, 8, 2)
		tree.trunk.Position = tree.base + Vector3.new(0, 4, 0)
		tree.trunk.Color = Color3.fromRGB(105, 70, 40)
	end
end

local function buildTree(spot)
	local y = groundY(spot.X, spot.Z)
	local base = Vector3.new(spot.X, y, spot.Z)

	local model = Instance.new("Model")
	model.Name = "Tree"

	local trunk = Instance.new("Part")
	trunk.Name = "Trunk"
	trunk.Anchored = true
	trunk.Size = Vector3.new(2, 8, 2)
	trunk.Position = base + Vector3.new(0, 4, 0)
	trunk.Color = Color3.fromRGB(105, 70, 40)
	trunk.Material = Enum.Material.Wood
	trunk.Parent = model

	local leaves = Instance.new("Part")
	leaves.Name = "Leaves"
	leaves.Shape = Enum.PartType.Ball
	leaves.Anchored = true
	leaves.CanCollide = false
	leaves.Size = Vector3.new(8, 8, 8)
	leaves.Position = base + Vector3.new(0, 10, 0)
	leaves.Color = Color3.fromRGB(60, 140, 60)
	leaves.Material = Enum.Material.Grass
	leaves.Parent = model

	model.PrimaryPart = trunk
	model.Parent = resourceFolder

	return { model = model, trunk = trunk, leaves = leaves, wood = WOOD_CAPACITY, base = base }
end

local function findNearbyTree(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local closest, closestDist
	for _, tree in ipairs(trees) do
		if tree.wood > 0 then
			local dist = (tree.trunk.Position - root.Position).Magnitude
			if dist <= GATHER_RANGE and (not closestDist or dist < closestDist) then
				closest, closestDist = tree, dist
			end
		end
	end
	return closest
end

-- Called by ToolService when a "tool" item is activated.
local function onToolSwing(player, tool, def)
	if def.toolType ~= "axe" then
		return
	end

	local now = os.clock()
	if now - (lastGather[player.UserId] or 0) < GATHER_COOLDOWN then
		return
	end

	local tree = findNearbyTree(player.Character)
	if not tree then
		return
	end
	lastGather[player.UserId] = now

	local amount = math.min(def.gatherPower or 1, tree.wood)
	-- Persist first (source of truth); only deplete the tree if it stuck.
	local ok = PlayerService.addItem(player, "wood", amount)
	if not ok then
		return -- inventory full or backend error; leave the tree alone
	end

	tree.wood -= amount
	if tree.wood <= 0 then
		setDepleted(tree, true)
		task.delay(RESPAWN_TIME, function()
			tree.wood = WOOD_CAPACITY
			setDepleted(tree, false)
		end)
	end
end

function GatheringService.start()
	resourceFolder = Instance.new("Folder")
	resourceFolder.Name = "Resources"
	resourceFolder.Parent = Workspace

	for _, spot in ipairs(TREE_SPOTS) do
		table.insert(trees, buildTree(spot))
	end

	ToolService.registerActivated("tool", onToolSwing)

	Players.PlayerRemoving:Connect(function(player)
		lastGather[player.UserId] = nil
	end)
end

return GatheringService
