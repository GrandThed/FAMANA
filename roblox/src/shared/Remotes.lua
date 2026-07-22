-- Remote factory usable from both sides:
--   server: creates the instance if missing (under ReplicatedStorage/Remotes)
--   client: waits for it to replicate
-- Keeps client and server referring to the same objects by name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Remotes = {}

local folder

local function getInstance(name, className)
	if RunService:IsServer() then
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing
		end
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
		return remote
	else
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing
		end
		return folder:WaitForChild(name, 60)
	end
end

if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end

	-- Pre-create common remotes on server load to prevent client replication warnings
	local PRECREATE_EVENTS = {
		"Notify",
		"OpenMarket",
		"OpenCooking",
		"OpenGuildBank",
		"OpenChest",
		"CastFishingRod",
		"FishingBiteAlert",
		"RequestCast",
		"FishingCastFailed",
		"RequestHook",
		"FishingMinigameStart",
		"FishingMinigameTick",
		"FishingMinigameEnd",
		"FishingReelInput",
		"WeatherChanged",
		"InventoryUpdated",
		"SpellsChanged",
		"SpellFeedback",
		"SpellVfxEvent",
		"OpenGuildResearch",
		"ToggleSleeping",
		"ToggleSitting",
	}
	local PRECREATE_FUNCTIONS = {
		"GetMarketListings",
		"CreateMarketListing",
		"BuyMarketItem",
		"CookRecipe",
		"RequestInventory",
		"RequestGuildBank",
		"SetWeather",
		"ConsumeItem",
		"ClaimGuildPlot",
		"GetGuildPlots",
		"GetGuildResearch",
		"ContributeGuildResearch",
		"PlaceStructure",
		"DemolishStructure",
	}
	for _, name in ipairs(PRECREATE_EVENTS) do
		getInstance(name, "RemoteEvent")
	end
	for _, name in ipairs(PRECREATE_FUNCTIONS) do
		getInstance(name, "RemoteFunction")
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

function Remotes.get(name)
	return getInstance(name, "RemoteEvent")
end

function Remotes.getFunction(name)
	return getInstance(name, "RemoteFunction")
end

-- Server-only: fires `name` to every player whose character is within
-- `radius` studs of `position`, instead of a single player. Used for "world"
-- SFX (weapon swings, hits, enemy deaths) so everyone standing nearby hears
-- them too, not just whoever caused it — see Config.CombatSfxHearRadius.
function Remotes.fireNearby(name, position, radius, ...)
	assert(RunService:IsServer(), "Remotes.fireNearby is server-only")
	local remote = Remotes.get(name)
	for _, plr in ipairs(Players:GetPlayers()) do
		local character = plr.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - position).Magnitude <= radius then
			remote:FireClient(plr, ...)
		end
	end
end

return Remotes