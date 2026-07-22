-- Fishing Service.
-- Flujo: el jugador activa la caña -> el cliente le muestra un apuntador y
-- una barra de potencia (cargar y soltar) -> el server valida que el punto
-- de caída sea AGUA de verdad (Terrain/parts con Enum.Material.Water, o
-- cualquier instancia con el tag "WaterZone") -> espera un tiempo random ->
-- avisa el pique -> el jugador tiene una ventana corta para enganchar ->
-- arranca un minijuego de barra (estilo Stardew Valley) que el server
-- simula de forma autoritativa a 20Hz y el cliente sólo dibuja.
--
-- CÓMO MARCAR AGUA EN EL MAPA:
--   1) Lo más simple: cualquier part o terreno pintado con el material
--      "Water" de Studio ya funciona automáticamente, no hace falta tocar
--      nada más.
--   2) Si tenés una laguna/río hecho con parts que por estética NO usan el
--      material Water (ej. un plano semi-transparente con un shader), agregale
--      el tag "WaterZone" con CollectionService (Studio: pestaña "Tags", o
--      `game:GetService("CollectionService"):AddTag(part, "WaterZone")`).
--      El tag también puede ir en el Model contenedor de toda la laguna.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Items = require(Shared:WaitForChild("Items"))
local FishingConfig = require(Shared:WaitForChild("FishingConfig"))
local PlayerService = require(script.Parent.PlayerService)
local ToolService = require(script.Parent.ToolService)

local FishingService = {}

local WATER_TAG = "WaterZone"

-- [userId] = { token, stage, castPosition, fish, minigame }
-- stage: "waiting_bite" | "hooking" | "minigame"
local sessions = {}

local function notify(player, text)
	Remotes.get("Notify"):FireClient(player, text)
end

