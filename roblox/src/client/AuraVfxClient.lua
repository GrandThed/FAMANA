-- Cliente que gestiona Auras Visuales (partículas, luces y efectos animados)
-- en los personajes cuando están bajo efectos/buffs activos (atributos Effect_<id>).
-- Se aplica al jugador local y a todos los demás jugadores visibles.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Effects = require(Shared:WaitForChild("Effects"))

local AuraVfxClient = {}

-- Configuración estética de auras por id de efecto (ver shared/Effects.lua)
local AURA_DEFS = {
	frenzy = {
		color = Color3.fromRGB(255, 40, 40),
		secondaryColor = Color3.fromRGB(180, 0, 0),
		rate = 25,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) }),
		speed = NumberRange.new(2, 5),
		lightColor = Color3.fromRGB(255, 50, 50),
		lightRange = 10,
	},
	battle_cry = {
		color = Color3.fromRGB(230, 80, 50),
		rate = 18,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 0.2) }),
		speed = NumberRange.new(3, 6),
	},
	bulwark = {
		color = Color3.fromRGB(90, 150, 255),
		secondaryColor = Color3.fromRGB(200, 230, 255),
		rate = 20,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0.1) }),
		speed = NumberRange.new(1, 3),
		lightColor = Color3.fromRGB(100, 160, 255),
		lightRange = 8,
	},
	steel_loyalty = {
		color = Color3.fromRGB(140, 170, 230),
		rate = 15,
		speed = NumberRange.new(1, 3),
	},
	on_guard = {
		color = Color3.fromRGB(120, 160, 210),
		rate = 12,
		speed = NumberRange.new(1, 2),
	},
	defensive_stance = {
		color = Color3.fromRGB(150, 160, 190),
		rate = 10,
		speed = NumberRange.new(1, 2),
	},
	swift_step = {
		color = Color3.fromRGB(90, 240, 255),
		rate = 22,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) }),
		speed = NumberRange.new(4, 8),
		lightColor = Color3.fromRGB(90, 240, 255),
		lightRange = 6,
	},
	sprint = {
		color = Color3.fromRGB(80, 220, 230),
		rate = 20,
		speed = NumberRange.new(4, 7),
	},
	overcharge = {
		color = Color3.fromRGB(180, 110, 255),
		secondaryColor = Color3.fromRGB(255, 150, 255),
		rate = 25,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.0), NumberSequenceKeypoint.new(1, 0.1) }),
		speed = NumberRange.new(2, 5),
		lightColor = Color3.fromRGB(180, 110, 255),
		lightRange = 9,
	},
	sacred_circle = {
		color = Color3.fromRGB(255, 235, 150),
		rate = 20,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) }),
		speed = NumberRange.new(1.5, 4),
		lightColor = Color3.fromRGB(255, 235, 150),
		lightRange = 10,
	},
	sanctuary = {
		color = Color3.fromRGB(255, 245, 200),
		secondaryColor = Color3.fromRGB(255, 255, 255),
		rate = 30,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.8), NumberSequenceKeypoint.new(1, 0) }),
		speed = NumberRange.new(2, 5),
		lightColor = Color3.fromRGB(255, 245, 200),
		lightRange = 12,
	},
	minor_blessing = {
		color = Color3.fromRGB(255, 220, 160),
		rate = 12,
		speed = NumberRange.new(1, 3),
	},
	legion = {
		color = Color3.fromRGB(120, 230, 180),
		rate = 20,
		speed = NumberRange.new(2, 4),
		lightColor = Color3.fromRGB(120, 230, 180),
		lightRange = 8,
	},
}

-- Mapa de auras activas: [character] = { [effectId] = FolderInstance }
local activeAuras = {}

local function removeAura(character, effectId)
	if not activeAuras[character] then
		return
	end
	local folder = activeAuras[character][effectId]
	if folder then
		folder:Destroy()
		activeAuras[character][effectId] = nil
	end
end

local function applyAura(character, effectId)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	removeAura(character, effectId)

	local auraDef = AURA_DEFS[effectId]
	if not auraDef then
		-- Si no hay def explícita pero existe la def de shared/Effects, usaremos sus colores por defecto
		local effDef = Effects.defs[effectId]
		if not effDef or not effDef.color then
			return
		end
		auraDef = {
			color = effDef.color,
			rate = 14,
			speed = NumberRange.new(1.5, 3.5),
		}
	end

	if not activeAuras[character] then
		activeAuras[character] = {}
	end

	local auraFolder = Instance.new("Folder")
	auraFolder.Name = "Aura_" .. effectId

	local attachment = Instance.new("Attachment")
	attachment.Name = "AuraAttachment"
	attachment.Position = Vector3.new(0, -1, 0)
	attachment.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "AuraEmitter"
	emitter.Color = ColorSequence.new(auraDef.color, auraDef.secondaryColor or auraDef.color)
	emitter.Size = auraDef.size or NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.0), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Rate = auraDef.rate or 15
	emitter.Speed = auraDef.speed or NumberRange.new(2, 4)
	emitter.VelocitySpread = 45
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Parent = attachment

	if auraDef.lightColor then
		local light = Instance.new("PointLight")
		light.Name = "AuraLight"
		light.Color = auraDef.lightColor
		light.Range = auraDef.lightRange or 8
		light.Brightness = 2
		light.Parent = root
		light.Parent = auraFolder
	end

	auraFolder.Parent = character
	activeAuras[character][effectId] = auraFolder
end

local function updatePlayerAuras(player)
	if not player then
		return
	end
	local character = player.Character
	if not character then
		return
	end

	local now = Workspace:GetServerTimeNow()

	for effectId, _ in pairs(Effects.defs) do
		local attrName = Effects.attributePrefix .. effectId
		local expiry = player:GetAttribute(attrName)
		if expiry and typeof(expiry) == "number" and expiry > now then
			applyAura(character, effectId)
		else
			removeAura(character, effectId)
		end
	end
end

local function trackPlayer(player)
	player.AttributeChanged:Connect(function(attrName)
		if string.sub(attrName, 1, #Effects.attributePrefix) == Effects.attributePrefix then
			updatePlayerAuras(player)
		end
	end)

	player.CharacterAdded:Connect(function(char)
		activeAuras[char] = nil
		task.delay(0.5, function()
			updatePlayerAuras(player)
		end)
	end)

	if player.Character then
		updatePlayerAuras(player)
	end
end

function AuraVfxClient.start()
	for _, player in ipairs(Players:GetPlayers()) do
		trackPlayer(player)
	end

	Players.PlayerAdded:Connect(trackPlayer)
	Players.PlayerRemoving:Connect(function(player)
		if player.Character then
			activeAuras[player.Character] = nil
		end
	end)

	-- Timer periódico de limpieza por expiración
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				updatePlayerAuras(player)
			end
		end
	end)
end

return AuraVfxClient
