-- Sonido de swing de arma/herramienta, distinto según el tipo (melee/
-- ranged/magic/tool). server/ToolService.lua ya dispara SwingRemote por
-- cada golpe válido (con su propio debounce de 0.4s ahí adentro —
-- SWING_COOLDOWN — así que este sonido ya viene naturalmente limitado sin
-- que tengamos que throttlear nada acá).
--
-- El daño en sí (dealDamage en EnemyService) todavía NO tiene ese mismo
-- límite — se puede spamear el click y pegar de más — así que el sonido de
-- IMPACTO (hit/critHit) vive en DamageIndicatorUI con Sfx.playThrottled en
-- vez de Sfx.play, como parche de audio hasta que exista un cooldown real
-- de combate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Sfx = require(script.Parent.Sfx)

local CombatSfx = {}

-- styleName llega de ToolService.swingStyleFor: "slash" (espadas melee sin
-- combo resuelto), "combo1"/"combo2"/"combo3" (los 3 golpes del combo melee,
-- ver EnemyService's resolveWeaponVariant), "draw" (arcos), "cast"
-- (varitas/staffs mágicos) o "chop" (herramientas, hacha/pico). Los combos
-- reusan el mismo sonido de espada (swingMelee) — el remate (combo3) solo
-- suena un toque más grave via PITCH_BY_STYLE, para que se sienta más
-- pesado sin necesitar un asset de sonido nuevo.
local SOUND_BY_STYLE = {
	slash = "swingMelee",
	combo1 = "swingMelee",
	combo2 = "swingMelee",
	combo3 = "swingMelee",
	draw = "swingRanged",
	cast = "swingMagic",
	chop = "swing",
}

local PITCH_BY_STYLE = {
	combo3 = 0.88, -- remate: mismo sonido, un poco más grave/pesado
}

-- lootSource llega de EnemyService (enemy.def.lootSource) — el mismo id que
-- ya usan para drops y objetivos de quest "kill", así que cualquier
-- enemigo nuevo que agreguen ya trae su lootSource de fábrica sin tocar
-- este archivo; solo hace falta sumarle una entrada acá (y su sonido en
-- Sfx.lua) para que deje de sonar con el fallback genérico.
local DEATH_SOUND_BY_LOOT_SOURCE = {
	slime = "slimeDeath",
	goblin = "goblinDeath",
}

function CombatSfx.start()
	Remotes.get("SwingRemote").OnClientEvent:Connect(function(styleName)
		Sfx.play(SOUND_BY_STYLE[styleName] or "swing", PITCH_BY_STYLE[styleName])
	end)

	Remotes.get("EnemyDied").OnClientEvent:Connect(function(lootSource)
		Sfx.play(DEATH_SOUND_BY_LOOT_SOURCE[lootSource] or "enemyDeath")
	end)
end

return CombatSfx