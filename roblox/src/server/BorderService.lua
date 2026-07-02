-- Border handoff between grid cells. Creates a trigger wall on each edge that
-- has a neighbor; crossing it saves the player and teleports them to the
-- neighboring Place, where they arrive at the opposite edge.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GridConfig = require(Shared:WaitForChild("GridConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local PlayerService = require(script.Parent.PlayerService)

local BorderService = {}

local TELEPORT_ATTEMPTS = 3
local FADE_LEAD = 0.35 -- seconds to let the screen fade to black before teleporting

local borderFolder
local teleportingRemote -- RemoteEvent: tell client to fade to black
local cancelledRemote -- RemoteEvent: tell client to fade back in (teleport failed)
local teleporting = {} -- [userId] = true while a handoff is in flight

local function playerFromHit(hit)
	local character = hit.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return Players:GetPlayerFromCharacter(character)
	end
	return nil
end

local function handoff(player, destCell, entryEdge)
	local destPlaceId = GridConfig.placeIdOf(destCell)
	if destPlaceId == 0 then
		warn(
			"[BorderService] Cell '" .. destCell .. "' has no placeId set in GridConfig — "
				.. "publish it and fill in the id. Skipping teleport."
		)
		teleporting[player.UserId] = nil
		return
	end

	-- Persist current HP/position so the destination loads fresh state.
	-- (Inventory already writes through on every change.)
	PlayerService.save(player)

	-- Fade the player's screen to black to hide the load, then teleport.
	teleportingRemote:FireClient(player)
	task.wait(FADE_LEAD)

	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({ entryEdge = entryEdge })

	local success = false
	for attempt = 1, TELEPORT_ATTEMPTS do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(destPlaceId, { player }, options)
		end)
		if ok then
			success = true
			break
		end
		-- TeleportService doesn't work in Studio, and can fail transiently live.
		warn(
			"[BorderService] Teleport to '" .. destCell .. "' attempt " .. attempt .. " failed: " .. tostring(err)
		)
		task.wait(1)
	end

	if not success then
		-- Recover: fade the screen back in and let them keep playing here.
		cancelledRemote:FireClient(player)
		teleporting[player.UserId] = nil
	end
end

local function createBorder(edge, destCell)
	local wall = Instance.new("Part")
	wall.Name = "Border_" .. edge
	wall.Anchored = true
	wall.CanCollide = false
	wall.Size = Vector3.new(2, 30, 90)
	wall.Position = Vector3.new(GridConfig.borderX(edge), 15, 0)
	wall.Color = Color3.fromRGB(80, 140, 255)
	wall.Transparency = 0.6
	wall.Material = Enum.Material.ForceField
	wall.Parent = borderFolder

	local entryEdge = GridConfig.oppositeEdge(edge)
	wall.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		if player and not teleporting[player.UserId] then
			teleporting[player.UserId] = true
			handoff(player, destCell, entryEdge)
		end
	end)
end

function BorderService.start()
	teleportingRemote = Remotes.get("Teleporting")
	cancelledRemote = Remotes.get("TeleportCancelled")

	borderFolder = Instance.new("Folder")
	borderFolder.Name = "Borders"
	borderFolder.Parent = Workspace

	local cellId = GridConfig.currentCell()
	for edge, destCell in pairs(GridConfig.neighbors(cellId)) do
		createBorder(edge, destCell)
	end

	Players.PlayerRemoving:Connect(function(player)
		teleporting[player.UserId] = nil
	end)
end

return BorderService
