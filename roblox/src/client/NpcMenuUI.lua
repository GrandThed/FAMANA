-- Menú conceptual que se abre al interactuar (E / click) con CUALQUIER NPC
-- (vendor, quest giver, camp architect) — un solo remoto (OpenNpcMenu) para
-- los tres, en vez de cada ProximityPrompt saltando directo a su panel/
-- acción. Mismo patrón que StoreUI/QuestUI (RemoteEvent + poll de distancia
-- para auto-cerrar), pero este panel no tiene lógica propia de servidor más
-- allá de QuestOffer: solo decide A DÓNDE mandar al jugador.
--
-- info (OpenNpcMenu): { kind = "vendor" | "giver" | "architect", name, position,
--   storeId?, storeName?,      -- vendor
--   giverId?, quests?,         -- giver (y vendors que también dan quests)
--   lines? }                   -- pool de flavor text para "Hablar"
--
-- "Hablar":
--   si info.giverId existe, primero se pregunta al server (QuestOffer) si
--   hay algo para ofrecer/entregar; si lo hay, se abre el panel de quest ya
--   enfocado en esa. Si no hay nada (o el NPC no da quests), se muestra una
--   línea al azar de info.lines — texto "predeterminado" que se repite.
-- "Ver tienda" / "Ver misiones": abren StoreUI/QuestUI directo, reusando la
--   info que ya mandó el ProximityPrompt (sin otro viaje al server).
-- "Mejorar campamento" (kind == "architect"): invoca UpgradeCampTier y
--   muestra el resultado (éxito o motivo del rechazo) con el mismo panel de
--   mensaje que usa el texto predeterminado, en vez de un toast aparte.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local ClientState = require(script.Parent.ClientState)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local NpcMenuUI = {}

local COLORS = {
	text = Theme.Semantic.TextBody,
	textDim = Theme.Semantic.TextMuted,
}

local PANEL_W = 360
local CLOSE_DISTANCE = 20 -- studs; walk away → the panel closes itself (mismo criterio que Store/Quest)
local AVATAR_SIZE = 34

local OPEN_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TYPE_CHAR_DELAY = 0.022 -- segundos entre letra y letra del diálogo
local TYPE_VOICE_EVERY = 2 -- el blip de "voz" suena cada N letras, no en cada una

-- Pitch base del blip de voz por tipo de NPC — el arquitecto suena grave
-- (aventurero viejo), la dadora de misiones aguda (anciana), el vendedor
-- queda neutral. ±5% de jitter alrededor de esto en cada letra para que no
-- suene a metrónomo.
local VOICE_PITCH = {
	architect = 0.72,
	giver = 1.25,
	vendor = 1.0,
}
local VOICE_PITCH_DEFAULT = 1.0

local DEFAULT_LINES = { "..." } -- por si un NPC queda sin lines por descuido de contenido

