-- Live buffs/debuffs (not persisted, like mana). Applies the gameplay side
-- (currently walkspeed multipliers) and replicates each active effect to its
-- owner as a Player attribute `Effect_<id>` holding the expiry time on the
-- server clock — the client's effects panel renders icons/countdowns from
-- those attributes with no remotes (see shared/Effects.lua).
--
-- First real effect: slimes inflict `slow` on melee hit.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Effects = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Effects"))
local EnemyService = require(script.Parent.EnemyService)

local EffectService = {}

local BASE_WALKSPEED = 16
local EXPIRE_TICK = 0.25 -- seconds between expiry sweeps

-- [userId] = { [effectId] = expiresAt (server clock) }
local active = {}

local function walkSpeedMult(userId)
	local effects = active[userId]
	local mult = 1
	if effects then
		for effectId in pairs(effects) do
			local def = Effects.get(effectId)
			if def and def.walkSpeedMult then
				mult *= def.walkSpeedMult
			end
		end
	end
	return mult
end

local function applyWalkSpeed(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = BASE_WALKSPEED * walkSpeedMult(player.UserId)
	end
end

-- Applies (or refreshes) an effect on the player.
function EffectService.apply(player, effectId)
	local def = Effects.get(effectId)
	if not def then
		warn("[EffectService] unknown effect: " .. tostring(effectId))
		return
	end
	local effects = active[player.UserId]
	if not effects then
		effects = {}
		active[player.UserId] = effects
	end
	local expiresAt = Workspace:GetServerTimeNow() + def.duration
	effects[effectId] = expiresAt
	player:SetAttribute(Effects.attributeFor(effectId), expiresAt)
	applyWalkSpeed(player)
end

local function sweepExpired()
	local now = Workspace:GetServerTimeNow()
	for userId, effects in pairs(active) do
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			active[userId] = nil
			continue
		end
		local changed = false
		for effectId, expiresAt in pairs(effects) do
			if now >= expiresAt then
				effects[effectId] = nil
				player:SetAttribute(Effects.attributeFor(effectId), nil)
				changed = true
			end
		end
		if changed then
			applyWalkSpeed(player)
		end
	end
end

function EffectService.start()
	-- Slimes inflict the slowness debuff on melee hit.
	EnemyService.onPlayerHit(function(lootSource, player)
		if lootSource == "slime" then
			EffectService.apply(player, "slow")
		end
	end)

	-- Respawning resets WalkSpeed; reapply active effects to the new character.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid then
				humanoid.WalkSpeed = BASE_WALKSPEED * walkSpeedMult(player.UserId)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		active[player.UserId] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(EXPIRE_TICK)
			sweepExpired()
		end
	end)
end

return EffectService
