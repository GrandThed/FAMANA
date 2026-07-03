-- Turns equippable inventory items (weapons/tools) into Roblox Tools in the
-- player's hotbar. Plays a swing animation on activation and dispatches to
-- registered handlers so gathering (step 4) and combat (step 5) can hook in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))
local PlayerService = require(script.Parent.PlayerService)

local ToolService = {}

-- Item types that become held Tools.
local EQUIPPABLE = { weapon = true, tool = true }

-- Roblox's built-in "tool slash" animation — usable by any game.
local SLASH_ANIM = "rbxassetid://522635514"
local SWING_COOLDOWN = 0.4

-- [itemType] = function(player, tool, def)  registered by later systems.
ToolService.activatedHandlers = {}

function ToolService.registerActivated(itemType, handler)
	ToolService.activatedHandlers[itemType] = handler
end

-- One reusable Animation instance (the id never changes).
local swingAnim = Instance.new("Animation")
swingAnim.AnimationId = SLASH_ANIM

-- Per-player swing debounce so the animation can't be spammed.
local lastSwing = {}

local function playSwing(player)
	local now = os.clock()
	if now - (lastSwing[player.UserId] or 0) < SWING_COOLDOWN then
		return
	end
	lastSwing[player.UserId] = now

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local track = animator:LoadAnimation(swingAnim)
	track:Play()
	track.Stopped:Once(function()
		track:Destroy()
	end)
end

local function buildHandle(def)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	if def.type == "weapon" and def.weaponType == "ranged" then -- magic staff
		handle.Size = Vector3.new(0.3, 5, 0.3)
		handle.Color = Color3.fromRGB(90, 60, 40)
		handle.Material = Enum.Material.Wood
	elseif def.type == "weapon" then
		handle.Size = Vector3.new(0.3, 0.3, 4)
		handle.Color = Color3.fromRGB(200, 200, 210)
		handle.Material = Enum.Material.Metal
	else -- tool (e.g. axe)
		handle.Size = Vector3.new(0.4, 3, 0.4)
		handle.Color = Color3.fromRGB(120, 80, 45)
		handle.Material = Enum.Material.Wood
	end
	return handle
end

local function buildTool(player, itemId)
	local def = Items.get(itemId)
	local tool = Instance.new("Tool")
	tool.Name = def.name
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("itemId", itemId)
	local handle = buildHandle(def)
	handle.Parent = tool

	-- A magic staff gets a glowing orb welded to its top.
	if def.type == "weapon" and def.weaponType == "ranged" then
		local orb = Instance.new("Part")
		orb.Name = "Orb"
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(0.9, 0.9, 0.9)
		orb.Color = Color3.fromRGB(150, 90, 255)
		orb.Material = Enum.Material.Neon
		orb.CanCollide = false
		orb.Massless = true
		orb.CFrame = handle.CFrame * CFrame.new(0, handle.Size.Y / 2, 0)

		local light = Instance.new("PointLight")
		light.Color = orb.Color
		light.Range = 8
		light.Brightness = 2
		light.Parent = orb

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = orb
		weld.Parent = orb
		orb.Parent = tool
	end

	tool.Activated:Connect(function()
		playSwing(player)
		local handler = ToolService.activatedHandlers[def.type]
		if handler then
			handler(player, tool, def)
		end
	end)

	return tool
end

local function heldTools(player)
	local tools = {}
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") then
				table.insert(tools, child)
			end
		end
	end
	if player.Character then
		for _, child in ipairs(player.Character:GetChildren()) do
			if child:IsA("Tool") then
				table.insert(tools, child)
			end
		end
	end
	return tools
end

-- Reconcile the player's Tools with the equippable items in their inventory.
function ToolService.syncTools(player)
	local profile = PlayerService.get(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not profile or not backpack then
		return
	end

	local desired = {}
	for _, entry in ipairs(profile.inventory) do
		local def = Items.get(entry.itemId)
		if def and EQUIPPABLE[def.type] then
			desired[entry.itemId] = true
		end
	end

	-- Drop tools that are no longer wanted; note which desired ones we already have.
	local have = {}
	for _, tool in ipairs(heldTools(player)) do
		local itemId = tool:GetAttribute("itemId")
		if desired[itemId] and not have[itemId] then
			have[itemId] = true
		else
			tool:Destroy()
		end
	end

	-- Create any missing tools.
	for itemId in pairs(desired) do
		if not have[itemId] then
			buildTool(player, itemId).Parent = backpack
		end
	end
end

function ToolService.start()
	-- Rebuild tools whenever the inventory changes (equippable items gained/lost).
	PlayerService.onInventoryChanged(function(player)
		ToolService.syncTools(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			-- Backpack is recreated on every (re)spawn; wait for it then sync.
			local backpack = player:WaitForChild("Backpack", 5)
			if backpack then
				ToolService.syncTools(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player.UserId] = nil
	end)
end

return ToolService