local function makeLabel(parent, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font or Theme.Font.Body
	label.TextSize = size
	label.TextColor3 = color or COLORS.text
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Parent = parent
	return label
end

function NpcMenuUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "NpcMenuUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, PANEL_W, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Position = UDim2.new(0.5, 0, 0.66, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Visible = false
	panel.Parent = gui
	UIKit.stylePanel(panel)
	UIKit.addShadow(panel)
	UIKit.autoScale(panel)

	-- Escala desde la que arranca/termina la animación de apertura y cierre
	-- (AutomaticSize hace que tweenear el Size directo no sirva, así que se
	-- escala el panel entero con un UIScale en vez de eso).
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 1
	uiScale.Parent = panel

	-- Retrato: círculo con la inicial del NPC. No depende de arte nuevo —
	-- si más adelante suben portraits de verdad, alcanza con poner una
	-- ImageLabel.Image acá adentro en vez de la letra.
	local avatar = Instance.new("Frame")
	avatar.Size = UDim2.new(0, AVATAR_SIZE, 0, AVATAR_SIZE)
	avatar.Position = UDim2.new(0, 14, 0, 6)
	avatar.BackgroundColor3 = Theme.Color.Ink650
	avatar.BorderSizePixel = 0
	avatar.ZIndex = panel.ZIndex + 1
	avatar.Parent = panel

	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0)
	avatarCorner.Parent = avatar

	local avatarStroke = Instance.new("UIStroke")
	avatarStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	avatarStroke.Thickness = 1
	avatarStroke.Color = Theme.Color.Ember400
	avatarStroke.Transparency = 0.15
	avatarStroke.Parent = avatar

	local avatarLabel = Instance.new("TextLabel")
	avatarLabel.BackgroundTransparency = 1
	avatarLabel.Size = UDim2.new(1, 0, 1, 0)
	avatarLabel.FontFace = Theme.Font.DisplayBold
	avatarLabel.TextSize = 16
	avatarLabel.TextColor3 = Theme.Semantic.TextTitle
	avatarLabel.Text = "?"
	avatarLabel.ZIndex = avatar.ZIndex + 1
	avatarLabel.Parent = avatar

	local title = UIKit.titleBar(panel, "", 36)
	title.Position = UDim2.new(0, 14 + AVATAR_SIZE + 8, 0, 0)
	title.Size = UDim2.new(1, -(36 + 16 + AVATAR_SIZE + 8), 0, 36)
	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -6, 0, 6)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, -24, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Position = UDim2.new(0, 12, 0, 44)
	body.Parent = panel

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Padding = UDim.new(0, 8)
	bodyLayout.Parent = body

	local bodyBottomPad = Instance.new("Frame")
	bodyBottomPad.BackgroundTransparency = 1
	bodyBottomPad.Size = UDim2.new(1, 0, 0, 28)
	bodyBottomPad.LayoutOrder = 100
	bodyBottomPad.Parent = body

	-- ---- state ------------------------------------------------------------
	local current = nil -- payload de OpenNpcMenu
	local mode = "menu" -- "menu" | "message" (flavor text O resultado de una acción como el upgrade)
	local messageText = ""
	local busy = false
	local messageTypeGen = 0

	local questOffer = Remotes.getFunction("QuestOffer")
	local upgradeCampTier = Remotes.getFunction("UpgradeCampTier")

	local render -- forward declaration

	local function clearBody()
		for _, child in ipairs(body:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local activeTween = nil

	local function playOpen()
		if activeTween then
			activeTween:Cancel()
		end
		panel.Visible = true
		panel.BackgroundTransparency = 1
		uiScale.Scale = 0.85
		TweenService:Create(panel, OPEN_TWEEN, { BackgroundTransparency = 0 }):Play()
		activeTween = TweenService:Create(uiScale, OPEN_TWEEN, { Scale = 1 })
		activeTween:Play()
	end

	local function playClose()
		if activeTween then
			activeTween:Cancel()
		end
		TweenService:Create(panel, CLOSE_TWEEN, { BackgroundTransparency = 1 }):Play()
		activeTween = TweenService:Create(uiScale, CLOSE_TWEEN, { Scale = 0.85 })
		activeTween:Play()
		activeTween.Completed:Connect(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed then
				panel.Visible = false
				panel.BackgroundTransparency = 0
			end
		end)
	end

	local function close()
		current = nil
		-- Corta cualquier animación de tipeo en curso (task.spawn en el modo
		-- "message" de render()): esa corrutina solo chequea `messageTypeGen`
		-- contra el valor que tenía al arrancar, así que sin este bump sigue
		-- viva de fondo — tipeando y reproduciendo el blip de voz — aunque
		-- el panel ya esté cerrado/invisible.
		messageTypeGen += 1
		playClose()
		ClientState.npcMenuOpen = false
		Sfx.play("panelClose")
	end
	ClientState.closeNpcMenu = close
	closeBtn.Activated:Connect(close)

	-- Escape cierra el panel igual que la X (solo si nadie más ya consumió
	-- la tecla, p. ej. escribiendo en un chat/textbox).
	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent or input.KeyCode ~= Enum.KeyCode.Escape then
			return
		end
		if panel.Visible then
			close()
		end
	end)

	local function openStore()
		local storeId = current and current.storeId
		local storeName = current and current.storeName
		local vendorName = current and current.name
		local position = current and current.position
		close()
		if ClientState.openStorePanel then
			ClientState.openStorePanel({
				storeId = storeId,
				storeName = storeName,
				vendorName = vendorName,
				position = position,
			})
		end
	end

	local function openQuests(quests)
		local voicePitch = current and VOICE_PITCH[current.kind]
		local giverName = current and current.name
		local giverId = current and current.giverId
		local position = current and current.position
		close()
		if ClientState.openQuestPanel then
			ClientState.openQuestPanel({
				giverId = giverId,
				giverName = giverName,
				position = position,
				quests = quests,
				voicePitch = voicePitch,
			})
		end
	end

	local function pickFlavorLine()
		local lines = (current and current.lines) or DEFAULT_LINES
		if typeof(lines) ~= "table" or #lines == 0 then
			lines = DEFAULT_LINES
		end
		return lines[math.random(1, #lines)]
	end

	local function onTalk()
		if busy or not current then
			return
		end
		-- Guardamos referencias: openStore/openQuests llaman close(), que
		-- limpia `current` — y un click tardío en un botón viejo del body
		-- no debería colar una acción sobre un NPC que ya no es el actual.
		local info = current
		if info.giverId then
			busy = true
			local ok, offer = pcall(function()
				return questOffer:InvokeServer(info.giverId)
			end)
			busy = false
			if current ~= info then
				return -- el panel se cerró/cambió mientras esperábamos al server
			end
			if ok and typeof(offer) == "table" then
				Sfx.play("uiClick")
				openQuests({ offer })
				return
			end
		end
		Sfx.play("uiClick")
		messageText = pickFlavorLine()
		mode = "message"
		render()
	end

	-- Camp Architect: intenta el upgrade YA (mismo tryUpgrade de siempre, ya
	-- validado server-side) y muestra el resultado — éxito o el motivo del
	-- rechazo (sin materiales, tier máximo, etc.) — en vez de un toast.
	local function onUpgrade()
		if busy or not current then
			return
		end
		local info = current
		busy = true
		local ok, result = pcall(function()
			return upgradeCampTier:InvokeServer()
		end)
		busy = false
		if current ~= info then
			return
		end
		if ok and typeof(result) == "table" and typeof(result.message) == "string" then
			messageText = result.message
			if result.ok then
				Sfx.play("levelUp")
			end
		else
			messageText = "Algo salió mal — probá de nuevo."
		end
		mode = "message"
		render()
	end

	-- ---- render -------------------------------------------------------------
	render = function()
		clearBody()
		if not current then
			return
		end
		title.Text = current.name or "..."
		avatarLabel.Text = (current.name and current.name:sub(1, 1):upper()) or "?"

		if mode == "message" then
			messageTypeGen += 1
			local myGen = messageTypeGen

			local label = makeLabel(body, "", 14, COLORS.text, Theme.Font.Body)
			label.LayoutOrder = 1

			local fullText = messageText
			local basePitch = (current and VOICE_PITCH[current.kind]) or VOICE_PITCH_DEFAULT
			task.spawn(function()
				local totalChars = utf8.len(fullText) or #fullText
				local prevByte = 1
				for i = 1, totalChars do
					if messageTypeGen ~= myGen then
						return -- se cerró o cambió el mensaje antes de terminar
					end
					local nextByte = utf8.offset(fullText, i + 1)
					local endByte = (nextByte or (#fullText + 1)) - 1
					label.Text = nextByte and fullText:sub(1, nextByte - 1) or fullText

					local char = fullText:sub(prevByte, endByte)
					prevByte = endByte + 1
					if char:match("%S") and i % TYPE_VOICE_EVERY == 0 then
						Sfx.play("npcTalk", basePitch * (0.95 + math.random() * 0.1))
					end

					task.wait(TYPE_CHAR_DELAY)
				end
			end)

			local backBtn = UIKit.ghostButton(body, "< Volver")
			backBtn.Size = UDim2.new(1, 0, 0, 30)
			backBtn.LayoutOrder = 2
			backBtn.Activated:Connect(function()
				mode = "menu"
				render()
			end)

			return
		end

		-- mode == "menu"
		-- El botón principal (rojo) es la acción propia del NPC, no "Hablar":
		-- mejorar campamento > tienda > misiones, en ese orden de prioridad
		-- (un vendedor que también da misiones prioriza la tienda como
		-- principal y deja "Ver misiones" como botón secundario aparte).
		local primaryLabel, primaryAction
		if current.kind == "architect" then
			primaryLabel, primaryAction = "Mejorar campamento", onUpgrade
		elseif current.kind == "vendor" and current.storeId then
			primaryLabel, primaryAction = "Ver tienda", openStore
		elseif current.giverId then
			primaryLabel, primaryAction = "Ver misiones", function()
				openQuests(current.quests or {})
			end
		end

		local layoutOrder = 1
		if primaryLabel then
			local primaryBtn = UIKit.primaryButton(body, primaryLabel)
			primaryBtn.Size = UDim2.new(1, 0, 0, 34)
			primaryBtn.TextSize = Theme.Text.Item
			primaryBtn.LayoutOrder = layoutOrder
			primaryBtn.Activated:Connect(primaryAction)
			layoutOrder += 1
		end

		-- Si el NPC no tiene ninguna acción propia (solo charla), "Hablar"
		-- queda como único botón y se muestra en estilo principal.
		local talkBtn = primaryLabel and UIKit.ghostButton(body, "Hablar") or UIKit.primaryButton(body, "Hablar")
		talkBtn.Size = UDim2.new(1, 0, 0, primaryLabel and 30 or 34)
		talkBtn.LayoutOrder = layoutOrder
		talkBtn.Activated:Connect(onTalk)
		layoutOrder += 1

		-- "Ver misiones" como secundario solo si no quedó como principal
		-- arriba (es decir, un vendor/architect que además da misiones).
		if current.giverId and primaryLabel ~= "Ver misiones" then
			local questsBtn = UIKit.ghostButton(body, "Ver misiones")
			questsBtn.Size = UDim2.new(1, 0, 0, 30)
			questsBtn.LayoutOrder = layoutOrder
			questsBtn.Activated:Connect(function()
				openQuests(current.quests or {})
			end)
			layoutOrder += 1
		end
	end

	-- ---- open / close (via OpenNpcMenu) --------------------------------------
	Remotes.get("OpenNpcMenu").OnClientEvent:Connect(function(info)
		if typeof(info) ~= "table" then
			return
		end
		if ClientState.inventoryOpen and ClientState.closeInventory then
			ClientState.closeInventory()
		end
		if ClientState.storeOpen and ClientState.closeStore then
			ClientState.closeStore()
		end
		if ClientState.questOpen and ClientState.closeQuest then
			ClientState.closeQuest()
		end
		if ClientState.chestOpen and ClientState.closeChest then
			ClientState.closeChest()
		end
		current = info
		mode = "menu"
		playOpen()
		ClientState.npcMenuOpen = true
		Sfx.play("panelOpen")
		render()
	end)

	-- Walk away → close (los paneles a los que este menú lleva tienen su
	-- propio chequeo de distancia server-side igual).
	task.spawn(function()
		while true do
			task.wait(0.5)
			if current and typeof(current.position) == "Vector3" then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and (root.Position - current.position).Magnitude > CLOSE_DISTANCE then
					close()
				end
			end
		end
	end)
end

return NpcMenuUI