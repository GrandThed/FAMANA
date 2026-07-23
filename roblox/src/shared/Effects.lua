-- Shared buff/debuff definitions. The server's EffectService applies these
-- (gameplay side) and replicates each active effect to its owner as a Player
-- attribute `Effect_<id>` holding the expiry time on the server clock
-- (Workspace:GetServerTimeNow()), so the client can render icons + countdowns
-- with no remotes. Effects are live-only (not persisted), like mana.

local Effects = {}

Effects.attributePrefix = "Effect_"

-- Gameplay fields an effect may carry (EffectService aggregates them across
-- everything active — multipliers multiply together):
--   walkSpeedMult    — movement speed multiplier
--   damageMults      — { melee?, physical?, magic? } outgoing damage multipliers
--   damageTakenMult  — incoming damage multiplier (< 1 = tankier)
Effects.defs = {
	slow = {
		id = "slow",
		name = "Slowed",
		kind = "debuff",
		duration = 4, -- seconds; reapplying refreshes the timer
		walkSpeedMult = 0.5,
		color = Color3.fromRGB(80, 200, 120), -- slime green: reads as its source
	},

	-- ---- innate ability buffs (see Spells.innates) ---------------------------
	defensive_stance = {
		id = "defensive_stance",
		name = "Defensive Stance",
		kind = "buff",
		duration = 6,
		damageTakenMult = 0.6,
		damageMults = { melee = 0.7, physical = 0.7, magic = 0.7 },
		color = Color3.fromRGB(150, 160, 190),
	},
	overcharge = {
		id = "overcharge",
		name = "Overcharge",
		kind = "buff",
		duration = 8,
		damageMults = { magic = 1.25 },
		color = Color3.fromRGB(150, 130, 220),
	},
	swift_step = {
		id = "swift_step",
		name = "Swift Step",
		kind = "buff",
		duration = 2,
		walkSpeedMult = 1.2,
		color = Color3.fromRGB(90, 210, 230),
	},
	minor_blessing = {
		id = "minor_blessing",
		name = "Minor Blessing",
		kind = "buff",
		duration = 5,
		damageTakenMult = 0.85,
		color = Color3.fromRGB(255, 235, 170),
	},
	-- Zone auras (SpellService's allyZone behavior refreshes these every tick
	-- while an ally stands inside the circle; stepping out lets them lapse).
	sacred_circle = {
		id = "sacred_circle",
		name = "Sacred Circle",
		kind = "buff",
		duration = 2,
		damageTakenMult = 0.85,
		color = Color3.fromRGB(255, 235, 170),
	},
	sanctuary = {
		id = "sanctuary",
		name = "Sanctuary",
		kind = "buff",
		duration = 1,
		damageTakenMult = 0, -- inside the circle nothing hurts at all
		color = Color3.fromRGB(255, 245, 200),
	},
	-- Primed-capstone markers: no gameplay fields — the HUD icon is the whole
	-- point. SpellService clears them early once the charge is consumed.
	double_nock = {
		id = "double_nock",
		name = "Double Nock",
		kind = "buff",
		duration = 10,
		color = Color3.fromRGB(90, 200, 90),
	},
	overflow = {
		id = "overflow",
		name = "Overflow",
		kind = "buff",
		duration = 10,
		color = Color3.fromRGB(120, 170, 255),
	},

	-- ---- spell buffs (see shared/Spells.lua) --------------------------------
	battle_cry = {
		id = "battle_cry",
		name = "Battle Cry",
		kind = "buff",
		duration = 10,
		damageMults = { melee = 1.25, physical = 1.25 },
		color = Color3.fromRGB(220, 80, 60),
	},
	frenzy = {
		id = "frenzy",
		name = "Frenzy",
		kind = "buff",
		duration = 8,
		damageMults = { melee = 1.5, physical = 1.35 },
		walkSpeedMult = 1.2,
		color = Color3.fromRGB(170, 30, 30),
	},
	on_guard = {
		id = "on_guard",
		name = "On Guard",
		kind = "buff",
		duration = 6,
		damageTakenMult = 0.85,
		color = Color3.fromRGB(120, 150, 200),
	},
	steel_loyalty = {
		id = "steel_loyalty",
		name = "Steel Loyalty",
		kind = "buff",
		duration = 10,
		damageTakenMult = 0.7,
		color = Color3.fromRGB(150, 170, 210),
	},
	bulwark = {
		id = "bulwark",
		name = "Bulwark",
		kind = "buff",
		duration = 6,
		damageTakenMult = 0.5,
		color = Color3.fromRGB(90, 120, 190),
	},
	sprint = {
		id = "sprint",
		name = "Sprint",
		kind = "buff",
		duration = 6,
		walkSpeedMult = 1.35,
		color = Color3.fromRGB(90, 210, 230),
	},

	-- ---- apex spell buffs (school 30-point ultimates) --------------------------
	legion = {
		id = "legion",
		name = "Legion",
		kind = "buff",
		duration = 10, -- HUD mirror of the familiar-empower window
		color = Color3.fromRGB(120, 220, 180),
	},
	bloodbath = {
		id = "bloodbath",
		name = "Bloodbath",
		kind = "buff",
		duration = 8, -- the kill window itself: SpellService checks isActive
		color = Color3.fromRGB(170, 30, 30),
	},
	crusade = {
		id = "crusade",
		name = "Crusade",
		kind = "buff",
		duration = 8, -- ally side: lifesteal via SpellService's hook
		color = Color3.fromRGB(230, 190, 90),
	},
	crusade_leader = {
		id = "crusade_leader",
		name = "Crusade (Leader)",
		kind = "buff",
		duration = 8, -- caster side: same lifesteal + the damage surge
		damageMults = { melee = 1.25, physical = 1.25, magic = 1.25 },
		color = Color3.fromRGB(230, 190, 90),
	},
	prophecy = {
		id = "prophecy",
		name = "Prophecy",
		kind = "buff",
		duration = 3, -- HUD mirror of HealthService's undying window
		color = Color3.fromRGB(140, 210, 220),
	},

	-- ---- camp (server/RestedService.lua) --------------------------------------
	-- No aplica por EffectService.apply: RestedService escribe el attribute
	-- directo, porque su expiry NO es un timer fijo — crece mientras el
	-- jugador descansa en zona segura de noche (hasta Config.Camp.rested.
	-- chargeCapSeconds) y después cuenta regresiva sola al alejarse/salir el
	-- sol. `duration` acá es ese tope, así el panel de efectos puede armar
	-- la barra de progreso (remaining / duration) igual que con cualquier
	-- otro buff, sin necesitar un caso especial.
	rested = {
		id = "rested",
		name = "Descansado",
		kind = "buff",
		duration = 20 * 60, -- debe matchear Config.Camp.rested.chargeCapSeconds
		color = Color3.fromRGB(255, 195, 120), -- luz de fogata
	},
}

function Effects.get(effectId)
	return Effects.defs[effectId]
end

-- The attribute name an active effect replicates under.
function Effects.attributeFor(effectId)
	return Effects.attributePrefix .. effectId
end

-- Reverse of attributeFor: effect id from an attribute name, or nil.
function Effects.idFromAttribute(attributeName)
	if attributeName:sub(1, #Effects.attributePrefix) == Effects.attributePrefix then
		return attributeName:sub(#Effects.attributePrefix + 1)
	end
	return nil
end

-- "12m 34s" sobre el minuto, "8s" por debajo — todos los buffs de combate
-- son cortos (≤10s) así que esto no cambia nada para ellos, pero Rested
-- puede llegar a 20 minutos y "1200s" no se lee. Un solo lugar para el
-- formato así HudUI e InventoryUI (los dos paneles de efectos) no
-- divergen.
function Effects.formatRemaining(seconds)
	seconds = math.max(0, seconds)
	if seconds >= 60 then
		return string.format("%dm %02ds", math.floor(seconds / 60), math.floor(seconds % 60))
	end
	return string.format("%.0fs", seconds)
end

return Effects
