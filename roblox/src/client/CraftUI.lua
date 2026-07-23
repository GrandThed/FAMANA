-- Crafting panel (V key / top-right button, stacked under Character).
-- Left column lists every recipe the player COULD craft right now: always
-- the station-less ones, plus any whose `station` matches the live
-- `NearbyStations` attribute. Includes category filter tabs (Todos, Equipos, Muebles, Varios).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Recipes = require(Shared:WaitForChild("Recipes"))
local ItemModels = require(Shared:WaitForChild("ItemModels"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent.Theme)
local TopRightMenu = require(script.Parent.TopRightMenu)
local UIKit = require(script.Parent.UIKit)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local CraftUI = {}

local COLORS = {
	section = Theme.Semantic.SurfaceWell,
	line = Theme.Semantic.BorderHair,
	tile = Theme.Color.Ink900,
	accent = Theme.Color.Ember500,
	good = Theme.Semantic.Good,
	bad = Theme.Semantic.Bad,
	text = Theme.Semantic.TextBody,
	textDim = Theme.Semantic.TextMuted,
}

local ERROR_TEXT = {
	missing_materials = "Materiales insuficientes",
	no_space = "Sin espacio en el inventario",
	too_far = "Demasiado lejos de la mesa de crafteo",
	unknown_recipe = "Esa receta no existe",
	recipe_locked = "No has desbloqueado esta receta aún",
	bad_request = "Ocurrió un error al fabricar",
}

local PANEL_W = 640
local PANEL_H = 480
local LIST_W = 300
local ROW_H = 46

local function makeLabel(parent, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font or Theme.Font.BodyBold
	label.TextSize = size
	label.TextColor3 = color or COLORS.text
	label.Text = text
	label.Parent = parent
	return label
end

function CraftUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "CraftUI"
	gui.ResetOnSpawn = false
	gui.Enabled = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Visible = false
	panel.Parent = gui
	UIKit.stylePanel(panel)
	UIKit.addShadow(panel)
	UIKit.autoScale(panel)

	local title = makeLabel(panel, "Fabricación y Crafteo", Theme.Text.Title, Theme.Semantic.TextTitle, Theme.Font.DisplayBold)
	title.Size = UDim2.new(1, -80, 0, 30)
	title.Position = UDim2.new(0, 12, 0, 4)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local hintLabel = makeLabel(panel, "Crea herramientas, armas y muebles para tu campamento y sede", 12, COLORS.textDim, Theme.Font.Body)
	hintLabel.Size = UDim2.new(1, -80, 0, 16)
	hintLabel.Position = UDim2.new(0, 12, 0, 28)
	hintLabel.TextXAlignment = Enum.TextXAlignment.Left

	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -6, 0, 6)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	-- ---- Category Filter Tabs -----------------------------------------------
	local activeCategory = "ALL"
	local filterButtons = {}

	local filterContainer = Instance.new("Frame")
	filterContainer.Size = UDim2.new(0, LIST_W, 0, 24)
	filterContainer.Position = UDim2.new(0, 12, 0, 48)
	filterContainer.BackgroundTransparency = 1
	filterContainer.Parent = panel

	local filterLayout = Instance.new("UIListLayout")
	filterLayout.FillDirection = Enum.FillDirection.Horizontal
	filterLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	filterLayout.SortOrder = Enum.SortOrder.LayoutOrder
	filterLayout.Padding = UDim.new(0, 4)
	filterLayout.Parent = filterContainer

	local CATEGORIES = {
		{ id = "ALL", text = "🌐 Todos" },
		{ id = "EQUIP", text = "⚔️ Equipos" },
		{ id = "FURNITURE", text = "🏠 Muebles" },
		{ id = "RESOURCE", text = "🌿 Varios" },
	}

	-- ---- rows (left column) -------------------------------------------------
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(0, LIST_W, 1, -(78 + 36))
	list.Position = UDim2.new(0, 12, 0, 78)
	list.BackgroundColor3 = COLORS.section
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.Parent = panel

	local listStroke = Instance.new("UIStroke")
	listStroke.Thickness = 1
	listStroke.Color = COLORS.line
	listStroke.Parent = list

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 6)
	listPadding.PaddingLeft = UDim.new(0, 6)
	listPadding.PaddingRight = UDim.new(0, 6)
	listPadding.PaddingBottom = UDim.new(0, 6)
	listPadding.Parent = list

	-- ---- detail pane (right column) -----------------------------------------
	local detail = Instance.new("Frame")
	detail.Position = UDim2.new(0, LIST_W + 24, 0, 48)
	detail.Size = UDim2.new(1, -(LIST_W + 36), 1, -(48 + 36))
	detail.BackgroundColor3 = COLORS.section
	detail.BorderSizePixel = 0
	detail.Parent = panel

	local detailStroke = Instance.new("UIStroke")
	detailStroke.Thickness = 1
	detailStroke.Color = COLORS.line
	detailStroke.Parent = detail

	local statusLabel = makeLabel(panel, "", 12, COLORS.bad)
	statusLabel.Size = UDim2.new(1, -24, 0, 20)
	statusLabel.Position = UDim2.new(0, 12, 1, -28)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- ---- state ----------------------------------------------------------------
	local isOpen = false
	local busy = false
	local inventory = {}
	local nearby = {}
	local unlocked = {}
	local selected = Recipes.list()[1] and Recipes.list()[1].id
	local quantity = 1

	local craftItem = Remotes.getFunction("CraftItem")

	local function countOwned(itemId)
		local total = 0
		for _, entry in ipairs(inventory) do
			if entry.containerId == "main" and entry.itemId == itemId then
				total += entry.quantity
			end
		end
		return total
	end

	local function isAvailable(def)
		if def.locked and not unlocked[def.id] then
			return false
		end
		return def.station == nil or nearby[def.station] == true
	end

	local function isRecipeInCategory(def, cat)
		if cat == "ALL" then
			return true
		end
		local resultDef = Items.get(def.result.itemId)
		local itemType = resultDef and resultDef.type or ""
		local id = def.id or ""

		if cat == "EQUIP" then
			return itemType == "weapon" or itemType == "tool" or itemType == "armor" or itemType == "ring" or itemType == "ammo"
		elseif cat == "FURNITURE" then
			return itemType == "placeable" or id:find("mesa") or id:find("cama") or id:find("silla") or id:find("cofre") or id:find("pared") or id:find("techo") or id:find("puerta") or id:find("valla") or id:find("acampada") or id:find("carpa") or id:find("olla") or id:find("forja") or id:find("portal") or id:find("letrero") or id:find("maceta")
		elseif cat == "RESOURCE" then
			return itemType == "resource" or itemType == "consumable" or itemType == "food" or itemType == "potion"
		end
		return true
	end

	local function canAfford(def, qty)
		qty = qty or 1
		for _, ingredient in ipairs(def.ingredients) do
			if countOwned(ingredient.itemId) < ingredient.quantity * qty then
				return false
			end
		end
		return true
	end

	local function maxCraftable(def)
		local max = math.huge
		for _, ingredient in ipairs(def.ingredients) do
			local owned = countOwned(ingredient.itemId)
			max = math.min(max, math.floor(owned / ingredient.quantity))
		end
		if max == math.huge then
			max = 0
		end
		return max
	end

	local refresh

	local function updateFilterStyles()
		for catId, btn in pairs(filterButtons) do
			local isActive = catId == activeCategory
			btn.BackgroundColor3 = isActive and Theme.Semantic.PanelTop or Theme.Semantic.SurfaceWell
			btn.TextColor3 = isActive and Theme.Semantic.Currency or Theme.Semantic.TextMuted
		end
	end

	for idx, cat in ipairs(CATEGORIES) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 70, 1, 0)
		btn.Text = cat.text
		btn.Font = Enum.Font.SourceSansBold
		btn.TextSize = 11
		btn.AutoButtonColor = false
		btn.LayoutOrder = idx
		btn.Parent = filterContainer

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 5)
		btnCorner.Parent = btn

		local btnStroke = Instance.new("UIStroke")
		btnStroke.Thickness = 1
		btnStroke.Color = Theme.Semantic.BorderPanel
		btnStroke.Parent = btn

		filterButtons[cat.id] = btn

		btn.Activated:Connect(function()
			activeCategory = cat.id
			updateFilterStyles()
			Sfx.play("uiClick")
			refresh()
		end)
	end
	updateFilterStyles()

	local function doCraft(recipeId, qty)
		if busy then
			return
		end
		busy = true
		statusLabel.Text = ""
		local result = craftItem:InvokeServer(recipeId, qty)
		busy = false
		if typeof(result) ~= "table" or not result.ok then
			local code = typeof(result) == "table" and result.error or nil
			statusLabel.Text = ERROR_TEXT[code] or ERROR_TEXT.bad_request
		end
	end

	-- ---- detail pane rendering -----------------------------------------------
	local function detailText(text, size, color, font)
		local label = makeLabel(detail, text, size, color, font)
		label.TextXAlignment = Enum.TextXAlignment.Left
		return label
	end

	local function renderDetail()
		for _, child in ipairs(detail:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local def = selected and Recipes.get(selected)
		if not def then
			local hint = detailText("Selecciona una receta para fabricar", Theme.Text.Body, COLORS.textDim, Theme.Font.Body)
			hint.Size = UDim2.new(1, -24, 0, 40)
			hint.Position = UDim2.new(0, 12, 0, 8)
			return
		end

		local maxQty = math.max(1, maxCraftable(def))
		quantity = math.clamp(quantity, 1, maxQty)

		local resultDef = Items.get(def.result.itemId)
		local rarity = Rarity.forDef(resultDef)

		local thumbHolder = Instance.new("Frame")
		thumbHolder.Size = UDim2.new(0, 100, 0, 100)
		thumbHolder.Position = UDim2.new(0.5, -50, 0, 10)
		thumbHolder.BackgroundColor3 = Theme.Color.Ink900
		thumbHolder.BorderSizePixel = 0
		thumbHolder.Parent = detail

		local thumbStroke = Instance.new("UIStroke")
		thumbStroke.Thickness = 1
		thumbStroke.Color = rarity.color
		thumbStroke.Parent = thumbHolder

		local thumb = Instance.new("ViewportFrame")
		thumb.Size = UDim2.new(1, -8, 1, -8)
		thumb.Position = UDim2.new(0, 4, 0, 4)
		thumb.BackgroundTransparency = 1
		thumb.Ambient = Color3.fromRGB(180, 180, 190)
		thumb.LightColor = Color3.new(1, 1, 1)
		thumb.Parent = thumbHolder
		ItemModels.preview(thumb, def.result.itemId)

		local nameLbl = detailText(def.name, 16, rarity.textColor, Theme.Font.DisplayBold)
		nameLbl.Size = UDim2.new(1, -24, 0, 20)
		nameLbl.Position = UDim2.new(0, 12, 0, 116)
		nameLbl.TextXAlignment = Enum.TextXAlignment.Center

		local categoryLbl = detailText(def.station and ("Estación: " .. def.station) or "Portátil", 11, COLORS.textDim, Theme.Font.Body)
		categoryLbl.Size = UDim2.new(1, -24, 0, 14)
		categoryLbl.Position = UDim2.new(0, 12, 0, 138)
		categoryLbl.TextXAlignment = Enum.TextXAlignment.Center

		-- Ingredients list
		local ingHeader = makeLabel(detail, "Ingredientes Requeridos:", 12, Theme.Semantic.TextTitle)
		ingHeader.Size = UDim2.new(1, -24, 0, 16)
		ingHeader.Position = UDim2.new(0, 12, 0, 156)
		ingHeader.TextXAlignment = Enum.TextXAlignment.Left

		local ingFrame = Instance.new("Frame")
		ingFrame.Size = UDim2.new(1, -24, 0, 120)
		ingFrame.Position = UDim2.new(0, 12, 0, 176)
		ingFrame.BackgroundTransparency = 1
		ingFrame.Parent = detail

		local ingLayout = Instance.new("UIListLayout")
		ingLayout.SortOrder = Enum.SortOrder.LayoutOrder
		ingLayout.Padding = UDim.new(0, 4)
		ingLayout.Parent = ingFrame

		for i, ing in ipairs(def.ingredients) do
			local ingDef = Items.get(ing.itemId)
			local owned = countOwned(ing.itemId)
			local needed = ing.quantity * quantity
			local hasEnough = owned >= needed

			local ingRow = Instance.new("Frame")
			ingRow.Size = UDim2.new(1, 0, 0, 24)
			ingRow.BackgroundColor3 = Theme.Color.Ink900
			ingRow.BackgroundTransparency = 0.5
			ingRow.BorderSizePixel = 0
			ingRow.LayoutOrder = i
			ingRow.Parent = ingFrame

			local ingName = makeLabel(ingRow, ingDef and ingDef.name or ing.itemId, 12, hasEnough and COLORS.text or COLORS.bad)
			ingName.Size = UDim2.new(1, -80, 1, 0)
			ingName.Position = UDim2.new(0, 8, 0, 0)
			ingName.TextXAlignment = Enum.TextXAlignment.Left

			local ingCount = makeLabel(ingRow, string.format("%d / %d", owned, needed), 12, hasEnough and COLORS.good or COLORS.bad)
			ingCount.Size = UDim2.new(0, 70, 1, 0)
			ingCount.Position = UDim2.new(1, -78, 0, 0)
			ingCount.TextXAlignment = Enum.TextXAlignment.Right
		end

		-- Quantity Selector
		local qtyFrame = Instance.new("Frame")
		qtyFrame.Size = UDim2.new(1, -24, 0, 30)
		qtyFrame.Position = UDim2.new(0, 12, 1, -88)
		qtyFrame.BackgroundTransparency = 1
		qtyFrame.Parent = detail

		local minusBtn = UIKit.ghostButton(qtyFrame, "-")
		minusBtn.Size = UDim2.new(0, 30, 1, 0)
		minusBtn.Position = UDim2.new(0, 0, 0, 0)

		local qtyLabel = makeLabel(qtyFrame, tostring(quantity), 14, Theme.Semantic.Currency, Theme.Font.DisplayBold)
		qtyLabel.Size = UDim2.new(0, 50, 1, 0)
		qtyLabel.Position = UDim2.new(0, 35, 0, 0)
		qtyLabel.TextXAlignment = Enum.TextXAlignment.Center

		local plusBtn = UIKit.ghostButton(qtyFrame, "+")
		plusBtn.Size = UDim2.new(0, 30, 1, 0)
		plusBtn.Position = UDim2.new(0, 90, 0, 0)

		local maxBtn = UIKit.ghostButton(qtyFrame, "Max")
		maxBtn.Size = UDim2.new(0, 45, 1, 0)
		maxBtn.Position = UDim2.new(0, 125, 0, 0)

		minusBtn.Activated:Connect(function()
			if quantity > 1 then
				quantity -= 1
				renderDetail()
			end
		end)
		plusBtn.Activated:Connect(function()
			if quantity < maxQty then
				quantity += 1
				renderDetail()
			end
		end)
		maxBtn.Activated:Connect(function()
			if quantity ~= maxQty then
				quantity = maxQty
				renderDetail()
			end
		end)

		local available = isAvailable(def)
		local affordable = canAfford(def, quantity)
		local actionBtn
		if available and affordable then
			actionBtn = UIKit.primaryButton(detail, quantity > 1 and ("Fabricar x" .. quantity) or "Fabricar")
			actionBtn.MouseButton1Click:Connect(function()
				doCraft(def.id, quantity)
			end)
		else
			actionBtn = UIKit.ghostButton(detail, not available and "Estación Lejana" or "Faltan Materiales")
			actionBtn.TextColor3 = Theme.Semantic.TextDim
		end
		actionBtn.Size = UDim2.new(1, -24, 0, 36)
		actionBtn.Position = UDim2.new(0, 12, 1, -12)
		actionBtn.AnchorPoint = Vector2.new(0, 1)
	end

	-- ---- recipe rows ------------------------------------------------------------
	local rowWidgets = {}

	local function styleRowSelection()
		for recipeId, widgets in pairs(rowWidgets) do
			local isSelected = recipeId == selected
			widgets.row.BackgroundTransparency = isSelected and 0.05 or 0.35
			widgets.stroke.Thickness = isSelected and 2 or 1
		end
	end

	local function makeRow(order, def)
		local resultDef = Items.get(def.result.itemId)
		local rarity = Rarity.forDef(resultDef)
		local available = isAvailable(def)
		local affordable = canAfford(def)

		local row = Instance.new("TextButton")
		row.Text = ""
		row.AutoButtonColor = false
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.BackgroundColor3 = COLORS.tile
		row.BackgroundTransparency = 0.35
		row.BorderSizePixel = 0
		row.LayoutOrder = order
		row.Parent = list

		local rowStroke = Instance.new("UIStroke")
		rowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rowStroke.Thickness = 1
		rowStroke.Color = rarity.color
		rowStroke.Parent = row

		local thumbHolder = Instance.new("Frame")
		thumbHolder.Size = UDim2.new(0, ROW_H - 6, 0, ROW_H - 6)
		thumbHolder.Position = UDim2.new(0, 3, 0, 3)
		thumbHolder.BackgroundColor3 = Theme.Color.Ink850
		thumbHolder.BorderSizePixel = 0
		thumbHolder.Parent = row

		local thumb = Instance.new("ViewportFrame")
		thumb.Size = UDim2.new(1, -4, 1, -4)
		thumb.Position = UDim2.new(0, 2, 0, 2)
		thumb.BackgroundTransparency = 1
		thumb.Ambient = Color3.fromRGB(180, 180, 190)
		thumb.LightColor = Color3.new(1, 1, 1)
		thumb.Parent = thumbHolder
		ItemModels.preview(thumb, def.result.itemId)

		local nameLabel = makeLabel(row, def.name, 13, (available and affordable) and rarity.textColor or COLORS.textDim)
		nameLabel.Size = UDim2.new(1, -(ROW_H + 40), 1, 0)
		nameLabel.Position = UDim2.new(0, ROW_H + 4, 0, 0)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

		local dot = makeLabel(row, "●", 13, affordable and COLORS.good or COLORS.bad)
		dot.Size = UDim2.new(0, 24, 1, 0)
		dot.Position = UDim2.new(1, -30, 0, 0)
		dot.TextXAlignment = Enum.TextXAlignment.Right

		row.MouseButton1Click:Connect(function()
			selected = def.id
			quantity = 1
			statusLabel.Text = ""
			styleRowSelection()
			renderDetail()
		end)

		rowWidgets[def.id] = { row = row, stroke = rowStroke }
	end

	refresh = function()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		rowWidgets = {}
		local order = 0
		local selectionListed = false
		for _, def in ipairs(Recipes.list()) do
			if isAvailable(def) and isRecipeInCategory(def, activeCategory) then
				order += 1
				makeRow(order, def)
				if not selected then
					selected = def.id
				end
				if def.id == selected then
					selectionListed = true
				end
			end
		end
		if not selectionListed then
			selected = nil
		end
		styleRowSelection()
		renderDetail()
	end

	-- ---- toggling ---------------------------------------------------------------
	local function setOpen(open)
		isOpen = open
		Sfx.play(isOpen and "panelOpen" or "panelClose")
		panel.Visible = isOpen
		if isOpen then
			statusLabel.Text = ""
			refresh()
		end
	end

	local function toggle()
		setOpen(not isOpen)
	end

	local openBtn = TopRightMenu.addButton("Craft (V)", 3)
	openBtn.Name = "CraftButton"

	openBtn.Activated:Connect(toggle)
	closeBtn.Activated:Connect(function()
		setOpen(false)
	end)

	ContextActionService:BindAction("ToggleCrafting", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.V)

	-- ---- live data ----------------------------------------------------------------
	Remotes.get("InventoryUpdated").OnClientEvent:Connect(function(entries)
		inventory = entries or {}
		if isOpen then
			refresh()
		end
	end)
	task.spawn(function()
		local entries = Remotes.getFunction("RequestInventory"):InvokeServer()
		if typeof(entries) == "table" and #inventory == 0 then
			inventory = entries
		end
	end)

	local function readNearby()
		nearby = {}
		local raw = player:GetAttribute("NearbyStations")
		if typeof(raw) == "string" then
			for station in raw:gmatch("[^,]+") do
				nearby[station] = true
			end
		end
	end
	readNearby()
	player:GetAttributeChangedSignal("NearbyStations"):Connect(function()
		readNearby()
		if isOpen then
			refresh()
		end
	end)

	local function readUnlocked()
		unlocked = {}
		local raw = player:GetAttribute("UnlockedRecipes")
		if typeof(raw) == "string" then
			for recipeId in raw:gmatch("[^,]+") do
				unlocked[recipeId] = true
			end
		end
	end
	readUnlocked()
	player:GetAttributeChangedSignal("UnlockedRecipes"):Connect(function()
		readUnlocked()
		if isOpen then
			refresh()
		end
	end)
end

return CraftUI
