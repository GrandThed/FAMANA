-- Ground drops. When a slime dies, rolls its loot table and spawns physical
-- item drops. Players pick them up by walking over them; the item is added to
-- the inventory via the backend. Drops despawn after a timeout.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))
local ArtKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArtKit"))
local ItemModels = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemModels"))
local PlayerService = require(script.Parent.PlayerService)
local EnemyService = require(script.Parent.EnemyService)

local DropService = {}

local DROP_LIFETIME = 120
local RETRY_DELAY = 1 -- if inventory is full, wait before letting the same drop retry

-- Loot tables: [source] = { { itemId, chance, min, max }, ... }
local LOOT = {
	slime = {
		{ itemId = "slime_goo", chance = 1.0, min = 1, max = 1 },
		{ itemId = "wood", chance = 0.25, min = 1, max = 1 },
	},
	goblin = {
		{ itemId = "goblin_ear", chance = 1.0, min = 1, max = 1 },
		{ itemId = "stone", chance = 0.4, min = 1, max = 2 },
		{ itemId = "sword_iron", chance = 0.05, min = 1, max = 1 }, -- rare
	},
}

local DROP_VISUAL_SIZE = 1.6 -- max extent of a drop's miniature model, studs
local dropScale = {} -- [itemId] = cached uniform scale for the drop visual

-- Scale that fits the item's model inside DROP_VISUAL_SIZE, or nil if the
-- item has no model (falls back to the generic glowing cube).
local function visualScale(itemId)
	local cached = dropScale[itemId]
	if cached then
		return cached
	end
	local model = ItemModels.build(itemId)
	if not model then
		return nil
	end
	local size = model:GetExtentsSize()
	model:Destroy()
	local scale = DROP_VISUAL_SIZE / math.max(size.X, size.Y, size.Z)
	dropScale[itemId] = scale
	return scale
end

local dropFolder

local function rollLoot(source)
	local lootTable = LOOT[source]
	if not lootTable then
		return {}
	end
	local results = {}
	for _, entry in ipairs(lootTable) do
		if math.random() <= entry.chance then
			results[#results + 1] = {
				itemId = entry.itemId,
				quantity = math.random(entry.min, entry.max),
			}
		end
	end
	return results
end

local function playerFromHit(hit)
	local character = hit.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return Players:GetPlayerFromCharacter(character)
	end
	return nil
end

local function releaseClaimLater(part)
	-- Inventory full or backend error: release the claim after a beat so the
	-- player can grab it again once they've made room.
	task.delay(RETRY_DELAY, function()
		if part.Parent then
			part:SetAttribute("claimed", false)
		end
	end)
end

local function tryPickup(player, part)
	if part:GetAttribute("claimed") then
		return
	end
	-- Claim before the (yielding) backend call so overlapping touches can't
	-- double-pick the same drop.
	part:SetAttribute("claimed", true)

	local itemId = part:GetAttribute("itemId")
	local quantity = part:GetAttribute("quantity")
	local def = Items.get(itemId)
	local stackable = def and def.stackable or false

	-- Stackables pick up partially (whatever fits); the rest stays on the
	-- ground with no fuss (decided UX: full inventory shows no toast).
	local ok, added = PlayerService.addItem(player, itemId, quantity, stackable)
	if ok and added >= quantity then
		part:Destroy()
	elseif ok and added > 0 then
		local left = quantity - added
		part:SetAttribute("quantity", left)
		local billboard = part:FindFirstChildOfClass("BillboardGui")
		local label = billboard and billboard:FindFirstChildOfClass("TextLabel")
		if label then
			label.Text = (def and def.name or itemId) .. (left > 1 and (" x" .. left) or "")
		end
		releaseClaimLater(part)
	else
		releaseClaimLater(part)
	end
end

local function spawnDrop(itemId, quantity, position)
	local def = Items.get(itemId)
	local spot = position + Vector3.new(math.random(-30, 30) / 10, 2, math.random(-30, 30) / 10)

	-- The root part is the touch/pickup zone; the item's miniature model is
	-- welded onto it (it follows the root's bob/spin CFrame updates).
	local part = Instance.new("Part")
	part.Name = "Drop"
	part.Size = Vector3.new(1.2, 1.2, 1.2)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- pickup works via Touched; don't block ground raycasts
	part.CFrame = CFrame.new(spot)
	part:SetAttribute("itemId", itemId)
	part:SetAttribute("quantity", quantity)
	part:SetAttribute("baseY", spot.Y)

	local scale = visualScale(itemId)
	if scale then
		part.Transparency = 1
		ArtKit.weld(part, ItemModels.get(itemId), scale)
	else
		part.Color = Color3.fromRGB(230, 200, 90)
		part.Material = Enum.Material.Neon
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 80, 0, 20)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = (def and def.name or itemId) .. (quantity > 1 and (" x" .. quantity) or "")
	label.Parent = billboard

	part.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		if player then
			tryPickup(player, part)
		end
	end)

	part.Parent = dropFolder

	task.delay(DROP_LIFETIME, function()
		if part.Parent then
			part:Destroy()
		end
	end)
end

-- Public: spawn a ground drop. Other systems (e.g. item stands) use this so
-- everything a player can pick up flows through the same claim/persist path.
function DropService.spawn(itemId, quantity, position)
	spawnDrop(itemId, quantity, position)
end

function DropService.start()
	dropFolder = Instance.new("Folder")
	dropFolder.Name = "Drops"
	dropFolder.Parent = Workspace

	-- Spawn loot when an enemy dies.
	EnemyService.onKilled(function(source, position, _killer)
		for _, drop in ipairs(rollLoot(source)) do
			spawnDrop(drop.itemId, drop.quantity, position)
		end
	end)

	-- Spin + bob the drops for visibility.
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for _, part in ipairs(dropFolder:GetChildren()) do
			if part:IsA("BasePart") then
				local baseY = part:GetAttribute("baseY") or part.Position.Y
				local y = baseY + math.sin(t * 3) * 0.3
				part.CFrame = CFrame.new(part.Position.X, y, part.Position.Z) * CFrame.Angles(0, t * 2, 0)
			end
		end
	end)
end

return DropService
