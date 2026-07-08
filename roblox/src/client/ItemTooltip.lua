-- The §6.5 item tooltip card (name + Lv, rarity·kind + size, divider, stat
-- line, INERT warning, trait grants with mini hexes, flavor), extracted from
-- InventoryUI so the store screen shows the exact same card. Hosts create
-- one instance per ScreenGui:
--
--   local tooltip = ItemTooltip.create(gui, guard)
--   tooltip.schedule(entry, lines)  -- show after the hover delay
--   tooltip.hide()
--
-- `guard` (optional) runs when the delay fires — the host says whether
-- showing still makes sense (panel open, not mid-drag). `lines` (optional)
-- appends host-specific rows under the card ({ { text, color? } }) — the
-- store uses it for price and "not traded here" hints. The tooltip appears
-- instantly at the cursor with no tween so it tracks cleanly (UI.md §11).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Traits = require(Shared:WaitForChild("Traits"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Icons = require(Shared:WaitForChild("Icons"))
local Spells = require(Shared:WaitForChild("Spells"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local ItemTooltip = {}

ItemTooltip.DELAY = 0.35 -- rest the cursor on an item this long to inspect
ItemTooltip.WIDTH = 214

local TYPE_NAMES = {
	tool = "Tool",
	resource = "Resource",
	ring = "Ring",
	consumable = "Consumable",
	backpack = "Backpack",
}
local PRETTY_SLOT = { head = "Head", chest = "Chest", hands = "Hands", legs = "Legs", feet = "Feet" }

-- "Chest Armor" / "Melee Weapon" / "Ring" — the §6.5 kind line.
local function kindFor(def)
	if def.type == "armor" then
		return (PRETTY_SLOT[def.slot] or "") .. " Armor"
	end
	if def.type == "weapon" then
		return (def.weaponType == "ranged" and "Ranged" or "Melee") .. " Weapon"
	end
	return TYPE_NAMES[def.type] or def.type
end

local function makeLabel(parent, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font or Theme.Font.BodyBold
	label.TextSize = size
	label.TextColor3 = color or Theme.Semantic.TextBody
	label.Text = text
	label.Parent = parent
	return label
end

function ItemTooltip.create(gui, guard)
	local tooltip = Instance.new("Frame")
	tooltip.BackgroundColor3 = Theme.Semantic.PanelTop
	tooltip.BorderSizePixel = 0
	tooltip.AutomaticSize = Enum.AutomaticSize.Y
	tooltip.Size = UDim2.new(0, ItemTooltip.WIDTH, 0, 0)
	tooltip.Visible = false
	tooltip.ZIndex = 60
	tooltip.Parent = gui
	UIKit.autoScale(tooltip) -- content scales; its Position stays screen-space

	local tooltipGradient = Instance.new("UIGradient")
	tooltipGradient.Rotation = 90
	tooltipGradient.Color = ColorSequence.new(Theme.Semantic.PanelTop, Theme.Semantic.PanelBot)
	tooltipGradient.Parent = tooltip

	-- Retinted to the hovered item's rarity when the tooltip shows (§6.5).
	local tooltipStroke = Instance.new("UIStroke")
	tooltipStroke.Thickness = 1
	tooltipStroke.Color = Theme.Semantic.BorderSlot
	tooltipStroke.Parent = tooltip

	local tooltipPad = Instance.new("UIPadding")
	tooltipPad.PaddingTop = UDim.new(0, 8)
	tooltipPad.PaddingBottom = UDim.new(0, 8)
	tooltipPad.PaddingLeft = UDim.new(0, 10)
	tooltipPad.PaddingRight = UDim.new(0, 10)
	tooltipPad.Parent = tooltip

	local tooltipLayout = Instance.new("UIListLayout")
	tooltipLayout.Padding = UDim.new(0, 4)
	tooltipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tooltipLayout.Parent = tooltip

	-- Rows are rebuilt per hover; UI components (gradient/stroke/padding/
	-- layout) are not GuiObjects, so the clear below leaves them alone.
	local tooltipOrder = 0
	local function tooltipRow(height)
		tooltipOrder += 1
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, height)
		row.BackgroundTransparency = 1
		row.LayoutOrder = tooltipOrder
		row.ZIndex = 61
		row.Parent = tooltip
		return row
	end

	local function tooltipText(parent, text, size, color, font)
		local label = makeLabel(parent, text, size, color, font)
		label.ZIndex = 61
		label.TextXAlignment = Enum.TextXAlignment.Left
		return label
	end

	-- Tiny solid hexagon + dark glyph for a trait-grant row (falls back to
	-- the def's emoji while the hex/glyph assets aren't uploaded).
	local function miniHex(parent, id, color, emoji)
		local hexImage = Icons.image("Hexagon")
		local glyphImage = Icons.forTrait(id)
		if hexImage and glyphImage then
			local badge = Instance.new("Frame")
			badge.Size = UDim2.new(0, 16, 0, 16)
			badge.BackgroundTransparency = 1
			badge.ZIndex = 61
			badge.Parent = parent

			local hex = Instance.new("ImageLabel")
			hex.Size = UDim2.new(1, 0, 1, 0)
			hex.BackgroundTransparency = 1
			hex.Image = hexImage
			hex.ScaleType = Enum.ScaleType.Fit
			hex.ImageColor3 = color
			hex.ZIndex = 61
			hex.Parent = badge

			local glyph = Instance.new("ImageLabel")
			glyph.Size = UDim2.new(0.6, 0, 0.6, 0)
			glyph.Position = UDim2.new(0.2, 0, 0.2, 0)
			glyph.BackgroundTransparency = 1
			glyph.Image = glyphImage
			glyph.ScaleType = Enum.ScaleType.Fit
			glyph.ImageColor3 = Theme.Color.Ink800
			glyph.ZIndex = 62
			glyph.Parent = badge
			return badge
		end
		local label = makeLabel(parent, emoji or "✦", 12, color)
		label.Size = UDim2.new(0, 16, 0, 16)
		label.ZIndex = 61
		return label
	end

	-- Rebuilds the tooltip rows for an entry (§6.5: name + Lv, rarity·kind +
	-- size, divider, stat line, trait grants with mini hexes, flavor), then
	-- any host-provided extra lines.
	local function buildTooltip(entry, lines)
		for _, child in ipairs(tooltip:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		tooltipOrder = 0

		local function extraLines()
			if not lines then
				return
			end
			for _, extra in ipairs(lines) do
				local row = tooltipRow(16)
				local label = tooltipText(row, extra.text, Theme.Text.Sm, extra.color or Theme.Semantic.TextMuted)
				label.Size = UDim2.new(1, 0, 1, 0)
			end
		end

		local def = Items.get(entry.itemId)
		local rarity = Rarity.forEntry(entry, def)
		tooltipStroke.Color = rarity.color -- frame tints with the tier
		if not def then
			local row = tooltipRow(20)
			local name = tooltipText(row, entry.itemId, Theme.Text.Item, rarity.textColor, Theme.Font.DisplayBold)
			name.Size = UDim2.new(1, 0, 1, 0)
			extraLines()
			return
		end

		local itemLevel, itemTraits = Traits.entryInfo(entry, def)

		local header = tooltipRow(20)
		local name = tooltipText(header, def.name, Theme.Text.Item, rarity.textColor, Theme.Font.DisplayBold)
		name.Size = UDim2.new(1, -36, 1, 0)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		if itemLevel > 0 then
			local lv = tooltipText(header, ("Lv %d"):format(itemLevel), Theme.Text.Sm, Theme.Semantic.TextSecondary)
			lv.Size = UDim2.new(0, 34, 1, 0)
			lv.Position = UDim2.new(1, -34, 0, 0)
			lv.TextXAlignment = Enum.TextXAlignment.Right
		end

		local sub = tooltipRow(14)
		local kind =
			tooltipText(sub, rarity.name .. " · " .. kindFor(def), Theme.Text.Xs, rarity.textColor, Theme.Font.Body)
		kind.Size = UDim2.new(1, -54, 1, 0)
		kind.TextTransparency = 0.25
		local w, h = Items.sizeFor(entry.itemId, false)
		local sizeLabel =
			tooltipText(sub, ("Size %d×%d"):format(w, h), Theme.Text.Xs, Theme.Semantic.TextMuted, Theme.Font.Body)
		sizeLabel.Size = UDim2.new(0, 52, 1, 0)
		sizeLabel.Position = UDim2.new(1, -52, 0, 0)
		sizeLabel.TextXAlignment = Enum.TextXAlignment.Right

		local dividerRow = tooltipRow(5)
		local divider = Instance.new("Frame")
		divider.Size = UDim2.new(1, 0, 0, 1)
		divider.Position = UDim2.new(0, 0, 0.5, 0)
		divider.BackgroundColor3 = Theme.Semantic.BorderDivider
		divider.BorderSizePixel = 0
		divider.ZIndex = 61
		divider.Parent = dividerRow

		-- One strong stat line, mock-style: "Damage +10 · Reach 10".
		local parts = {}
		if def.damage then
			parts[#parts + 1] = ("Damage +%d"):format(def.damage)
		end
		if def.reach then
			parts[#parts + 1] = ("Reach %d"):format(def.reach)
		end
		if def.manaCost then
			parts[#parts + 1] = ("Mana %d"):format(def.manaCost)
		end
		if def.gatherPower then
			parts[#parts + 1] = ("Gather +%d"):format(def.gatherPower)
		end
		if def.stackable then
			parts[#parts + 1] = ("Stack %d/%d"):format(entry.quantity, def.maxStack)
		end
		if #parts > 0 then
			local statRow = tooltipRow(16)
			local stats = tooltipText(statRow, table.concat(parts, "  ·  "), Theme.Text.Sm, Theme.Semantic.TextStrong)
			stats.Size = UDim2.new(1, 0, 1, 0)
		end

		local playerLevel = player:GetAttribute("Level") or 1
		if itemLevel > playerLevel then
			local inertRow = tooltipRow(14)
			local inert = tooltipText(
				inertRow,
				("INERT — needs class Lv %d"):format(itemLevel),
				Theme.Text.Xs,
				Theme.Color.Blood400
			)
			inert.Size = UDim2.new(1, 0, 1, 0)
		end

		-- Trait grants, one row each with a mini hex (schools first — they
		-- gate spells).
		if itemTraits then
			local function grantRow(id, displayName, color, emoji, points)
				local row = tooltipRow(18)
				local badge = miniHex(row, id, color, emoji)
				badge.Position = UDim2.new(0, 0, 0.5, -8)
				local label =
					tooltipText(row, ("%s +%d"):format(displayName, points), Theme.Text.Sm, Theme.Semantic.TextStrong)
				label.Size = UDim2.new(1, -22, 1, 0)
				label.Position = UDim2.new(0, 22, 0, 0)
			end
			for _, schoolId in ipairs(Spells.schoolOrder) do
				local points = itemTraits[schoolId]
				if points then
					local school = Spells.schools[schoolId]
					grantRow(schoolId, school.name, school.color, school.icon, points)
				end
			end
			for _, traitId in ipairs(Traits.order) do
				local points = itemTraits[traitId]
				if points then
					local traitDef = Traits.get(traitId)
					grantRow(
						traitId,
						traitDef and traitDef.name or traitId,
						traitDef and traitDef.color or Theme.Semantic.TextBody,
						traitDef and traitDef.icon,
						points
					)
				end
			end
		end

		-- Flavor, italic and quoted (only when the def carries one).
		if typeof(def.flavor) == "string" and def.flavor ~= "" then
			local flavorRow = tooltipRow(0)
			flavorRow.AutomaticSize = Enum.AutomaticSize.Y
			local flavor = tooltipText(
				flavorRow,
				"“" .. def.flavor .. "”",
				Theme.Text.Xs,
				Theme.Semantic.TextMuted,
				Theme.Font.BodyItalic
			)
			flavor.Size = UDim2.new(1, 0, 0, 0)
			flavor.AutomaticSize = Enum.AutomaticSize.Y
			flavor.TextWrapped = true
		end

		extraLines()
	end

	local hoverToken = 0 -- invalidates pending tooltip timers

	local handle = {}

	function handle.hide()
		hoverToken += 1
		tooltip.Visible = false
	end

	function handle.schedule(entry, lines)
		hoverToken += 1
		local token = hoverToken
		task.delay(ItemTooltip.DELAY, function()
			if token ~= hoverToken or (guard and not guard()) then
				return
			end
			buildTooltip(entry, lines)
			local s = UIKit.scaleFactor() -- rendered tooltip size is design px × scale
			local guiSize = gui.AbsoluteSize
			tooltip.Position = UDim2.new(
				0,
				math.min(mouse.X + 14, guiSize.X - (ItemTooltip.WIDTH + 16) * s),
				0,
				math.min(mouse.Y + 10, guiSize.Y - 220 * s)
			)
			tooltip.Visible = true
		end)
	end

	return handle
end

return ItemTooltip
