-- Fishing & Sunken Treasure Service.
-- Handles fishing casts, bite notifications, catch calculations, and opening sunken treasure chests.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Items = require(Shared:WaitForChild("Items"))
local PlayerService = require(script.Parent.PlayerService)
local ToolService = require(script.Parent.ToolService)

local FishingService = {}

local activeFishing = {} -- [userId] = { token, position }

local function notify(player, text)
	Remotes.get("Notify"):FireClient(player, text)
end

function FishingService.start()
	local castRodRemote = Remotes.get("CastFishingRod")
	local biteAlertRemote = Remotes.get("FishingBiteAlert")
	local startFishingRemote = Remotes.getFunction("StartFishing")
	local catchFishRemote = Remotes.getFunction("CatchFish")

	-- Register cana_pescar tool activation handler
	ToolService.registerActivated("tool", function(player, tool, def)
		if def.toolType ~= "fishing_rod" then
			return
		end
		-- Fire client to start fishing cast
		Remotes.get("CastFishingRod"):FireClient(player)
	end)

	startFishingRemote.OnServerInvoke = function(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return { ok = false }
		end

		local token = (activeFishing[player.UserId] and activeFishing[player.UserId].token or 0) + 1
		activeFishing[player.UserId] = { token = token, position = root.Position }

		-- Wait 2.5s for a bite
		task.delay(2.5, function()
			local current = activeFishing[player.UserId]
			if current and current.token == token then
				biteAlertRemote:FireClient(player, { token = token })
			end
		end)

		return { ok = true }
	end

	catchFishRemote.OnServerInvoke = function(player, payload)
		local current = activeFishing[player.UserId]
		if not current then
			return { ok = false }
		end
		activeFishing[player.UserId] = nil

		-- Roll catch table
		local roll = math.random(1, 100)
		local catchItemId = "pez_dorado"
		if roll <= 45 then
			catchItemId = "pez_dorado"
		elseif roll <= 75 then
			catchItemId = "trucha_plateada"
		elseif roll <= 90 then
			catchItemId = "pez_sombra"
		else
			catchItemId = "cofre_hundido"
		end

		PlayerService.addItem(player, catchItemId, 1, true)
		local itemDef = Items.get(catchItemId)
		notify(player, string.format("¡Pescaste: %s!", itemDef and itemDef.name or catchItemId))

		return { ok = true, itemId = catchItemId }
	end
end

return FishingService
