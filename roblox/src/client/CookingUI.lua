-- Cooking & Alchemy UI (Olla de Campamento).
-- Displays available recipes, required ingredients, and cooks dishes / brews potions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Items = require(Shared:WaitForChild("Items"))
local CookingRecipes = require(Shared:WaitForChild("CookingRecipes"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local CookingUI = {}

local PANEL_W = 460
local PANEL_H = 380

function CookingUI.start()
	local cookRemote = Remotes.getFunction("CookRecipe")
	local requestInventory = Remotes.getFunction("RequestInventory")

	local gui = Instance.new("ScreenGui")
	gui.Name = "CookingUI"
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

	local title = UIKit.titleBar(panel, "Olla de Cocina & Alquimia", 36)

	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -6, 0, 5)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -24, 1, -60)
	scroll.Position = UDim2.new(0, 12, 0, 48)
	scroll.BackgroundColor3 = Theme.Semantic.SurfaceWell
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = scroll

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = scroll

	local function countItemInInventory(inv, itemId)
		local count = 0
		for _, e in ipairs(inv) do
			if e.itemId == itemId then
				count += (e.quantity or 1)
			end
		end
		return count
	end

	local function refresh()
		for _, child in ipairs(scroll:GetChildren()) do
			if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
				child:Destroy()
			end
		end

		local inv = requestInventory:InvokeServer() or {}

		for _, recipe in ipairs(CookingRecipes.list()) do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 54)
			row.BackgroundColor3 = Theme.Color.Ink900
			row.BackgroundTransparency = 0.2
			row.BorderSizePixel = 0
			row.Parent = scroll

			local def = Items.get(recipe.result.itemId)
			local name = def and def.name or recipe.result.itemId

			local titleLabel = UIKit.label(row, name, 13, Theme.Semantic.TextTitle, Theme.Font.DisplayBold)
			titleLabel.Size = UDim2.new(0, 180, 0, 20)
			titleLabel.Position = UDim2.new(0, 8, 0, 4)

			-- Ingredients list
			local ingParts = {}
			local canCook = true
			for _, ing in ipairs(recipe.ingredients) do
				local ingDef = Items.get(ing.itemId)
				local ingName = ingDef and ingDef.name or ing.itemId
				local hasCount = countItemInInventory(inv, ing.itemId)
				if hasCount < ing.quantity then
					canCook = false
				end
				table.insert(ingParts, string.format("%s: %d/%d", ingName, hasCount, ing.quantity))
			end

			local ingLabel = UIKit.label(row, table.concat(ingParts, "  |  "), 11, canCook and Theme.Semantic.Good or Theme.Semantic.TextMuted)
			ingLabel.Size = UDim2.new(1, -120, 0, 20)
			ingLabel.Position = UDim2.new(0, 8, 0, 26)

			local cookBtn = canCook and UIKit.primaryButton(row, "Preparar") or UIKit.ghostButton(row, "Faltan Ítems")
			cookBtn.Size = UDim2.new(0, 90, 0, 28)
			cookBtn.Position = UDim2.new(1, -98, 0.5, -14)

			if canCook then
				cookBtn.Activated:Connect(function()
					cookRemote:InvokeServer(recipe.id)
					task.wait(0.3)
					refresh()
				end)
			end
		end
	end

	local function setOpen(open)
		panel.Visible = open
		Sfx.play(open and "panelOpen" or "panelClose")
		if open then
			refresh()
		end
	end

	closeBtn.Activated:Connect(function()
		setOpen(false)
	end)

	function CookingUI.open()
		setOpen(true)
	end

	function CookingUI.close()
		setOpen(false)
	end

	Remotes.get("OpenCooking").OnClientEvent:Connect(function()
		CookingUI.open()
	end)
end

return CookingUI
