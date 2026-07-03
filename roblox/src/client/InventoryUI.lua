-- Grid inventory screen (toggled with B / the top-right button).
-- Two columns:
--   left  — equipment paper doll (drag an item onto a slot to equip) and the
--           active effects panel (icons + countdowns from Effect_* attributes)
--   right — utilities bar (Sort button, gold readout) over the scrollable
--           10x30 item grid.
-- Items span WxH cells (item def `size`); drag & drop moves them (R rotates
-- while dragging, green/red highlight previews the drop). Hovering an item
-- and pressing 3–0 quick-binds tools/consumables to the hotbar (HotbarBinds).
-- Every move is validated server-side; this UI only previews and asks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local ItemModels = require(Shared:WaitForChild("ItemModels"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = require(Shared:WaitForChild("Config"))
local Effects = require(Shared:WaitForChild("Effects"))
local ClientState = require(script.Parent.ClientState)
local HotbarBinds = require(script.Parent.HotbarBinds)

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local InventoryUI = {}

local CELL = 40 -- px per grid cell
local GRID_W = Config.inventoryGrid.width
local GRID_H = Config.inventoryGrid.height
local VISIBLE_ROWS = 11 -- grid rows shown before scrolling
local EQUIP_SLOT = 54 -- px, paper-doll slot size
local TOPBAR = 36

local COLORS = {
	panel = Color3.fromRGB(25, 25, 28),
	section = Color3.fromRGB(33, 33, 38),
	line = Color3.fromRGB(48, 48, 55),
	tile = Color3.fromRGB(52, 52, 62),
	tileStroke = Color3.fromRGB(90, 90, 105),
	good = Color3.fromRGB(80, 180, 90),
	bad = Color3.fromRGB(200, 70, 60),
	gold = Color3.fromRGB(255, 220, 120),
	text = Color3.fromRGB(235, 235, 240),
	textDim = Color3.fromRGB(150, 150, 160),
}

-- Quick-bind keys → hotbar slot index (slots 0/1 are the reserved weapons).
local BIND_KEYS = {
	[Enum.KeyCode.Three] = 2,
	[Enum.KeyCode.Four] = 3,
	[Enum.KeyCode.Five] = 4,
	[Enum.KeyCode.Six] = 5,
	[Enum.KeyCode.Seven] = 6,
	[Enum.KeyCode.Eight] = 7,
	[Enum.KeyCode.Nine] = 8,
	[Enum.KeyCode.Zero] = 9,
}

-- Paper-doll arrangement: [slotName] = { column (0 | 1 | 0.5 = centered), row }.
local SLOT_POS = {
	head = { 0.5, 0 },
	weapon = { 0, 1 },
	chest = { 1, 1 },
	offhand = { 0, 2 },
	hands = { 1, 2 },
	ring1 = { 0, 3 },
	legs = { 1, 3 },
	ring2 = { 0, 4 },
	feet = { 1, 4 },
	back = { 0.5, 5 },
}

local SLOT_LABEL = {
	head = "Helmet",
	chest = "Chest",
	hands = "Gloves",
	legs = "Legs",
	feet = "Boots",
	weapon = "Weapon",
	offhand = "Offhand",
	back = "Back",
	ring1 = "Ring",
	ring2 = "Ring",
}

-- slotName → equipment container x (0-based), from the shared canonical order.
local SLOT_INDEX = {}
for i, name in ipairs(Items.EQUIPMENT_SLOTS) do
	SLOT_INDEX[name] = i - 1
end

local function makeLabel(parent, text, size, color)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = size
	label.TextColor3 = color or COLORS.text
	label.Text = text
	label.Parent = parent
	return label
end

local function makeViewport(parent)
	local thumb = Instance.new("ViewportFrame")
	thumb.Size = UDim2.new(1, -4, 1, -4)
	thumb.Position = UDim2.new(0, 2, 0, 2)
	thumb.BackgroundTransparency = 1
	thumb.Ambient = Color3.fromRGB(180, 180, 190)
	thumb.LightColor = Color3.new(1, 1, 1)
	thumb.Parent = parent
	return thumb
end

function InventoryUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "InventoryUI"
	gui.ResetOnSpawn = false
	gui.Enabled = true -- always on; we toggle the panel's Visibility instead
	gui.Parent = player:WaitForChild("PlayerGui")

	-- ---- panel shell -------------------------------------------------------
	local gridPixW = GRID_W * CELL
	local rightW = gridPixW + 14 -- room for the scrollbar
	local leftW = 2 * EQUIP_SLOT + 3 * 16 + 60 -- two slot columns + gaps
	local panelW = leftW + rightW + 36
	local panelH = TOPBAR + VISIBLE_ROWS * CELL + 58

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, panelW, 0, panelH)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = COLORS.panel
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui

	local title = makeLabel(panel, "Inventory", 16)
	title.Size = UDim2.new(1, -34, 0, 30)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 30, 0, 30)
	closeBtn.Position = UDim2.new(1, -2, 0, 2)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Text = "X"
	closeBtn.Parent = panel

	-- ---- left column: paper doll + effects ---------------------------------
	local leftCol = Instance.new("Frame")
	leftCol.Size = UDim2.new(0, leftW, 1, -(TOPBAR + 12))
	leftCol.Position = UDim2.new(0, 12, 0, TOPBAR)
	leftCol.BackgroundColor3 = COLORS.section
	leftCol.BorderSizePixel = 0
	leftCol.Parent = panel

	local equipTitle = makeLabel(leftCol, "EQUIPMENT", 12, COLORS.textDim)
	equipTitle.Size = UDim2.new(1, 0, 0, 22)

	local colX = { [0] = 30, [1] = leftW - EQUIP_SLOT - 30, [0.5] = (leftW - EQUIP_SLOT) / 2 }

	-- equipSlots[slotName] = { frame, thumb, nameLabel, stroke, entry }
	local equipSlots = {}
	for slotName, pos in pairs(SLOT_POS) do
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(0, EQUIP_SLOT, 0, EQUIP_SLOT)
		frame.Position = UDim2.new(0, colX[pos[1]], 0, 26 + pos[2] * (EQUIP_SLOT + 8))
		frame.BackgroundColor3 = COLORS.panel
		frame.BorderSizePixel = 0
		frame.Parent = leftCol

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.5
		stroke.Color = COLORS.line
		stroke.Parent = frame

		local nameLabel = makeLabel(frame, SLOT_LABEL[slotName], 10, COLORS.textDim)
		nameLabel.Size = UDim2.new(1, 0, 1, 0)
		nameLabel.TextWrapped = true

		local thumb = makeViewport(frame)

		equipSlots[slotName] = { frame = frame, thumb = thumb, nameLabel = nameLabel, stroke = stroke, entry = nil }
	end

	local effectsY = 26 + 6 * (EQUIP_SLOT + 8) + 10
	local effectsTitle = makeLabel(leftCol, "EFFECTS", 12, COLORS.textDim)
	effectsTitle.Size = UDim2.new(1, 0, 0, 22)
	effectsTitle.Position = UDim2.new(0, 0, 0, effectsY)

	local effectsList = Instance.new("Frame")
	effectsList.Size = UDim2.new(1, -20, 1, -(effectsY + 26))
	effectsList.Position = UDim2.new(0, 10, 0, effectsY + 24)
	effectsList.BackgroundTransparency = 1
	effectsList.Parent = leftCol

	local effectsLayout = Instance.new("UIListLayout")
	effectsLayout.Padding = UDim.new(0, 4)
	effectsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	effectsLayout.Parent = effectsList

	-- ---- right column: utilities bar + grid --------------------------------
	local rightX = leftW + 24
	local utilBar = Instance.new("Frame")
	utilBar.Size = UDim2.new(0, rightW, 0, 30)
	utilBar.Position = UDim2.new(0, rightX, 0, TOPBAR)
	utilBar.BackgroundColor3 = COLORS.section
	utilBar.BorderSizePixel = 0
	utilBar.Parent = panel

	local sortBtn = Instance.new("TextButton")
	sortBtn.Size = UDim2.new(0, 70, 0, 24)
	sortBtn.Position = UDim2.new(0, 4, 0, 3)
	sortBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 160)
	sortBtn.BorderSizePixel = 0
	sortBtn.Font = Enum.Font.GothamBold
	sortBtn.TextSize = 13
	sortBtn.TextColor3 = Color3.new(1, 1, 1)
	sortBtn.Text = "Sort"
	sortBtn.Parent = utilBar

	-- Shows the hovered item's name (poor man's inspect tooltip).
	local hoverLabel = makeLabel(utilBar, "", 13, COLORS.text)
	hoverLabel.Size = UDim2.new(1, -200, 1, 0)
	hoverLabel.Position = UDim2.new(0, 84, 0, 0)
	hoverLabel.TextXAlignment = Enum.TextXAlignment.Left

	local goldLabel = makeLabel(utilBar, "Gold: 0", 14, COLORS.gold)
	goldLabel.Size = UDim2.new(0, 110, 1, 0)
	goldLabel.Position = UDim2.new(1, -114, 0, 0)
	goldLabel.TextXAlignment = Enum.TextXAlignment.Right

	local gridScroll = Instance.new("ScrollingFrame")
	gridScroll.Size = UDim2.new(0, rightW, 0, VISIBLE_ROWS * CELL)
	gridScroll.Position = UDim2.new(0, rightX, 0, TOPBAR + 34)
	gridScroll.BackgroundColor3 = COLORS.section
	gridScroll.BorderSizePixel = 0
	gridScroll.CanvasSize = UDim2.new(0, gridPixW, 0, GRID_H * CELL)
	gridScroll.ScrollBarThickness = 10
	gridScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	gridScroll.Parent = panel

	-- Everything grid-positioned parents here so it scrolls with the canvas.
	local itemsLayer = Instance.new("Frame")
	itemsLayer.Size = UDim2.new(0, gridPixW, 0, GRID_H * CELL)
	itemsLayer.BackgroundTransparency = 1
	itemsLayer.Parent = gridScroll

	-- Grid lines (thin frames beat 300 cell frames).
	for i = 0, GRID_W do
		local line = Instance.new("Frame")
		line.Size = UDim2.new(0, 1, 1, 0)
		line.Position = UDim2.new(0, i * CELL, 0, 0)
		line.BackgroundColor3 = COLORS.line
		line.BorderSizePixel = 0
		line.ZIndex = 1
		line.Parent = itemsLayer
	end
	for j = 0, GRID_H do
		local line = Instance.new("Frame")
		line.Size = UDim2.new(1, 0, 0, 1)
		line.Position = UDim2.new(0, 0, 0, j * CELL)
		line.BackgroundColor3 = COLORS.line
		line.BorderSizePixel = 0
		line.ZIndex = 1
		line.Parent = itemsLayer
	end

	-- Drop preview highlight (green = fits, red = blocked).
	local highlight = Instance.new("Frame")
	highlight.BackgroundColor3 = COLORS.good
	highlight.BackgroundTransparency = 0.6
	highlight.BorderSizePixel = 0
	highlight.Visible = false
	highlight.ZIndex = 5
	highlight.Parent = itemsLayer

	-- ---- state ---------------------------------------------------------------
	local currentInventory = {}
	local hovered = nil -- entry under the mouse (for tooltips/quick binds)
	local drag = nil -- { itemId, from = {containerId,x,y}, rotated, sourceObj, ghost, thumb, dropTarget }
	local dragStepConn = nil

	local moveItemRemote, sortRemote -- resolved async in the remotes block

	local function sameRef(entry, ref)
		return entry.containerId == ref.containerId and entry.x == ref.x and entry.y == ref.y
	end

	-- Client-side fit preview for the main grid (server still has final say).
	-- Returns ok, plus whether the drop would merge into a same-item stack.
	local function canPlace(gx, gy, w, h, itemId)
		if gx < 0 or gy < 0 or gx + w > GRID_W or gy + h > GRID_H then
			return false
		end
		local overlaps = {}
		for _, entry in ipairs(currentInventory) do
			if entry.containerId == "main" and not (drag and sameRef(entry, drag.from)) then
				local ew, eh = Items.sizeFor(entry.itemId, entry.rotated)
				if entry.x < gx + w and gx < entry.x + ew and entry.y < gy + h and gy < entry.y + eh then
					overlaps[#overlaps + 1] = entry
				end
			end
		end
		if #overlaps == 0 then
			return true
		end
		local def = Items.get(itemId)
		if #overlaps == 1 and overlaps[1].itemId == itemId and def and def.stackable then
			return overlaps[1].quantity < Items.maxStackFor(itemId), true
		end
		return false
	end

	local function resetEquipStrokes()
		for _, slot in pairs(equipSlots) do
			slot.stroke.Color = COLORS.line
			slot.stroke.Thickness = 1.5
		end
	end

	local function destroyGhost()
		if drag and drag.ghost then
			drag.ghost:Destroy()
		end
	end

	local function buildGhost()
		destroyGhost()
		local w, h = Items.sizeFor(drag.itemId, drag.rotated)
		local ghost = Instance.new("Frame")
		ghost.Size = UDim2.new(0, w * CELL, 0, h * CELL)
		ghost.BackgroundColor3 = COLORS.tile
		ghost.BackgroundTransparency = 0.35
		ghost.BorderSizePixel = 0
		ghost.ZIndex = 50
		ghost.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = COLORS.gold
		stroke.Parent = ghost
		local thumb = makeViewport(ghost)
		thumb.ZIndex = 51
		ItemModels.preview(thumb, drag.itemId)
		drag.ghost = ghost
	end

	local function pointIn(guiObject, px, py)
		local pos, size = guiObject.AbsolutePosition, guiObject.AbsoluteSize
		return px >= pos.X and px <= pos.X + size.X and py >= pos.Y and py <= pos.Y + size.Y
	end

	local function updateDrag()
		if not drag then
			return
		end
		local w, h = Items.sizeFor(drag.itemId, drag.rotated)
		local px = mouse.X - (w * CELL) / 2
		local py = mouse.Y - (h * CELL) / 2
		drag.ghost.Position = UDim2.new(0, px, 0, py)

		drag.dropTarget = nil
		highlight.Visible = false
		resetEquipStrokes()

		if pointIn(gridScroll, mouse.X, mouse.Y) then
			local origin = itemsLayer.AbsolutePosition
			local gx = math.floor((px - origin.X) / CELL + 0.5)
			local gy = math.floor((py - origin.Y) / CELL + 0.5)
			local ok = canPlace(gx, gy, w, h, drag.itemId)
			highlight.Visible = true
			highlight.Position = UDim2.new(0, math.clamp(gx, 0, GRID_W - 1) * CELL, 0, math.clamp(gy, 0, GRID_H - 1) * CELL)
			highlight.Size = UDim2.new(0, w * CELL, 0, h * CELL)
			highlight.BackgroundColor3 = ok and COLORS.good or COLORS.bad
			if ok then
				drag.dropTarget = { containerId = "main", x = gx, y = gy, rotated = drag.rotated }
			end
		else
			local def = Items.get(drag.itemId)
			for slotName, slot in pairs(equipSlots) do
				if pointIn(slot.frame, mouse.X, mouse.Y) then
					local accepts = Items.slotAccepts(slotName, def)
						and (slot.entry == nil or sameRef(slot.entry, drag.from))
					slot.stroke.Color = accepts and COLORS.good or COLORS.bad
					slot.stroke.Thickness = 2.5
					if accepts then
						drag.dropTarget = { containerId = "equipment", x = SLOT_INDEX[slotName], y = 0 }
					end
					break
				end
			end
		end
	end

	local function endDrag(commit)
		if not drag then
			return
		end
		local from, target = drag.from, commit and drag.dropTarget or nil
		if dragStepConn then
			dragStepConn:Disconnect()
			dragStepConn = nil
		end
		destroyGhost()
		highlight.Visible = false
		resetEquipStrokes()
		if drag.sourceObj and drag.sourceObj.Parent then
			drag.sourceObj.BackgroundTransparency = drag.sourceTransparency or 0
		end
		drag = nil

		if target then
			task.spawn(function()
				if not moveItemRemote then
					return
				end
				pcall(function()
					-- On success the server pushes InventoryUpdated, re-rendering
					-- everything; on failure nothing changed, so nothing to undo.
					moveItemRemote:InvokeServer(from, target)
				end)
			end)
		end
	end

	local function beginDrag(entry, fromRef, sourceObj)
		if drag then
			return
		end
		drag = {
			itemId = entry.itemId,
			from = fromRef,
			rotated = entry.rotated == true,
			sourceObj = sourceObj,
			sourceTransparency = sourceObj.BackgroundTransparency,
		}
		sourceObj.BackgroundTransparency = 0.75
		buildGhost()
		updateDrag()
		dragStepConn = RunService.RenderStepped:Connect(updateDrag)
	end

	-- ---- rendering -----------------------------------------------------------
	local function createTile(entry)
		local w, h = Items.sizeFor(entry.itemId, entry.rotated)
		local def = Items.get(entry.itemId)

		local tile = Instance.new("TextButton")
		tile.Text = ""
		tile.AutoButtonColor = false
		tile:SetAttribute("itemTile", true)
		tile.Size = UDim2.new(0, w * CELL - 2, 0, h * CELL - 2)
		tile.Position = UDim2.new(0, entry.x * CELL + 1, 0, entry.y * CELL + 1)
		tile.BackgroundColor3 = COLORS.tile
		tile.BorderSizePixel = 0
		tile.ZIndex = 3
		tile.Parent = itemsLayer

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1
		stroke.Color = COLORS.tileStroke
		stroke.Parent = tile

		local thumb = makeViewport(tile)
		thumb.ZIndex = 4
		if not ItemModels.preview(thumb, entry.itemId) then
			local fallback = makeLabel(tile, def and def.name or entry.itemId, 11)
			fallback.Size = UDim2.new(1, -6, 1, -6)
			fallback.Position = UDim2.new(0, 3, 0, 3)
			fallback.TextWrapped = true
			fallback.ZIndex = 4
		end

		if entry.quantity > 1 then
			local qty = makeLabel(tile, tostring(entry.quantity), 13, COLORS.gold)
			qty.Size = UDim2.new(1, -6, 0, 14)
			qty.Position = UDim2.new(0, 3, 1, -16)
			qty.TextXAlignment = Enum.TextXAlignment.Right
			qty.ZIndex = 5
		end

		tile.MouseEnter:Connect(function()
			hovered = entry
			hoverLabel.Text = def and def.name or entry.itemId
		end)
		tile.MouseLeave:Connect(function()
			if hovered == entry then
				hovered = nil
				hoverLabel.Text = ""
			end
		end)
		tile.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				beginDrag(entry, { containerId = "main", x = entry.x, y = entry.y }, tile)
			end
		end)
	end

	local function render(inventory)
		if typeof(inventory) ~= "table" then
			inventory = {}
		end
		currentInventory = inventory
		hovered = nil
		hoverLabel.Text = ""

		-- A re-render mid-drag means the world changed under us; cancel cleanly.
		if drag then
			endDrag(false)
		end

		for _, child in ipairs(itemsLayer:GetChildren()) do
			if child:GetAttribute("itemTile") then
				child:Destroy()
			end
		end
		for _, slot in pairs(equipSlots) do
			slot.entry = nil
			slot.thumb:ClearAllChildren()
			slot.nameLabel.Visible = true
		end

		for _, entry in ipairs(inventory) do
			if entry.containerId == "main" then
				createTile(entry)
			elseif entry.containerId == "equipment" then
				local slotName = Items.EQUIPMENT_SLOTS[entry.x + 1]
				local slot = slotName and equipSlots[slotName]
				if slot then
					slot.entry = entry
					slot.nameLabel.Visible = false
					ItemModels.preview(slot.thumb, entry.itemId)
				end
			end
		end
	end

	-- Equipment slots: drag out to unequip (and hover shows the name).
	for slotName, slot in pairs(equipSlots) do
		slot.frame.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 and slot.entry then
				beginDrag(
					slot.entry,
					{ containerId = "equipment", x = SLOT_INDEX[slotName], y = 0 },
					slot.frame
				)
			end
		end)
		slot.frame.MouseEnter:Connect(function()
			if slot.entry then
				local def = Items.get(slot.entry.itemId)
				hoverLabel.Text = def and def.name or slot.entry.itemId
			end
		end)
		slot.frame.MouseLeave:Connect(function()
			hoverLabel.Text = ""
		end)
	end

	-- ---- effects panel -------------------------------------------------------
	local function refreshEffects()
		for _, child in ipairs(effectsList:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local now = Workspace:GetServerTimeNow()
		for name, value in pairs(player:GetAttributes()) do
			local effectId = Effects.idFromAttribute(name)
			local def = effectId and Effects.get(effectId)
			if def and typeof(value) == "number" and value > now then
				local row = Instance.new("Frame")
				row.Size = UDim2.new(1, 0, 0, 24)
				row.BackgroundTransparency = 1
				row.Parent = effectsList

				local icon = Instance.new("Frame")
				icon.Size = UDim2.new(0, 18, 0, 18)
				icon.Position = UDim2.new(0, 0, 0, 3)
				icon.BackgroundColor3 = def.color or COLORS.textDim
				icon.BorderSizePixel = 0
				icon.Parent = row

				local text = makeLabel(row, string.format("%s  %.0fs", def.name, value - now), 12)
				text.Size = UDim2.new(1, -26, 1, 0)
				text.Position = UDim2.new(0, 26, 0, 0)
				text.TextXAlignment = Enum.TextXAlignment.Left
			end
		end
	end

	player.AttributeChanged:Connect(function(name)
		if Effects.idFromAttribute(name) then
			refreshEffects()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if panel.Visible then
				refreshEffects()
			end
		end
	end)

	-- ---- gold ----------------------------------------------------------------
	local function updateGold()
		goldLabel.Text = "Gold: " .. tostring(player:GetAttribute("Gold") or 0)
	end
	player:GetAttributeChangedSignal("Gold"):Connect(updateGold)
	updateGold()

	-- ---- toggling ------------------------------------------------------------
	local function toggle()
		panel.Visible = not panel.Visible
		-- Free the cursor (via ShiftLockController) while the panel is open.
		ClientState.inventoryOpen = panel.Visible
		if not panel.Visible then
			endDrag(false)
		else
			refreshEffects()
		end
	end

	local openBtn = Instance.new("TextButton")
	openBtn.Name = "InventoryButton"
	openBtn.Size = UDim2.new(0, 120, 0, 34)
	-- Top-right corner: the bottom corners hold the health/mana orbs (HudUI).
	openBtn.Position = UDim2.new(1, -16, 0, 16)
	openBtn.AnchorPoint = Vector2.new(1, 0)
	openBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 160)
	openBtn.BorderSizePixel = 0
	openBtn.Font = Enum.Font.GothamBold
	openBtn.TextSize = 15
	openBtn.TextColor3 = Color3.new(1, 1, 1)
	openBtn.Text = "Inventory (B)"
	openBtn.Parent = gui

	openBtn.Activated:Connect(toggle)
	closeBtn.Activated:Connect(toggle)
	sortBtn.Activated:Connect(function()
		task.spawn(function()
			if sortRemote then
				pcall(function()
					sortRemote:InvokeServer()
				end)
			end
		end)
	end)

	-- Bound action (not raw InputBegan) so the key works without 3D-viewport
	-- keyboard focus; it still won't fire while a TextBox is captured.
	ContextActionService:BindAction("ToggleInventory", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.B)

	-- ---- drag/bind keys ------------------------------------------------------
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not panel.Visible then
			return
		end
		if drag and input.KeyCode == Enum.KeyCode.R then
			-- Rotate the carried item; the ghost and preview follow.
			drag.rotated = not drag.rotated
			buildGhost()
			updateDrag()
			return
		end
		if gameProcessed then
			return
		end
		local bindSlot = BIND_KEYS[input.KeyCode]
		if bindSlot and hovered then
			local def = Items.get(hovered.itemId)
			-- Decided rule: only tools and consumables are quick-bindable
			-- (weapons live on the reserved 1/2 keys).
			if def and (def.type == "tool" or def.type == "consumable") then
				HotbarBinds.set(bindSlot, hovered.itemId)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if drag and input.UserInputType == Enum.UserInputType.MouseButton1 then
			endDrag(true)
		end
	end)

	-- Wire up the remotes in the background so a slow/missing server can never
	-- block the keybind above.
	task.spawn(function()
		moveItemRemote = Remotes.getFunction("MoveItem")
		sortRemote = Remotes.getFunction("SortInventory")

		local inventoryUpdated = Remotes.get("InventoryUpdated")
		inventoryUpdated.OnClientEvent:Connect(render)

		local requestInventory = Remotes.getFunction("RequestInventory")
		local ok, inventory = pcall(function()
			return requestInventory:InvokeServer()
		end)
		if ok then
			render(inventory)
		end
	end)
end

return InventoryUI
