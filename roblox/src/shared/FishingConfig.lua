-- Sintonía de la mecánica de pesca (lanzamiento cargado + minijuego de barra
-- al estilo Stardew Valley). Todo lo que sea "un número que se puede tunear"
-- vive acá para no tener que tocar FishingService.lua ni FishingUI.lua.

local FishingConfig = {}

-- ---- lanzamiento --------------------------------------------------------------
FishingConfig.Cast = {
	chargeTime = 1.1, -- segundos manteniendo click para llegar a potencia máxima
	minDistance = 8, -- studs mínimos desde el jugador
	maxDistance = 55, -- studs máximos (a potencia 1.0)
	waterRayHeight = 30, -- altura desde la que se tira el rayo hacia abajo para detectar agua
	waterRayDepth = 60,
	cooldownAfterFish = 1.2, -- tiempo de espera tras terminar una pesca antes de poder castear de nuevo
}

-- ---- espera del pique -----------------------------------------------------------
FishingConfig.Bite = {
	waitMin = 1.5,
	waitMax = 5.5,
	hookWindow = 1.2, -- segundos para reaccionar al "¡Pique!" antes de que se escape
}

-- ---- minijuego (barra del jugador vs. pez) ---------------------------------------
FishingConfig.Minigame = {
	tickRate = 1 / 20, -- 20 Hz de simulación autoritativa en el server
	timeout = 16, -- segundos máximos antes de que el pez se escape solo (fail-safe)
	gravity = 1.15, -- aceleración hacia abajo de la barra cuando no se mantiene input
	holdAccel = 2.7, -- aceleración hacia arriba mientras se mantiene el input
	maxBarSpeed = 1.5,
	progressGainRate = 0.55, -- progreso ganado por segundo mientras la barra cubre al pez
	progressLossRate = 0.35, -- progreso perdido por segundo mientras no lo cubre
	progressStart = 0.5,
}

-- ---- catálogo de peces --------------------------------------------------------
-- difficulty 0-100 (misma escala conceptual que Stardew): a mayor dificultad,
-- el pez se mueve más rápido/errático y tanto su hitbox como la barra del
-- jugador se achican.
FishingConfig.Fish = {
	{ itemId = "pez_dorado", weight = 45, difficulty = 15 },
	{ itemId = "trucha_plateada", weight = 30, difficulty = 40 },
	{ itemId = "pez_sombra", weight = 15, difficulty = 65 },
	{ itemId = "cofre_hundido", weight = 10, difficulty = 80 },
}

function FishingConfig.rollFish()
	local totalWeight = 0
	for _, fish in ipairs(FishingConfig.Fish) do
		totalWeight += fish.weight
	end
	local roll = math.random() * totalWeight
	local acc = 0
	for _, fish in ipairs(FishingConfig.Fish) do
		acc += fish.weight
		if roll <= acc then
			return fish
		end
	end
	return FishingConfig.Fish[1]
end

-- Deriva tamaños de barra/pez y velocidad errática a partir de la dificultad.
-- Se usa tanto en el server (simulación autoritativa) como en el cliente
-- (para saber qué tan grandes dibujar la barra y el ícono del pez).
function FishingConfig.deriveMinigameParams(difficulty)
	local t = math.clamp(difficulty, 0, 100) / 100
	return {
		barSize = 0.30 - 0.13 * t, -- 0.30 (fácil) -> 0.17 (difícil)
		fishSize = 0.12 - 0.05 * t, -- 0.12 -> 0.07
		fishSpeed = 0.30 + 0.85 * t, -- unidades normalizadas (0-1) por segundo
		fishDirChangeMin = 0.75 - 0.45 * t,
		fishDirChangeMax = 1.3 - 0.6 * t,
	}
end

return FishingConfig