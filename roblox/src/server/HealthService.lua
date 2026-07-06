-- HP: restores saved health + position on spawn, out-of-combat regen, and
-- death -> respawn. Reads the profile from PlayerService.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Classes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Classes"))
local PlayerService = require(script.Parent.PlayerService)

local HealthService = {}

-- [userId] = os.clock() of last damage, for gating regen.
local lastDamage = {}

-- Called by the combat system (step 5) whenever a player takes damage.
function HealthService.registerDamage(player)
	lastDamage[player.UserId] = os.clock()
end

-- registerMaxHealthMult: fn(player) -> multiplier on max HP (Brawler trait).
local maxHealthMultHooks = {}
function HealthService.registerMaxHealthMult(fn)
	table.insert(maxHealthMultHooks, fn)
end

-- registerBonusRegen: fn(player) -> extra HP per SECOND, applied even in
-- combat (unlike the base out-of-combat regen) — the Brawler trickle.
local bonusRegenHooks = {}
function HealthService.registerBonusRegen(fn)
	table.insert(bonusRegenHooks, fn)
end

local function hookedMaxHealthMult(player)
	local mult = 1
	for _, fn in ipairs(maxHealthMultHooks) do
		local ok, value = pcall(fn, player)
		if ok and typeof(value) == "number" then
			mult *= value
		end
	end
	return mult
end

local function hookedBonusRegen(player)
	local rate = 0
	for _, fn in ipairs(bonusRegenHooks) do
		local ok, value = pcall(fn, player)
		if ok and typeof(value) == "number" then
			rate += value
		end
	end
	return rate
end

local function maxHealthFor(player)
	local profile = PlayerService.get(player)
	-- Base max HP scaled by the player's current class (see shared/Classes)
	-- and any registered multipliers (Brawler trait).
	local classDef = Classes.get(profile and profile.currentClass)
	return math.floor(Config.HP.max * classDef.hpMult * hookedMaxHealthMult(player) + 0.5)
end

-- Re-derives MaxHealth mid-life (equipment/trait changes). Current HP stays
-- absolute — more max is headroom, less max clamps.
function HealthService.refreshMaxHealth(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local maxHealth = maxHealthFor(player)
	if humanoid.MaxHealth ~= maxHealth then
		humanoid.MaxHealth = maxHealth
		humanoid.Health = math.min(humanoid.Health, maxHealth)
	end
end

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	local profile = PlayerService.get(player)

	local maxHealth = maxHealthFor(player)
	humanoid.MaxHealth = maxHealth

	-- Restore saved HP; a dead-saved value or missing value comes back full.
	local savedHealth = (profile and profile.health) or maxHealth
	if savedHealth <= 0 then
		savedHealth = maxHealth
	end
	humanoid.Health = math.clamp(savedHealth, 1, maxHealth)

	-- Restore saved position within this cell (skip the default origin).
	if profile and profile.position then
		local p = profile.position
		if not (p.x == 0 and p.y == 0 and p.z == 0) then
			local root = character:WaitForChild("HumanoidRootPart")
			root.CFrame = CFrame.new(p.x, p.y, p.z)
		end
	end

	humanoid.Died:Connect(function()
		if profile then
			profile.health = humanoid.MaxHealth -- respawn at full (current max)
		end
		task.wait(Config.HP.respawnDelay)
		if player.Parent then
			player:LoadCharacter()
		end
	end)
end

function HealthService.start()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		-- Handle a character that somehow already exists.
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastDamage[player.UserId] = nil
	end)

	-- Out-of-combat regen tick.
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Config.HP.regenInterval then
			return
		end
		accumulator = 0

		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
				-- Trait regen (Brawler) trickles even in combat; the base
				-- regen still waits for the out-of-combat delay.
				local heal = hookedBonusRegen(player) * Config.HP.regenInterval
				local last = lastDamage[player.UserId] or 0
				if os.clock() - last >= Config.HP.regenDelay then
					heal += Config.HP.regenAmount
				end
				if heal > 0 then
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + heal)
				end
			end
		end
	end)
end

return HealthService
