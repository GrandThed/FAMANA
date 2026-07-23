-- "Rested" — the reworked version of camp coziness (docs/CAMP_TIERS.md §3).
--
-- Used to grant extra HP regen scaled by decoration, straight from
-- CampFurnitureService. Reworked because HP regen already has too many
-- hands in the pot (Cleric's Devotion passive, Brawler's synergy bonus, the
-- generic `regen` trait stat — all feed the same
-- HealthService.registerBonusRegen hook), so a decoration-scaled regen
-- bonus mostly rewarded whoever already stacked regen the hardest, not
-- "did you bother decorating your camp."
--
-- New shape: while a player stands in a safe camp zone at night, they bank
-- rest time (faster the cozier that camp is — see
-- CampFurnitureService.cozinessRatio). Leaving the zone (or day breaking)
-- doesn't drain the bank instantly — restedUntil just stops being extended,
-- so it counts down in real time on its own. While restedUntil hasn't
-- passed yet, GatheringService's yield-bonus hook (registered below) grants
-- a flat bonus, same mechanism as the night gathering bonus.
--
-- This is the real choice the player makes: park it at a cozy camp all
-- night banking a long Rested buff, or go fight the (tougher, night-
-- boosted) mobs / gather the (better-yielding) nodes right now instead.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Effects = require(Shared:WaitForChild("Effects"))

local CampService = require(script.Parent.CampService)
local CampFurnitureService = require(script.Parent.CampFurnitureService)
local DayNightService = require(script.Parent.DayNightService)

local RestedService = {}

local RESTED = Config.Camp.rested
local REST_ATTRIBUTE = Effects.attributeFor("rested")

-- [userId] = timestamp (Workspace:GetServerTimeNow()) the Rested buff
-- expires at. Absent/past means not resting. In-memory only, same as the
-- rest of camp state — a server restart just means you're not Rested
-- anymore, no big loss.
--
-- Usa el reloj SINCRONIZADO server/cliente (GetServerTimeNow, no os.clock())
-- porque este mismo valor se publica como el attribute Effect_rested
-- (shared/Effects.lua) para que el HUD/panel de personaje dibujen el ícono
-- y la barra de progreso sin remotos — mismo mecanismo que EffectService.
local restedUntil = {}

-- Recomputing this every frame for every player is pointless — resting is a
-- multi-minute action, a slow tick is imperceptible and cheap.
local TICK_INTERVAL = 1

function RestedService.isRested(player)
	local until_ = restedUntil[player.UserId]
	return until_ ~= nil and Workspace:GetServerTimeNow() < until_
end

local function tick(dt)
	local night = DayNightService.isNight()

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if night and root and CampService.isPositionSafeForPlayer(player, root.Position) then
			local camp = CampService.campFor(player)
			if camp then
				local coziness = CampFurnitureService.cozinessRatio(camp.ownerUserId)
				local accrualRate = RESTED.baseAccrualPerSecond * (1 + coziness * (RESTED.accrualMultAtMaxCoziness - 1))

				local now = Workspace:GetServerTimeNow()
				local current = math.max(restedUntil[player.UserId] or now, now)
				local cap = now + RESTED.chargeCapSeconds
				local until_ = math.min(current + dt * accrualRate, cap)
				restedUntil[player.UserId] = until_
				player:SetAttribute(REST_ATTRIBUTE, until_)
			end
		end
		-- Not resting right now (out of the zone, or it's day): just don't
		-- extend restedUntil. It keeps counting down toward "not Rested"
		-- entirely on its own — nothing to do here. The attribute already
		-- holds the same expiry, so the HUD's own countdown/fill-bar drains
		-- it live without another write from us; the effects panel simply
		-- stops showing it once GetServerTimeNow() passes that value (same
		-- rule EffectService's own buffs use — see shared/Effects.lua).
	end
end

function RestedService.start()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < TICK_INTERVAL then
			return
		end
		local elapsed = accumulator
		accumulator = 0
		tick(elapsed)
	end)

	Players.PlayerRemoving:Connect(function(player)
		restedUntil[player.UserId] = nil
	end)
end

return RestedService
