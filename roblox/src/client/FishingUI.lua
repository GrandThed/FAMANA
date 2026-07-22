-- Fishing UI (Minijuego de Pesca, estilo Stardew Valley).
-- 1) Apuntar + cargar potencia (mantener click, soltar para lanzar).
-- 2) Esperar el pique.
-- 3) Enganchar a tiempo (ESPACIO/click).
-- 4) Minijuego de barra: mantené ESPACIO/click para subir la barra y
--    mantenerla sobre el pez mientras sube el progreso. El server simula
--    todo esto de forma autoritativa; acá sólo dibujamos lo que manda.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local FishingConfig = require(Shared:WaitForChild("FishingConfig"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local WATER_TAG = "WaterZone"
local HOOK_KEYS = { [Enum.KeyCode.Space] = true }
local HOOK_INPUTS = { [Enum.UserInputType.MouseButton1] = true }

local FishingUI = {}

-- Sólo para feedback visual mientras se apunta (verde/rojo). La validación
-- real y autoritativa vive en el server (FishingService.isWaterAt).
local function isWaterAtClient(position)
	local params = RaycastParams.new()
	local character = player.Character
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = character and { character } or {}
	params.IgnoreWater = false

	local origin = Vector3.new(position.X, position.Y + FishingConfig.Cast.waterRayHeight, position.Z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -FishingConfig.Cast.waterRayDepth, 0), params)
	if not result then
		return false, nil
	end
	local isWater = result.Material == Enum.Material.Water
		or CollectionService:HasTag(result.Instance, WATER_TAG)
		or (result.Instance:FindFirstAncestorWhichIsA("Model") ~= nil
			and CollectionService:HasTag(result.Instance:FindFirstAncestorWhichIsA("Model"), WATER_TAG))
	return isWater, result.Position
end

-- Raycast desde la cámara a través de la posición del mouse, contra
-- workspace (terreno/parts), para saber dónde caería el anzuelo.
local function mouseWorldPoint()
	local mouseLoc = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLoc.X, mouseLoc.Y)

	local params = RaycastParams.new()
	local character = player.Character
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = character and { character } or {}
	params.IgnoreWater = false

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if result then
		return result.Position
	end
	return ray.Origin + ray.Direction * 60
end

