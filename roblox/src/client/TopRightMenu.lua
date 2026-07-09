-- The shared top-right HUD stack: one auto-scaled column pinned to the
-- top-right corner holding the window buttons (Inventory/Character/Craft),
-- the options gear beside the top row, and the trait-tracker rail below —
-- one layout context, so rows never overlap or drift out of alignment.
--
-- Rows sort by the `order` passed in (buttons 1..9, rail 50). The container
-- is built lazily by the FIRST consumer — the trait rail, started early in
-- init.client.lua — so the big windows' ScreenGuis are created later and
-- draw above the stack wherever they overlap it.

local Players = game:GetService("Players")

local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local TopRightMenu = {}

local INSET = 16 -- from the screen's top/right edges
local WIDTH = 120 -- button-column width; wider rows overflow leftward

local container -- built on first use
local buttonRows = {} -- [order] = button; addAside anchors to the topmost

local function ensureContainer()
	if container then
		return container
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "TopRightMenu"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	container = Instance.new("Frame")
	container.Size = UDim2.new(0, WIDTH, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.AnchorPoint = Vector2.new(1, 0)
	container.Position = UDim2.new(1, -INSET, 0, INSET)
	container.BackgroundTransparency = 1
	container.Parent = gui
	UIKit.autoScale(container) -- top-right anchored: grows leftward/downward (§9)

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, 6)
	layout.Parent = container

	return container
end

-- A full-width ghost-button row (the window toggles). The caller connects
-- Activated and may retint/resize text.
function TopRightMenu.addButton(text, order, height)
	local button = UIKit.ghostButton(ensureContainer(), text)
	button.Size = UDim2.new(1, 0, 0, height or 30)
	button.LayoutOrder = order
	buttonRows[order] = button
	return button
end

-- A small square button hanging LEFT of the topmost button row (the gear).
-- As the row's child it scales and moves with the stack; sitting outside
-- the row's rect it doesn't trigger the row's own hover.
function TopRightMenu.addAside(text)
	local anchor, anchorOrder
	for order, button in pairs(buttonRows) do
		if not anchorOrder or order < anchorOrder then
			anchor, anchorOrder = button, order
		end
	end
	if not anchor then
		-- No button rows yet (init-order change): a square row of its own.
		local button = UIKit.ghostButton(ensureContainer(), text)
		button.Size = UDim2.new(0, 34, 0, 34)
		button.LayoutOrder = 0
		return button
	end

	local button = UIKit.ghostButton(anchor, text)
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(0, -6, 0, 0)
	button.Size = UDim2.new(0, anchor.Size.Y.Offset, 1, 0)
	return button
end

-- A transparent auto-height row hosting arbitrary content (the trait rail
-- mounts its panel here). Content wider than the column overflows leftward.
function TopRightMenu.addHost(order)
	local host = Instance.new("Frame")
	host.Size = UDim2.new(1, 0, 0, 0)
	host.AutomaticSize = Enum.AutomaticSize.Y
	host.BackgroundTransparency = 1
	host.LayoutOrder = order
	host.Parent = ensureContainer()
	return host
end

return TopRightMenu
