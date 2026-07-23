-- Cliente que maneja audio 3D posicional y agitación de cámara (Screen Shake)
-- para impactos y explosiones de hechizos en el mundo.
-- El servidor emite `SpellVfxEvent(data)` con posición, sonido y tipo de efecto.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Sfx = require(script.Parent.Sfx)

local SpellVfxClient = {}

local camera = Workspace.CurrentCamera

-- Agita levemente la cámara si la posición del impacto está dentro de `radius` studs del jugador local.
local function triggerScreenShake(position, intensity, radius)
	local localPlayer = Players.LocalPlayer
	if not localPlayer or not localPlayer.Character then
		return
	end

	local root = localPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local dist = (root.Position - position).Magnitude
	local maxRadius = radius or 45
	if dist > maxRadius then
		return
	end

	-- Multiplicador decreciente según la distancia
	local factor = 1 - (dist / maxRadius)
	local actualIntensity = (intensity or 0.4) * factor

	task.spawn(function()
		local startTime = os.clock()
		local duration = 0.3
		while os.clock() - startTime < duration do
			local dt = RunService.RenderStepped:Wait()
			local remaining = 1 - ((os.clock() - startTime) / duration)
			local currentScale = actualIntensity * remaining
			local offset = Vector3.new(
				(math.random() - 0.5) * currentScale,
				(math.random() - 0.5) * currentScale,
				(math.random() - 0.5) * currentScale
			)
			camera.CFrame = camera.CFrame * CFrame.Angles(
				math.rad(offset.X * 5),
				math.rad(offset.Y * 5),
				math.rad(offset.Z * 5)
			)
		end
	end)
end

function SpellVfxClient.start()
	local remote = Remotes.get("SpellVfxEvent")
	remote.OnClientEvent:Connect(function(data)
		if typeof(data) ~= "table" or not data.position then
			return
		end

		if data.soundName then
			Sfx.play(data.soundName)
		end

		if data.shakeIntensity and data.shakeIntensity > 0 then
			triggerScreenShake(data.position, data.shakeIntensity, data.shakeRadius)
		end
	end)
end

return SpellVfxClient