function FishingUI.start()
	local castRodRemote = Remotes.get("CastFishingRod")
	local biteAlertRemote = Remotes.get("FishingBiteAlert")
	local requestCastRemote = Remotes.get("RequestCast")
	local castFailedRemote = Remotes.get("FishingCastFailed")
	local requestHookRemote = Remotes.get("RequestHook")
	local minigameStartRemote = Remotes.get("FishingMinigameStart")
	local minigameTickRemote = Remotes.get("FishingMinigameTick")
	local minigameEndRemote = Remotes.get("FishingMinigameEnd")
	local reelInputRemote = Remotes.get("FishingReelInput")

	local gui = Instance.new("ScreenGui")
	gui.Name = "FishingUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Forward-declaradas acá arriba (y asignadas más abajo, no con `local
	-- function`) para que beginAiming() pueda llamarlas como red de
	-- seguridad aunque estén definidas más adelante en el archivo.
	local resetBite
	local closeMinigame

	--------------------------------------------------------------------------
	-- Apuntado + carga de potencia
	--------------------------------------------------------------------------
	local aimFrame = Instance.new("Frame")
	aimFrame.Size = UDim2.new(0, 320, 0, 90)
	aimFrame.Position = UDim2.new(0.5, 0, 0.85, 0)
	aimFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	aimFrame.Visible = false
	aimFrame.Parent = gui
	UIKit.stylePanel(aimFrame)
	UIKit.addShadow(aimFrame)
	UIKit.autoScale(aimFrame)

	local aimHint = UIKit.label(aimFrame, "Apuntá al agua y mantené click para cargar", 13, Theme.Semantic.TextBody)
	aimHint.Size = UDim2.new(1, -20, 0, 20)
	aimHint.Position = UDim2.new(0, 10, 0, 8)
	aimHint.TextXAlignment = Enum.TextXAlignment.Center

	local powerTrack = Instance.new("Frame")
	powerTrack.Size = UDim2.new(1, -24, 0, 16)
	powerTrack.Position = UDim2.new(0, 12, 0, 40)
	powerTrack.BackgroundColor3 = Theme.Semantic.SurfaceWell
	powerTrack.BorderSizePixel = 0
	powerTrack.Parent = aimFrame
	local powerStroke = Instance.new("UIStroke")
	powerStroke.Thickness = 1
	powerStroke.Color = Theme.Semantic.BorderPanel
	powerStroke.Parent = powerTrack

	local powerFill = Instance.new("Frame")
	powerFill.Size = UDim2.new(0, 0, 1, 0)
	powerFill.BackgroundColor3 = Theme.Semantic.Accent
	powerFill.BorderSizePixel = 0
	powerFill.Parent = powerTrack

	local waterStatusLabel = UIKit.label(aimFrame, "", 12, Theme.Semantic.Bad, Theme.Font.BodyBold)
	waterStatusLabel.Size = UDim2.new(1, -20, 0, 18)
	waterStatusLabel.Position = UDim2.new(0, 10, 0, 62)
	waterStatusLabel.TextXAlignment = Enum.TextXAlignment.Center

	local waitingLabel = UIKit.label(gui, "🎣 Esperando el pique...", 14, Theme.Semantic.TextSecondary, Theme.Font.BodyBold)
	waitingLabel.Size = UDim2.new(0, 300, 0, 24)
	waitingLabel.Position = UDim2.new(0.5, 0, 0.78, 0)
	waitingLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	waitingLabel.TextXAlignment = Enum.TextXAlignment.Center
	waitingLabel.Visible = false

	local aiming = false
	local charging = false
	local chargeStart = 0
	local aimConn = nil
	local aimInputConn = nil
	local aimInputConn2 = nil

	local function stopAiming()
		aiming = false
		charging = false
		aimFrame.Visible = false
		if aimConn then
			aimConn:Disconnect()
			aimConn = nil
		end
		if aimInputConn then
			aimInputConn:Disconnect()
			aimInputConn = nil
		end
		if aimInputConn2 then
			aimInputConn2:Disconnect()
			aimInputConn2 = nil
		end
	end

	local function beginAiming()
		-- Red de seguridad: si por lo que sea quedó algo abierto de una sesión
		-- anterior (minijuego o prompt de pique), lo cerramos antes de arrancar
		-- una nueva. El fix real es que el server ya no reabre este flujo
		-- mientras hay una sesión activa, pero esto cubre cualquier otro borde.
		if closeMinigame then
			closeMinigame()
		end
		if resetBite then
			resetBite()
		end

		aiming = true
		charging = false
		aimFrame.Visible = true
		powerFill.Size = UDim2.new(0, 0, 1, 0)
		waterStatusLabel.Text = ""

		if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			charging = true
			chargeStart = os.clock()
		end

		aimConn = RunService.RenderStepped:Connect(function()
			local point = mouseWorldPoint()
			local water = isWaterAtClient(point)
			waterStatusLabel.Text = water and "✓ Hay agua ahí" or "✗ Ahí no hay agua"
			waterStatusLabel.TextColor3 = water and Theme.Semantic.Good or Theme.Semantic.Bad

			if charging then
				local power = math.clamp((os.clock() - chargeStart) / FishingConfig.Cast.chargeTime, 0, 1)
				powerFill.Size = UDim2.new(power, 0, 1, 0)
			end
		end)

		aimInputConn = UserInputService.InputBegan:Connect(function(input, gpe)
			if gpe or not aiming then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				charging = true
				chargeStart = os.clock()
			elseif input.KeyCode == Enum.KeyCode.Escape then
				stopAiming()
			end
		end)

		aimInputConn2 = UserInputService.InputEnded:Connect(function(input, gpe)
			if not aiming or not charging then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				local power = math.clamp((os.clock() - chargeStart) / FishingConfig.Cast.chargeTime, 0, 1)
				local point = mouseWorldPoint()
				Sfx.play("uiClick")
				requestCastRemote:FireServer({ power = power, target = point })
				stopAiming()
				waitingLabel.Visible = true
			end
		end)
	end

	local cooldownUntil = 0

	castRodRemote.OnClientEvent:Connect(function()
		waitingLabel.Visible = false
		local cd = FishingConfig.Cast.cooldownAfterFish or 1.2
		if os.clock() < cooldownUntil then
			return
		end
		beginAiming()
	end)

	castFailedRemote.OnClientEvent:Connect(function()
		waitingLabel.Visible = false
	end)

	--------------------------------------------------------------------------
	-- Ventana de pique ("¡PIQUE! Presiona ESPACIO")
	--------------------------------------------------------------------------
	local biteFrame = Instance.new("Frame")
	biteFrame.Size = UDim2.new(0, 260, 0, 70)
	biteFrame.Position = UDim2.new(0.5, 0, 0.75, 0)
	biteFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	biteFrame.Visible = false
	biteFrame.Parent = gui
	UIKit.stylePanel(biteFrame)
	UIKit.addShadow(biteFrame)

	local biteTitle = UIKit.label(biteFrame, "¡PIQUE! Presiona ESPACIO", 14, Theme.Semantic.Currency, Theme.Font.DisplayBold)
	biteTitle.Size = UDim2.new(1, 0, 0, 30)
	biteTitle.Position = UDim2.new(0, 0, 0, 10)
	biteTitle.TextXAlignment = Enum.TextXAlignment.Center

	local biteToken = nil
	local biteConn = nil

	function resetBite()
		cooldownUntil = os.clock() + (FishingConfig.Cast.cooldownAfterFish or 1.2)
		biteFrame.Visible = false
		biteToken = nil
		if biteConn then
			biteConn:Disconnect()
			biteConn = nil
		end
	end

	biteAlertRemote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		closeMinigame()
		waitingLabel.Visible = false
		biteToken = payload.token
		biteFrame.Visible = true
		Sfx.play("xpDing")

		biteConn = UserInputService.InputBegan:Connect(function(input, gpe)
			if gpe then
				return
			end
			if HOOK_KEYS[input.KeyCode] or HOOK_INPUTS[input.UserInputType] then
				if biteToken then
					requestHookRemote:FireServer({ token = biteToken })
					resetBite()
				end
			end
		end)

		task.delay(FishingConfig.Bite.hookWindow, function()
			if biteFrame.Visible then
				resetBite()
			end
		end)
	end)

	--------------------------------------------------------------------------
	-- Minijuego de barra vs. pez
	--------------------------------------------------------------------------
	local mgFrame = Instance.new("Frame")
	mgFrame.Size = UDim2.new(0, 220, 0, 340)
	mgFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	mgFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	mgFrame.Visible = false
	mgFrame.Parent = gui
	UIKit.stylePanel(mgFrame)
	UIKit.addShadow(mgFrame)
	UIKit.autoScale(mgFrame)

	local mgTitle = UIKit.label(mgFrame, "¡Algo picó!", 15, Theme.Semantic.TextTitle, Theme.Font.DisplayBold)
	mgTitle.Size = UDim2.new(1, -20, 0, 24)
	mgTitle.Position = UDim2.new(0, 10, 0, 8)
	mgTitle.TextXAlignment = Enum.TextXAlignment.Center

	local mgHint = UIKit.label(mgFrame, "Mantené ESPACIO / click para subir", 11, Theme.Semantic.TextMuted)
	mgHint.Size = UDim2.new(1, -20, 0, 16)
	mgHint.Position = UDim2.new(0, 10, 0, 32)
	mgHint.TextXAlignment = Enum.TextXAlignment.Center

	-- Track vertical: contiene el ícono del pez y la barra del jugador.
	local track = Instance.new("Frame")
	track.Size = UDim2.new(0, 60, 0, 220)
	track.Position = UDim2.new(0, 20, 0, 58)
	track.BackgroundColor3 = Theme.Semantic.SurfaceWell
	track.BorderSizePixel = 0
	track.Parent = mgFrame
	local trackStroke = Instance.new("UIStroke")
	trackStroke.Thickness = 1
	trackStroke.Color = Theme.Semantic.BorderPanel
	trackStroke.Parent = track

	local fishIcon = Instance.new("Frame")
	fishIcon.Size = UDim2.new(1, -8, 0, 20)
	fishIcon.Position = UDim2.new(0, 4, 0.5, 0)
	fishIcon.AnchorPoint = Vector2.new(0, 0.5)
	fishIcon.BackgroundColor3 = Theme.Semantic.Danger
	fishIcon.BorderSizePixel = 0
	fishIcon.ZIndex = 2
	fishIcon.Parent = track

	local catchBar = Instance.new("Frame")
	catchBar.Size = UDim2.new(1, 0, 0, 60)
	catchBar.Position = UDim2.new(0, 0, 0.5, 0)
	catchBar.AnchorPoint = Vector2.new(0, 0.5)
	catchBar.BackgroundColor3 = Theme.Semantic.Good
	catchBar.BackgroundTransparency = 0.45
	catchBar.BorderSizePixel = 0
	catchBar.ZIndex = 1
	catchBar.Parent = track

	-- Barra de progreso al costado del track.
	local progressTrack = Instance.new("Frame")
	progressTrack.Size = UDim2.new(0, 16, 0, 220)
	progressTrack.Position = UDim2.new(0, 90, 0, 58)
	progressTrack.BackgroundColor3 = Theme.Semantic.SurfaceWell
	progressTrack.BorderSizePixel = 0
	progressTrack.Parent = mgFrame
	local progressStroke = Instance.new("UIStroke")
	progressStroke.Thickness = 1
	progressStroke.Color = Theme.Semantic.BorderPanel
	progressStroke.Parent = progressTrack

	local progressFill = Instance.new("Frame")
	progressFill.Size = UDim2.new(1, 0, 0.5, 0)
	progressFill.Position = UDim2.new(0, 0, 1, 0)
	progressFill.AnchorPoint = Vector2.new(0, 1)
	progressFill.BackgroundColor3 = Theme.Semantic.Accent
	progressFill.BorderSizePixel = 0
	progressFill.Parent = progressTrack

	local resultLabel = UIKit.label(mgFrame, "", 13, Theme.Semantic.TextStrong, Theme.Font.BodyBold)
	resultLabel.Size = UDim2.new(1, -20, 0, 40)
	resultLabel.Position = UDim2.new(0, 10, 1, -48)
	resultLabel.TextXAlignment = Enum.TextXAlignment.Center
	resultLabel.TextWrapped = true
	resultLabel.Visible = false

	local mgToken = nil
	local mgHolding = false
	local mgInputConn = nil
	local mgInputConn2 = nil

	local function setHolding(value)
		if mgHolding == value then
			return
		end
		mgHolding = value
		reelInputRemote:FireServer(value)
	end

	function closeMinigame()
		mgFrame.Visible = false
		mgToken = nil
		setHolding(false)
		if mgInputConn then
			mgInputConn:Disconnect()
			mgInputConn = nil
		end
		if mgInputConn2 then
			mgInputConn2:Disconnect()
			mgInputConn2 = nil
		end
	end

	local function updateTrackFromNormalized(frame, size, normalized)
		-- normalized: 0 = abajo, 1 = arriba. La UDim2.Position usa 0 = arriba,
		-- así que se invierte.
		local usable = 1 - size
		local y = (1 - normalized) * usable
		frame.Position = UDim2.new(frame.Position.X.Scale, frame.Position.X.Offset, y, 0)
	end

	minigameStartRemote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		mgToken = payload.token
		resultLabel.Visible = false
		mgFrame.Visible = true
		mgTitle.Text = "¡Algo picó!"

		local barSize = payload.barSize or 0.25
		local fishSize = payload.fishSize or 0.1
		catchBar.Size = UDim2.new(1, 0, barSize, 0)
		fishIcon.Size = UDim2.new(1, -8, fishSize, 0)
		catchBar.Position = UDim2.new(0, 0, 0.5, 0)
		catchBar.AnchorPoint = Vector2.new(0, 0)
		fishIcon.AnchorPoint = Vector2.new(0, 0)
		updateTrackFromNormalized(catchBar, barSize, 0.5)
		updateTrackFromNormalized(fishIcon, fishSize, 0.5)
		progressFill.Size = UDim2.new(1, 0, 0.5, 0)

		local function press()
			setHolding(true)
		end
		local function release()
			setHolding(false)
		end

		mgInputConn = UserInputService.InputBegan:Connect(function(input, gpe)
			if gpe then
				return
			end
			if HOOK_KEYS[input.KeyCode] or HOOK_INPUTS[input.UserInputType] then
				press()
			end
		end)
		mgInputConn2 = UserInputService.InputEnded:Connect(function(input, gpe)
			if HOOK_KEYS[input.KeyCode] or HOOK_INPUTS[input.UserInputType] then
				release()
			end
		end)
	end)

	minigameTickRemote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" or payload.token ~= mgToken then
			return
		end
		local barSize = catchBar.Size.Y.Scale
		local fishSize = fishIcon.Size.Y.Scale
		updateTrackFromNormalized(catchBar, barSize, payload.barPos or 0.5)
		updateTrackFromNormalized(fishIcon, fishSize, payload.fishPos or 0.5)
		progressFill.Size = UDim2.new(1, 0, math.clamp(payload.progress or 0, 0, 1), 0)
	end)

	minigameEndRemote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		if payload.token ~= mgToken then
			return
		end
		cooldownUntil = os.clock() + (FishingConfig.Cast.cooldownAfterFish or 1.2)
		resultLabel.Visible = true
		if payload.success then
			resultLabel.Text = string.format("¡Pescaste: %s!", payload.itemName or "algo")
			resultLabel.TextColor3 = Theme.Semantic.Good
			Sfx.play("xpDing")
		else
			resultLabel.Text = "Se te escapó..."
			resultLabel.TextColor3 = Theme.Semantic.Danger
			Sfx.play("spellDenied")
		end

		local endedToken = payload.token
		task.delay(1.1, function()
			-- Si mientras esperábamos ya arrancó una sesión nueva (mgToken
			-- cambió), no la pisamos cerrándola por error.
			if mgToken == endedToken then
				closeMinigame()
			end
		end)
	end)
end

return FishingUI