local function getCharacterRoot(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

-- Tira un rayo hacia abajo desde `position` y devuelve true + el punto de
-- impacto si lo que encuentra es agua de verdad (material Water, o algo
-- etiquetado "WaterZone"). Esto es lo único que decide si se puede pescar
-- ahí, así que corre siempre en el server.
local function isWaterAt(position, excludeInstance)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludeInstance and { excludeInstance } or {}
	params.IgnoreWater = false -- Roblox ignora el agua de Terrain por defecto; la necesitamos

	local origin = Vector3.new(position.X, position.Y + FishingConfig.Cast.waterRayHeight, position.Z)
	local direction = Vector3.new(0, -FishingConfig.Cast.waterRayDepth, 0)
	local result = Workspace:Raycast(origin, direction, params)
	if not result then
		return false
	end

	if result.Material == Enum.Material.Water then
		return true, result.Position
	end

	local inst = result.Instance
	if inst and CollectionService:HasTag(inst, WATER_TAG) then
		return true, result.Position
	end

	local ancestorModel = inst and inst:FindFirstAncestorWhichIsA("Model")
	if ancestorModel and CollectionService:HasTag(ancestorModel, WATER_TAG) then
		return true, result.Position
	end

	return false
end

local lastFishingEnd = {} -- [userId] = timestamp of last session end

local function endSession(userId)
	if sessions[userId] then
		lastFishingEnd[userId] = os.clock()
	end
	sessions[userId] = nil
end

-- Un paso de física del minijuego: mueve al pez con un "random walk" hacia
-- objetivos nuevos (más errático cuanto más difícil es el pez), aplica
-- gravedad/impulso a la barra del jugador, y actualiza el progreso según si
-- se solapan o no.
local function stepMinigame(mg, dt)
	local now = os.clock()
	if now >= mg.fishNextChange then
		mg.fishTarget = math.clamp(0.05 + math.random() * 0.9, 0, 1)
		mg.fishNextChange = now
			+ mg.params.fishDirChangeMin
			+ math.random() * (mg.params.fishDirChangeMax - mg.params.fishDirChangeMin)
	end
	local diff = mg.fishTarget - mg.fishPos
	local step = mg.params.fishSpeed * dt
	if math.abs(diff) <= step then
		mg.fishPos = mg.fishTarget
	else
		mg.fishPos += (diff > 0 and step or -step)
	end

	local mgc = FishingConfig.Minigame
	if mg.holding then
		mg.barVel += mgc.holdAccel * dt
	else
		mg.barVel -= mgc.gravity * dt
	end
	mg.barVel = math.clamp(mg.barVel, -mgc.maxBarSpeed, mgc.maxBarSpeed)
	mg.barPos = math.clamp(mg.barPos + mg.barVel * dt, 0, 1)
	if mg.barPos <= 0 or mg.barPos >= 1 then
		mg.barVel = 0
	end

	local barHalf = mg.params.barSize / 2
	local fishHalf = mg.params.fishSize / 2
	local overlap = (mg.barPos - barHalf) <= (mg.fishPos + fishHalf)
		and (mg.barPos + barHalf) >= (mg.fishPos - fishHalf)

	if overlap then
		mg.progress = math.clamp(mg.progress + mgc.progressGainRate * dt, 0, 1)
	else
		mg.progress = math.clamp(mg.progress - mgc.progressLossRate * dt, 0, 1)
	end
end

local function finishMinigame(player, session, success)
	local fish = session.fish
	local token = session.token
	endSession(player.UserId)

	if success then
		PlayerService.addItem(player, fish.itemId, 1, true)
		local itemDef = Items.get(fish.itemId)
		local name = itemDef and itemDef.name or fish.itemId
		notify(player, string.format("¡Pescaste: %s!", name))
		Remotes.get("FishingMinigameEnd"):FireClient(player, {
			token = token,
			success = true,
			itemId = fish.itemId,
			itemName = name,
		})
	else
		notify(player, "El pez se soltó del anzuelo...")
		Remotes.get("FishingMinigameEnd"):FireClient(player, { token = token, success = false })
	end
end

local function startMinigameLoop(player, token)
	local mgc = FishingConfig.Minigame
	local startTime = os.clock()
	local lastTick = startTime

	task.spawn(function()
		while true do
			task.wait(mgc.tickRate)

			local session = sessions[player.UserId]
			if not session or session.token ~= token or session.stage ~= "minigame" then
				return
			end

			local now = os.clock()
			local dt = now - lastTick
			lastTick = now

			stepMinigame(session.minigame, dt)

			Remotes.get("FishingMinigameTick"):FireClient(player, {
				token = token,
				fishPos = session.minigame.fishPos,
				barPos = session.minigame.barPos,
				progress = session.minigame.progress,
			})

			if session.minigame.progress >= 1 then
				finishMinigame(player, session, true)
				return
			elseif session.minigame.progress <= 0 or (now - startTime) >= mgc.timeout then
				finishMinigame(player, session, false)
				return
			end
		end
	end)
end

function FishingService.start()
	local castRodRemote = Remotes.get("CastFishingRod")
	local biteAlertRemote = Remotes.get("FishingBiteAlert")
	local requestCastRemote = Remotes.get("RequestCast")
	local castFailedRemote = Remotes.get("FishingCastFailed")
	local requestHookRemote = Remotes.get("RequestHook")
	local minigameStartRemote = Remotes.get("FishingMinigameStart")
	local reelInputRemote = Remotes.get("FishingReelInput")

	-- Registrar el handler de activación de la caña (mismo patrón que el resto
	-- de las tools: ToolService despacha por def.type == "tool" y acá filtramos
	-- por toolType). Si ya hay una sesión de pesca en curso (cargando, esperando
	-- pique, enganchando o en el minijuego), ignoramos la activación: el mismo
	-- click de "mantener para remar" del minijuego también dispara Activated
	-- porque la caña sigue equipada, y sin este guard eso reabría el flujo de
	-- lanzamiento por encima de una sesión que ya está corriendo.
	ToolService.registerActivated("tool", function(player, tool, def)
		if def.toolType ~= "fishing_rod" then
			return
		end
		if sessions[player.UserId] then
			return
		end
		local cd = FishingConfig.Cast.cooldownAfterFish or 1.2
		if os.clock() - (lastFishingEnd[player.UserId] or 0) < cd then
			return
		end
		castRodRemote:FireClient(player)
	end)

	-- El cliente soltó el click de carga: nos manda potencia (0-1) y el punto
	-- del mundo al que apuntó. Acá se valida TODO: que tenga la caña puesta,
	-- que el punto esté dentro del rango permitido por la potencia, y sobre
	-- todo que sea agua real.
	requestCastRemote.OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end

		local root = getCharacterRoot(player)
		if not root then
			return
		end

		local heldId = ToolService.getHeldItemId and ToolService.getHeldItemId(player)
		if heldId ~= "cana_pescar" then
			return
		end

		-- Ya hay una sesión corriendo (esperando pique, enganchando o en el
		-- minijuego): ignoramos este pedido en vez de pisarla. Sin esto, un
		-- click perdido durante el minijuego (ver el guard en Activated más
		-- arriba) podría matar en silencio la sesión activa sin avisarle al
		-- cliente, dejando su UI vieja congelada en pantalla.
		local existing = sessions[player.UserId]
		if existing and existing.stage ~= "waiting_bite" then
			return
		end

		local token = ((sessions[player.UserId] and sessions[player.UserId].token) or 0) + 1
		endSession(player.UserId)

		local power = math.clamp(tonumber(payload.power) or 0, 0, 1)
		local cast = FishingConfig.Cast
		local maxDist = cast.minDistance + power * (cast.maxDistance - cast.minDistance)

		local targetPos
		if typeof(payload.target) == "Vector3" then
			local toTarget = payload.target - root.Position
			local dist = toTarget.Magnitude
			if dist > maxDist + 4 and dist > 0 then
				-- No confiamos ciegamente en el punto del cliente: si pidió más
				-- distancia de la que su potencia permite, lo recortamos.
				targetPos = root.Position + toTarget.Unit * maxDist
			else
				targetPos = payload.target
			end
		else
			targetPos = root.Position + root.CFrame.LookVector * cast.minDistance
		end

		local water, hitPos = isWaterAt(targetPos, player.Character)
		if not water then
			castFailedRemote:FireClient(player, { reason = "no_water" })
			notify(player, "Ahí no hay agua para pescar.")
			return
		end

		sessions[player.UserId] = { token = token, stage = "waiting_bite", castPosition = hitPos }

		local bite = FishingConfig.Bite
		local waitTime = bite.waitMin + math.random() * (bite.waitMax - bite.waitMin)

		task.delay(waitTime, function()
			local session = sessions[player.UserId]
			if not session or session.token ~= token or session.stage ~= "waiting_bite" then
				return
			end
			session.stage = "hooking"
			biteAlertRemote:FireClient(player, { token = token })

			task.delay(bite.hookWindow, function()
				local s = sessions[player.UserId]
				if s and s.token == token and s.stage == "hooking" then
					endSession(player.UserId)
					notify(player, "¡Se escapó! Había que enganchar más rápido.")
				end
			end)
		end)
	end)

	-- El jugador reaccionó al "¡Pique!" dentro de la ventana: se sortea el
	-- pez y arranca el minijuego de barra.
	requestHookRemote.OnServerEvent:Connect(function(player, payload)
		local session = sessions[player.UserId]
		if not session or session.stage ~= "hooking" then
			return
		end
		if typeof(payload) == "table" and payload.token and payload.token ~= session.token then
			return
		end

		local fish = FishingConfig.rollFish()
		local params = FishingConfig.deriveMinigameParams(fish.difficulty)

		session.stage = "minigame"
		session.fish = fish
		session.minigame = {
			fishPos = 0.2 + math.random() * 0.6,
			fishTarget = 0.2 + math.random() * 0.6,
			fishNextChange = os.clock(),
			barPos = 0.5,
			barVel = 0,
			progress = FishingConfig.Minigame.progressStart,
			holding = false,
			params = params,
		}

		local itemDef = Items.get(fish.itemId)
		minigameStartRemote:FireClient(player, {
			token = session.token,
			itemId = fish.itemId,
			itemName = itemDef and itemDef.name or fish.itemId,
			barSize = params.barSize,
			fishSize = params.fishSize,
		})

		startMinigameLoop(player, session.token)
	end)

	-- El cliente manda el estado de "mantener apretado" del minijuego cada vez
	-- que cambia (no todos los frames), así que el server sólo guarda el
	-- último valor y lo usa en su propia simulación a 20Hz.
	reelInputRemote.OnServerEvent:Connect(function(player, holding)
		local session = sessions[player.UserId]
		if session and session.stage == "minigame" and session.minigame then
			session.minigame.holding = holding == true
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		endSession(player.UserId)
	end)
end

return FishingService