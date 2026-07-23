-- Player Market UI (Puesto de Mercado).
-- Dual tabs: "Comprar" (browse active listings) & "Vender" (post items from pack).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Items = require(Shared:WaitForChild("Items"))
local ItemGrid = require(script.Parent.ItemGrid)
local ItemTooltip = require(script.Parent.ItemTooltip)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local MarketUI = {}

local PANEL_W = 540
local PANEL_H = 460

function MarketUI.start()
	local getListings = Remotes.getFunction("GetMarketListings")
	local createListing = Remotes.getFunction("CreateMarketListing")
	local buyItem = Remotes.getFunction("BuyMarketItem")
	local requestInventory = Remotes.getFunction("RequestInventory")

	local gui = Instance.new("ScreenGui")
	gui.Name = "MarketUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 7
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

	local title = UIKit.titleBar(panel, "Puesto de Mercado", 36)

	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -6, 0, 5)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	-- Tab Switcher: "Comprar" vs "Vender"
	local tabBuy = UIKit.primaryButton(panel, "Comprar")
	tabBuy.Size = UDim2.new(0, 120, 0, 28)
	tabBuy.Position = UDim2.new(0, 12, 0, 46)

	local tabSell = UIKit.ghostButton(panel, "Vender")
	tabSell.Size = UDim2.new(0, 120, 0, 28)
	tabSell.Position = UDim2.new(0, 140, 0, 46)

	-- Container Frames
	local buyContainer = Instance.new("Frame")
	buyContainer.Size = UDim2.new(1, -24, 1, -90)
	buyContainer.Position = UDim2.new(0, 12, 0, 80)
	buyContainer.BackgroundTransparency = 1
	buyContainer.Parent = panel

	local sellContainer = Instance.new("Frame")
	sellContainer.Size = UDim2.new(1, -24, 1, -90)
	sellContainer.Position = UDim2.new(0, 12, 0, 80)
	sellContainer.BackgroundTransparency = 1
	sellContainer.Visible = false
	sellContainer.Parent = panel

	-- ---- BUY TAB -----------------------------------------------------------
	local buyScroll = Instance.new("ScrollingFrame")
	buyScroll.Size = UDim2.new(1, 0, 1, 0)
	buyScroll.BackgroundColor3 = Theme.Semantic.SurfaceWell
	buyScroll.BorderSizePixel = 0
	buyScroll.ScrollBarThickness = 6
	buyScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	buyScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	buyScroll.Parent = buyContainer

	local buyLayout = Instance.new("UIListLayout")
	buyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buyLayout.Padding = UDim.new(0, 4)
	buyLayout.Parent = buyScroll

	local buyPadding = Instance.new("UIPadding")
	buyPadding.PaddingTop = UDim.new(0, 6)
	buyPadding.PaddingLeft = UDim.new(0, 6)
	buyPadding.PaddingRight = UDim.new(0, 6)
	buyPadding.PaddingBottom = UDim.new(0, 6)
	buyPadding.Parent = buyScroll

	local function refreshBuyListings()
		for _, child in ipairs(buyScroll:GetChildren()) do
			if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
				child:Destroy()
			end
		end

		local listings = getListings:InvokeServer()
		if typeof(listings) ~= "table" then
			return
		end

		for _, item in ipairs(listings) do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 36)
			row.BackgroundColor3 = Theme.Color.Ink900
			row.BackgroundTransparency = 0.2
			row.BorderSizePixel = 0
			row.Parent = buyScroll

			local def = Items.get(item.itemId)
			local name = def and def.name or item.itemId
			local totalCost = item.quantity * item.pricePerUnit

			local infoLabel = UIKit.label(
				row,
				string.format("%s x%d — %d Oro c/u (Total: %d)", name, item.quantity, item.pricePerUnit, totalCost),
				12,
				Theme.Semantic.TextBody
			)
			infoLabel.Size = UDim2.new(1, -170, 1, 0)
			infoLabel.Position = UDim2.new(0, 8, 0, 0)

			local sellerLabel = UIKit.label(row, "Vendedor: " .. tostring(item.sellerName), 11, Theme.Semantic.TextMuted)
			sellerLabel.Size = UDim2.new(0, 100, 1, 0)
			sellerLabel.Position = UDim2.new(1, -165, 0, 0)

			local buyBtn = UIKit.primaryButton(row, "Comprar")
			buyBtn.Size = UDim2.new(0, 60, 0, 24)
			buyBtn.Position = UDim2.new(1, -64, 0.5, -12)
			buyBtn.Activated:Connect(function()
				buyItem:InvokeServer(item.id)
				task.wait(0.3)
				refreshBuyListings()
			end)
		end
	end

	-- ---- SELL TAB ----------------------------------------------------------
	local packHeader = UIKit.label(sellContainer, "Tu Inventario", 12, Theme.Semantic.TextMuted)
	packHeader.Size = UDim2.new(0, 200, 0, 16)
	packHeader.Position = UDim2.new(0, 0, 0, 0)

	local packGrid = ItemGrid.create(sellContainer, { columns = 6, visibleRows = 8, canvasRows = 8 })
	packGrid.frame.Position = UDim2.new(0, 0, 0, 20)

	local sellForm = Instance.new("Frame")
	sellForm.Size = UDim2.new(0, 240, 1, -20)
	sellForm.Position = UDim2.new(1, -240, 0, 20)
	sellForm.BackgroundColor3 = Theme.Semantic.SurfaceWell
	sellForm.BorderSizePixel = 0
	sellForm.Parent = sellContainer

	local formTitle = UIKit.label(sellForm, "Publicar Oferta", 13, Theme.Semantic.TextTitle, Theme.Font.DisplayBold)
	formTitle.Size = UDim2.new(1, -16, 0, 24)
	formTitle.Position = UDim2.new(0, 8, 0, 8)

	local selectedItemLabel = UIKit.label(sellForm, "Selecciona un ítem de tu inventario", 11, Theme.Semantic.TextMuted)
	selectedItemLabel.Size = UDim2.new(1, -16, 0, 20)
	selectedItemLabel.Position = UDim2.new(0, 8, 0, 36)

	local qtyLabel = UIKit.label(sellForm, "Cantidad:", 11, Theme.Semantic.TextBody)
	qtyLabel.Size = UDim2.new(0, 80, 0, 20)
	qtyLabel.Position = UDim2.new(0, 8, 0, 68)

	local qtyBox = Instance.new("TextBox")
	qtyBox.Size = UDim2.new(0, 120, 0, 24)
	qtyBox.Position = UDim2.new(0, 100, 0, 66)
	qtyBox.BackgroundColor3 = Theme.Color.Ink900
	qtyBox.BorderSizePixel = 0
	qtyBox.FontFace = Theme.Font.BodyBold
	qtyBox.TextSize = 12
	qtyBox.TextColor3 = Theme.Semantic.TextBody
	qtyBox.Text = "1"
	qtyBox.Parent = sellForm

	local priceLabel = UIKit.label(sellForm, "Precio/Unidad (Oro):", 11, Theme.Semantic.TextBody)
	priceLabel.Size = UDim2.new(0, 120, 0, 20)
	priceLabel.Position = UDim2.new(0, 8, 0, 104)

	local priceBox = Instance.new("TextBox")
	priceBox.Size = UDim2.new(0, 100, 0, 24)
	priceBox.Position = UDim2.new(0, 130, 0, 102)
	priceBox.BackgroundColor3 = Theme.Color.Ink900
	priceBox.BorderSizePixel = 0
	priceBox.FontFace = Theme.Font.BodyBold
	priceBox.TextSize = 12
	priceBox.TextColor3 = Theme.Semantic.Currency
	priceBox.Text = "10"
	priceBox.Parent = sellForm

	local postBtn = UIKit.primaryButton(sellForm, "Publicar en Mercado")
	postBtn.Size = UDim2.new(1, -16, 0, 32)
	postBtn.Position = UDim2.new(0, 8, 1, -40)

	local selectedEntry = nil

	packGrid.callbacks = {
		onClick = function(entry)
			selectedEntry = entry
			local def = Items.get(entry.itemId)
			selectedItemLabel.Text = string.format("%s (Disponibles: %d)", def and def.name or entry.itemId, entry.quantity or 1)
			qtyBox.Text = tostring(entry.quantity or 1)
		end,
		onHover = function(entry)
			if entry then
				tooltip.schedule(entry, {})
			else
				tooltip.hide()
			end
		end,
	}

	local function refreshSellPack()
		local entries = requestInventory:InvokeServer()
		if typeof(entries) == "table" then
			local mainList = {}
			for _, e in ipairs(entries) do
				if e.containerId == "main" then
					table.insert(mainList, e)
				end
			end
			packGrid.render(mainList)
		end
	end

	postBtn.Activated:Connect(function()
		if not selectedEntry then
			return
		end
		local qty = tonumber(qtyBox.Text) or 1
		local price = tonumber(priceBox.Text) or 1
		createListing:InvokeServer({
			itemId = selectedEntry.itemId,
			quantity = qty,
			pricePerUnit = price,
		})
		selectedEntry = nil
		selectedItemLabel.Text = "Selecciona un ítem de tu inventario"
		task.wait(0.3)
		refreshSellPack()
	end)

	-- Tab Switcher Actions
	tabBuy.Activated:Connect(function()
		buyContainer.Visible = true
		sellContainer.Visible = false
		UIKit.stylePrimaryButton(tabBuy)
		UIKit.styleGhostButton(tabSell)
		refreshBuyListings()
	end)

	tabSell.Activated:Connect(function()
		buyContainer.Visible = false
		sellContainer.Visible = true
		UIKit.styleGhostButton(tabBuy)
		UIKit.stylePrimaryButton(tabSell)
		refreshSellPack()
	end)

	local function setOpen(open)
		panel.Visible = open
		Sfx.play(open and "panelOpen" or "panelClose")
		if open then
			refreshBuyListings()
		else
			tooltip.hide()
		end
	end

	closeBtn.Activated:Connect(function()
		setOpen(false)
	end)

	function MarketUI.open()
		setOpen(true)
	end

	function MarketUI.close()
		setOpen(false)
	end

	Remotes.get("OpenMarket").OnClientEvent:Connect(function()
		MarketUI.open()
	end)
end

return MarketUI
