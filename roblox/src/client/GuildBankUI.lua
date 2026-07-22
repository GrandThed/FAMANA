-- Guild Bank screen: two 2D spatial grid panes — GUILD BANK (left) and YOUR PACK (right),
-- reusing the exact same ItemGrid component as the inventory and camp chest.
-- Opens when interacting with a planted "Cofre de Gremio" in your camp.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Items = require(Shared:WaitForChild("Items"))
local ClientState = require(script.Parent.ClientState)
local ItemGrid = require(script.Parent.ItemGrid)
local ItemTooltip = require(script.Parent.ItemTooltip)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local GuildBankUI = {}

local CELL = Theme.Size.Cell
local PACK_COLS = Config.inventoryGrid.width
local PACK_ROWS = Config.inventoryGrid.height
local BANK_COLS = 6
local BANK_ROWS = 6
local VISIBLE_ROWS = 12

local BANK_X = 12
local PACK_GAP = 24
local PANE_TOP = 76

function GuildBankUI.start()
	local requestInventory = Remotes.getFunction("RequestInventory")
	local requestBank = Remotes.getFunction("RequestGuildBank")
	local bankDeposit = Remotes.get("GuildBankDeposit")
	local bankWithdraw = Remotes.get("GuildBankWithdraw")

	local gui = Instance.new("ScreenGui")
	gui.Name = "GuildBankUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Visible = false
	panel.Parent = gui
	UIKit.stylePanel(panel)
	UIKit.addShadow(panel)
	UIKit.autoScale(panel)

	local title = UIKit.titleBar(panel, "Banco de Gremio", 36)

	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -6, 0, 5)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	local statusLabel = UIKit.label(panel, "", 12, Theme.Semantic.Danger, Theme.Font.Body)
	statusLabel.Size = UDim2.new(0, 360, 0, 18)
	statusLabel.Position = UDim2.new(0, BANK_X, 0, PANE_TOP - 22)
	statusLabel.TextWrapped = true

	local function header(text, x, w)
		local label = UIKit.sectionLabel(panel, text)
		label.Size = UDim2.new(0, w, 0, 18)
		label.Position = UDim2.new(0, x, 0, 52)
		label.TextXAlignment = Enum.TextXAlignment.Left
		return label
	end

	local bankItems = {}
	local inventory = {}
	local busy = false

	local bankGrid, packGrid
	local tooltip = ItemTooltip.create(gui, function()
		return panel.Visible
	end)

	local function setStatus(text)
		statusLabel.Text = text or ""
	end

	-- Convert flat bank items [{ itemId, quantity }, ...] into grid-placed items
	local function layoutBankGrid(rawItems)
		local entries = {}
		local curX, curY = 0, 0
		for _, item in ipairs(rawItems) do
			local def = Items.get(item.itemId)
			local w = (def and def.size and def.size[1]) or 1
			local h = (def and def.size and def.size[2]) or 1
			if curX + w > BANK_COLS then
				curX = 0
				curY = curY + 1
			end
			table.insert(entries, {
				id = "bank_" .. item.itemId,
				itemId = item.itemId,
				quantity = item.quantity,
				x = curX,
				y = curY,
				meta = nil,
			})
			curX = curX + w
		end
		return entries
	end

	local function packEntries()
		local list = {}
		for _, entry in ipairs(inventory) do
			if entry.containerId == "main" then
				table.insert(list, entry)
			end
		end
		return list
	end

	local function refreshBank()
		bankGrid.render(layoutBankGrid(bankItems))
	end

	local function refreshPack()
		packGrid.render(packEntries())
	end

	local function onPackClick(entry)
		if busy then
			return
		end
		if entry.meta then
			setStatus("No se pueden depositar ítems con atributos únicos.")
			return
		end
		busy = true
		setStatus(nil)
		bankDeposit:FireServer({ itemId = entry.itemId, quantity = entry.quantity })
		task.wait(0.35)
		local raw = requestBank:InvokeServer()
		if typeof(raw) == "table" then
			bankItems = raw
			refreshBank()
		end
		local inv = requestInventory:InvokeServer()
		if typeof(inv) == "table" then
			inventory = inv
			refreshPack()
		end
		busy = false
		Sfx.play("uiClick")
	end

	local function onBankClick(entry)
		if busy then
			return
		end
		local iAmPrivileged = player:GetAttribute("GuildLeader") == true or player:GetAttribute("GuildOfficer") == true
		if not iAmPrivileged then
			setStatus("Solo los oficiales o líderes pueden retirar del banco.")
			return
		end
		busy = true
		setStatus(nil)
		bankWithdraw:FireServer({ itemId = entry.itemId, quantity = entry.quantity })
		task.wait(0.35)
		local raw = requestBank:InvokeServer()
		if typeof(raw) == "table" then
			bankItems = raw
			refreshBank()
		end
		local inv = requestInventory:InvokeServer()
		if typeof(inv) == "table" then
			inventory = inv
			refreshPack()
		end
		busy = false
		Sfx.play("uiClick")
	end

	local function hoverTip(entry)
		if not entry then
			tooltip.hide()
			return
		end
		tooltip.schedule(entry, {})
	end

	-- ---- Panes -------------------------------------------------------------
	header("Banco de Gremio", BANK_X + 2, 200)
	bankGrid = ItemGrid.create(panel, { columns = BANK_COLS, visibleRows = BANK_ROWS, canvasRows = BANK_ROWS })
	bankGrid.frame.Position = UDim2.new(0, BANK_X, 0, PANE_TOP)
	bankGrid.callbacks = { onClick = onBankClick, onHover = hoverTip }

	local packX = BANK_X + BANK_COLS * CELL + 8 + PACK_GAP
	header("Tu Inventario", packX + 2, 200)
	packGrid = ItemGrid.create(panel, { columns = PACK_COLS, visibleRows = VISIBLE_ROWS, canvasRows = PACK_ROWS })
	packGrid.frame.Position = UDim2.new(0, packX, 0, PANE_TOP)
	packGrid.callbacks = { onClick = onPackClick, onHover = hoverTip }

	local panelW = packX + PACK_COLS * CELL + 8 + 12
	local panelH = PANE_TOP + math.max(BANK_ROWS, VISIBLE_ROWS) * CELL + 20
	panel.Size = UDim2.new(0, panelW, 0, panelH)

	-- ---- Lifecycle ---------------------------------------------------------
	local isOpen = false

	local function render()
		local raw = requestBank:InvokeServer()
		if typeof(raw) == "table" then
			bankItems = raw
			refreshBank()
		end
		local inv = requestInventory:InvokeServer()
		if typeof(inv) == "table" then
			inventory = inv
			refreshPack()
		end
	end

	local function setOpen(open)
		isOpen = open
		panel.Visible = open
		Sfx.play(open and "panelOpen" or "panelClose")
		if not open then
			tooltip.hide()
		else
			setStatus(nil)
			render()
		end
	end

	closeBtn.Activated:Connect(function()
		setOpen(false)
	end)

	function GuildBankUI.open()
		if not player:GetAttribute("GuildId") then
			return
		end
		setOpen(true)
	end

	function GuildBankUI.close()
		setOpen(false)
	end

	player:GetAttributeChangedSignal("GuildId"):Connect(function()
		if isOpen and not player:GetAttribute("GuildId") then
			setOpen(false)
		end
	end)

	Remotes.get("OpenGuildBank").OnClientEvent:Connect(function()
		GuildBankUI.open()
	end)

	Remotes.get("InventoryUpdated").OnClientEvent:Connect(function(entries)
		if isOpen and typeof(entries) == "table" then
			inventory = entries
			refreshPack()
		end
	end)
end

return GuildBankUI
