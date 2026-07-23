-- Dynamic Weather & Environmental Water Service.
-- Manages weather cycles (Clear, Rain, Fog, Thunderstorm), extinguishes unroofed campfires during rain,
-- applies the "Wet" status to players in water or rain, and syncs atmosphere with clients.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local CampService = require(script.Parent.CampService)

local WeatherService = {}

local WEATHER_TYPES = { "clear", "rain", "fog", "thunderstorm" }
local currentGlobalWeather = "clear"

function WeatherService.getWeather()
	return currentGlobalWeather
end

local function applyWeather(weather)
	currentGlobalWeather = weather
	Workspace:SetAttribute("Weather", weather)
	Remotes.get("WeatherChanged"):FireAllClients(weather)

	-- Rain extinguishes exposed campfires
	if weather == "rain" or weather == "thunderstorm" then
		task.spawn(function()
			CampService.extinguishExposedCampfires()
		end)
	end
end

function WeatherService.setWeather(weather)
	if table.find(WEATHER_TYPES, weather) then
		applyWeather(weather)
		return true
	end
	return false
end

function WeatherService.start()
	local weatherChangedRemote = Remotes.get("WeatherChanged")
	local setWeatherRemote = Remotes.getFunction("SetWeather")

	setWeatherRemote.OnServerInvoke = function(player, weather)
		if typeof(weather) == "string" then
			return WeatherService.setWeather(weather)
		end
		return false
	end

	applyWeather("clear")

	-- Weather cycle loop (changes every 240s)
	task.spawn(function()
		while true do
			task.wait(240)
			local idx = math.random(1, #WEATHER_TYPES)
			applyWeather(WEATHER_TYPES[idx])
		end
	end)

	-- Player Water / Wet detection loop
	task.spawn(function()
		while true do
			task.wait(0.5)
			local isRaining = (currentGlobalWeather == "rain" or currentGlobalWeather == "thunderstorm")
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local root = character and character:FindFirstChild("HumanoidRootPart")

				local inWater = false
				if humanoid and root then
					if humanoid.FloorMaterial == Enum.Material.Water or humanoid:GetState() == Enum.HumanoidStateType.Swimming then
						inWater = true
					end
				end

				local isWet = inWater or isRaining
				player:SetAttribute("Wet", isWet)
				if character then
					character:SetAttribute("Wet", isWet)
				end
			end
		end
	end)

	-- Chat command handler: /clima <despejado|lluvia|niebla|tormenta> or /weather <clear|rain|fog|thunderstorm>
	local MAP = {
		despejado = "clear",
		clear = "clear",
		sol = "clear",
		lluvia = "rain",
		rain = "rain",
		niebla = "fog",
		fog = "fog",
		tormenta = "thunderstorm",
		thunderstorm = "thunderstorm",
	}

	local function onPlayerChatted(player, msg)
		local args = string.split(string.lower(msg), " ")
		if args[1] == "/clima" or args[1] == "/weather" then
			local target = args[2] and MAP[args[2]]
			if target then
				WeatherService.setWeather(target)
				Remotes.get("Notify"):FireClient(player, "Clima cambiado a: " .. target)
			else
				Remotes.get("Notify"):FireClient(player, "Uso: /clima <despejado|lluvia|niebla|tormenta>")
			end
		end
	end

	for _, p in ipairs(Players:GetPlayers()) do
		p.Chatted:Connect(function(msg)
			onPlayerChatted(p, msg)
		end)
	end
	Players.PlayerAdded:Connect(function(p)
		p.Chatted:Connect(function(msg)
			onPlayerChatted(p, msg)
		end)
	end)
end

return WeatherService
