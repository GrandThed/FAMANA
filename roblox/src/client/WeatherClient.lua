-- Dynamic Weather Client.
-- Controls atmosphere, realistic streak rain particles, fog, and rain sound effects.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer

local WeatherClient = {}

local rainEmitterPart, rainParticle
local rainSound

local function setupRainEmitter()
	local part = Instance.new("Part")
	part.Name = "RainEmitterPart"
	part.Size = Vector3.new(100, 1, 100)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Parent = Workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "RainDrops"
	emitter.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
	emitter.Size = NumberSequence.new(0.25, 0.25)
	emitter.Transparency = NumberSequence.new(0.05, 0.3)
	emitter.Lifetime = NumberRange.new(0.4, 0.7)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(20, 30)
	emitter.Acceleration = Vector3.new(0, -250, 0)
	emitter.LightEmission = 0.4
	emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.SpreadAngle = Vector2.new(5, 5)
	emitter.Parent = part

	local sound = Instance.new("Sound")
	sound.Name = "RainSound"
	sound.SoundId = "rbxassetid://140237752767800" -- Rain ambient loop
	sound.Looped = true
	sound.Volume = 0.5
	sound.Parent = part

	rainEmitterPart = part
	rainParticle = emitter
	rainSound = sound
end

local function applyVisualWeather(weather)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if weather == "rain" or weather == "thunderstorm" then
		Lighting.FogStart = 10
		Lighting.FogEnd = 350
		Lighting.FogColor = Color3.fromRGB(120, 135, 150)
		if atmosphere then
			atmosphere.Density = 0.45
		end
		if rainParticle then
			rainParticle.Rate = weather == "thunderstorm" and 900 or 500
		end
		if rainSound and not rainSound.IsPlaying then
			rainSound:Play()
		end
	elseif weather == "fog" then
		Lighting.FogStart = 0
		Lighting.FogEnd = 120
		Lighting.FogColor = Color3.fromRGB(160, 170, 180)
		if atmosphere then
			atmosphere.Density = 0.75
		end
		if rainParticle then
			rainParticle.Rate = 0
		end
		if rainSound and rainSound.IsPlaying then
			rainSound:Stop()
		end
	else
		Lighting.FogStart = 50
		Lighting.FogEnd = 1500
		Lighting.FogColor = Color3.fromRGB(200, 210, 220)
		if atmosphere then
			atmosphere.Density = 0.25
		end
		if rainParticle then
			rainParticle.Rate = 0
		end
		if rainSound and rainSound.IsPlaying then
			rainSound:Stop()
		end
	end
end

function WeatherClient.start()
	setupRainEmitter()

	local weatherRemote = Remotes.get("WeatherChanged")
	weatherRemote.OnClientEvent:Connect(function(weather)
		applyVisualWeather(weather)
	end)

	local initial = Workspace:GetAttribute("Weather") or "clear"
	applyVisualWeather(initial)

	-- Follow player position for rain particles and sound
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and rainEmitterPart then
			rainEmitterPart.CFrame = CFrame.new(root.Position + Vector3.new(0, 30, 0))

			-- Roof check: raycast straight up from player position to see if under a roof/building
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { character, rainEmitterPart }

			local currentGlobalWeather = Workspace:GetAttribute("Weather") or "clear"
			local isRainingWeather = (currentGlobalWeather == "rain" or currentGlobalWeather == "thunderstorm")

			local rayResult = Workspace:Raycast(root.Position, Vector3.new(0, 60, 0), params)
			local isUnderRoof = rayResult ~= nil

			-- Dynamic Indoor Fog & Atmosphere Culling
			local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
			if isUnderRoof then
				Lighting.FogStart = 45
				Lighting.FogEnd = 220
				if atmosphere then
					atmosphere.Density = 0.12
				end
			else
				-- Restore outdoor fog based on current weather
				if currentGlobalWeather == "fog" then
					Lighting.FogStart = 0
					Lighting.FogEnd = 120
					if atmosphere then
						atmosphere.Density = 0.75
					end
				elseif isRainingWeather then
					Lighting.FogStart = 10
					Lighting.FogEnd = 350
					if atmosphere then
						atmosphere.Density = 0.45
					end
				else
					Lighting.FogStart = 50
					Lighting.FogEnd = 1500
					if atmosphere then
						atmosphere.Density = 0.25
					end
				end
			end

			if isRainingWeather and rainParticle then
				if isUnderRoof then
					rainParticle.Rate = 0
					if rainSound then
						rainSound.Volume = 0.1
					end
				else
					rainParticle.Rate = currentGlobalWeather == "thunderstorm" and 900 or 500
					if rainSound then
						rainSound.Volume = 0.5
					end
				end
			end
		end
	end)
end

return WeatherClient
