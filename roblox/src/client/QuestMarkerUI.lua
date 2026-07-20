-- Ícono "!" flotando sobre la cabeza de cualquier NPC dador de quests que
-- tenga algo para EXTE jugador puntual: una misión nueva para ofrecer (ver
-- la rotación de QuestService) o una activa lista para entregar. El server
-- decide el bool por giverId (depende de nivel/progreso de cada jugador,
-- no es lo mismo para todos) y lo empuja por el remote QuestGiverMarkers;
-- este módulo solo prende/apaga el ícono que ya tiene armado.
--
-- Encuentra los NPCs vía CollectionService (tag "QuestGiverNPC", mismo que
-- server/QuestService.registerGiverPosition setea) en vez de que el server
-- le pase referencias de modelo — funciona igual sea cual sea el servicio
-- que construyó ese NPC (QuestService, CampArchitectService, un futuro
-- vendor con giverId, ...), un solo lugar para el ícono de todos.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent.Theme)

local QuestMarkerUI = {}

local TAG = "QuestGiverNPC"

local latestMarkers = {} -- [giverId] = bool, último estado que mandó el server
local badgesByGiver = {} -- [giverId] = { [part] = billboard }

local function buildBadge(part, giverId)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "QuestMarker"
	billboard.Size = UDim2.new(0, 34, 0, 34)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4.6, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = latestMarkers[giverId] == true
	billboard.Parent = part

	local badge = Instance.new("Frame")
	badge.Size = UDim2.new(1, 0, 1, 0)
	badge.BackgroundColor3 = Theme.Color.Gold400
	badge.BorderSizePixel = 0
	badge.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = badge

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Theme.Color.Ink900
	stroke.Parent = badge

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Font.BodyBold
	label.TextSize = 22
	label.TextColor3 = Theme.Color.Ink900
	label.Text = "!"
	label.Parent = badge

	return billboard
end

local function watchPart(part)
	if not part:IsA("BasePart") then
		return
	end
	local giverId = part:GetAttribute("GiverId")
	if not giverId then
		return
	end

	local billboard = buildBadge(part, giverId)
	badgesByGiver[giverId] = badgesByGiver[giverId] or {}
	badgesByGiver[giverId][part] = billboard

	part.AncestryChanged:Connect(function(_, parent)
		if not parent then
			badgesByGiver[giverId][part] = nil
		end
	end)
end

local function applyMarkers(markers)
	for giverId, visible in pairs(markers) do
		latestMarkers[giverId] = visible == true
		for _, billboard in pairs(badgesByGiver[giverId] or {}) do
			billboard.Enabled = visible == true
		end
	end
end

-- Leve "respiración" (escala) en vez de un bob de posición — se nota igual
-- de bien colgando sobre la cabeza de un NPC quieto, sin competir con el
-- vaivén de la cámara al caminar cerca.
local function startPulse()
	RunService.Heartbeat:Connect(function()
		local scale = 1 + 0.08 * math.sin(os.clock() * 3)
		for _, parts in pairs(badgesByGiver) do
			for _, billboard in pairs(parts) do
				if billboard.Enabled then
					billboard.Size = UDim2.new(0, 34 * scale, 0, 34 * scale)
				end
			end
		end
	end)
end

function QuestMarkerUI.start()
	for _, part in ipairs(CollectionService:GetTagged(TAG)) do
		watchPart(part)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(watchPart)

	local remote = Remotes.get("QuestGiverMarkers")
	remote.OnClientEvent:Connect(applyMarkers)

	startPulse()
end

return QuestMarkerUI
