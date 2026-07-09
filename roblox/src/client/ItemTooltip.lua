-- The §6.5 item tooltip card (name + Lv, rarity·kind + size, divider, stat
-- line, INERT warning, trait grants with mini hexes, flavor), extracted from
-- InventoryUI so the store screen shows the exact same card. Hosts create
-- one instance per ScreenGui:
--
--   local tooltip = ItemTooltip.create(gui, guard)
--   tooltip.schedule(entry, lines, compareEntry)  -- show after the hover delay
--   tooltip.hide()
--
-- `guard` (optional) runs when the delay fires — the host says whether
-- showing still makes sense (panel open, not mid-drag). `lines` (optional)
-- appends host-specific rows under the card ({ { text, color? } }) — the
-- store uses it for price and "not traded here" hints. `compareEntry`
-- (optional) is the equipped piece the hovered item would replace: the
-- card's trait rows then carry a right-aligned green/red point delta
-- against it, and traits only on the equipped piece show as "+0" rows
-- with the full loss on the right. The tooltip appears instantly at the
-- cursor with no tween so it tracks cleanly (UI.md §11).

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
	-- One card shell (frame + rarity stroke + list layout). The main card and
	-- the compare card are two instances of the same recipe.
	local function makeCard()
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = Theme.Semantic.PanelTop
		frame.BorderSizePixel = 0
		frame.AutomaticSize = Enum.AutomaticSize.Y
		frame.Size = UDim2.new(0, ItemTooltip.WIDTH, 0, 0)
		frame.Visible = false
		frame.ZIndex = 60
		frame.Parent = gui
		UIKit.autoScale(frame) -- content scales; its Position stays screen-space

		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(Theme.Semantic.PanelTop, Theme.Semantic.PanelBot)
		gradient.Parent = frame

		-- Retinted to the item's rarity when the card shows (§6.5).
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1
		stroke.Color = Theme.Semantic.BorderSlot
		stroke.Parent = frame

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = frame

		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 4)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = frame

		return { frame = frame, stroke = stroke, order = 0 }
	end

	local main = makeCard()

	-- Rows are rebuilt per hover; UI components (gradient/stroke/padding/
	-- layout) are not GuiObjects, so the clear below leaves them alone.
	local function cardRow(card, height)
		card.order += 1
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, height)
		row.BackgroundTransparency = 1
		row.LayoutOrder = card.order
		row.ZIndex = 61
		row.Parent = card.frame
		return row
	end

	local function cardText(parent, text, size, color, font)
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

	-- Rebuilds a card's rows for an entry (§6.5: name + Lv, rarity·kind +
	-- size, divider, stat line, trait grants with mini hexes, flavor), then
	-- any host-provided extra lines. `compareEntry` adds the equipped-piece
	-- trait deltas to the trait rows.
	local function buildCard(card, entry, lines, compareEntry)
		for _, child in ipairs(card.frame:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		card.order = 0

		local function extraLines()
			if not lines then
				return
			end
			for _, extra in ipairs(lines) do
				local row = cardRow(card, 16)
				local label = cardText(row, extra.text, Theme.Text.Sm, extra.color or Theme.Semantic.TextMuted)
				label.Size = UDim2.new(1, 0, 1, 0)
			end
		end

		local def = Items.get(entry.itemId)
		local rarity = Rarity.forEntry(entry, def)
		card.stroke.Color = rarity.color -- frame tints with the tier
		if not def then
			local row = cardRow(card, 20)
			local name = cardText(row, entry.itemId, Theme.Text.Item, rarity.textColor, Theme.Font.DisplayBold)
			name.Size = UDim2.new(1, 0, 1, 0)
			extraLines()
			return
		end

		local itemLevel, itemTraits = Traits.entryInfo(entry, def)

		local header = cardRow(card, 20)
		local name = cardText(header, def.name, Theme.Text.Item, rarity.textColor, Theme.Font.DisplayBold)
		name.Size = UDim2.new(1, -36, 1, 0)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		if itemLevel > 0 then
			local lv = cardText(header, ("Lv %d"):format(itemLevel), Theme.Text.Sm, Theme.Semantic.TextSecondary)
			lv.Size = UDim2.new(0, 34, 1, 0)
			lv.Position = UDim2.new(1, -34, 0, 0)
			lv.TextXAlignment = Enum.TextXAlignment.Right
		end

		local sub = cardRow(card, 14)
		local kind =
			cardText(sub, rarity.name .. " · " .. kindFor(def), Theme.Text.Xs, rarity.textColor, Theme.Font.Body)
		kind.Size = UDim2.new(1, -54, 1, 0)
		kind.TextTransparency = 0.25
		local w, h = Items.sizeFor(entry.itemId, false)
		local sizeLabel =
			cardText(sub, ("Size %d×%d"):format(w, h), Theme.Text.Xs, Theme.Semantic.TextMuted, Theme.Font.Body)
		sizeLabel.Size = UDim2.new(0, 52, 1, 0)
		sizeLabel.Position = UDim2.new(1, -52, 0, 0)
		sizeLabel.TextXAlignment = Enum.TextXAlignment.Right

		local dividerRow = cardRow(card, 5)
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
			local statRow = cardRow(card, 16)
			local stats = cardText(statRow, table.concat(parts, "  ·  "), Theme.Text.Sm, Theme.Semantic.TextStrong)
			stats.Size = UDim2.new(1, 0, 1, 0)
		end

		local playerLevel = player:GetAttribute("Level") or 1
		if itemLevel > playerLevel then
			local inertRow = cardRow(card, 14)
			local inert = cardText(
				inertRow,
				("INERT — needs class Lv %d"):format(itemLevel),
				Theme.Text.Xs,
				Theme.Color.Blood400
			)
			inert.Size = UDim2.new(1, 0, 1, 0)
		end

		-- The compared (equipped) piece's traits, for the delta column.
		local diffTraits
		if compareEntry then
			local compareDef = Items.get(compareEntry.itemId)
			if compareDef then
				local _, t = Traits.entryInfo(compareEntry, compareDef)
				diffTraits = t or {}
			end
		end

		-- Trait grants, one row each with a mini hex (schools first — they
		-- gate spells). Equipped-only traits still get a row — "+0" on the
		-- left, the full loss as the delta.
		if itemTraits or diffTraits then
			local ownTraits = itemTraits or {}
			local function grantRow(id, displayName, color, emoji, points, delta)
				local row = cardRow(card, 18)
				local badge = miniHex(row, id, color, emoji)
				badge.Position = UDim2.new(0, 0, 0.5, -8)
				local showDelta = delta ~= nil and delta ~= 0
				local label = cardText(
					row,
					("%s +%d"):format(displayName, points),
					Theme.Text.Sm,
					Theme.Semantic.TextStrong
				)
				label.Size = UDim2.new(1, showDelta and -60 or -22, 1, 0)
				label.Position = UDim2.new(0, 22, 0, 0)
				if showDelta then
					local deltaLabel = cardText(
						row,
						(delta > 0 and "+%d" or "%d"):format(delta),
						Theme.Text.Sm,
						delta > 0 and Theme.Semantic.Good or Theme.Semantic.Bad
					)
					deltaLabel.Size = UDim2.new(0, 36, 1, 0)
					deltaLabel.Position = UDim2.new(1, -36, 0, 0)
					deltaLabel.TextXAlignment = Enum.TextXAlignment.Right
				end
			end

			local function traitRows(id, displayName, color, emoji)
				local points = ownTraits[id]
				local basePoints = diffTraits and diffTraits[id]
				if points then
					local delta = diffTraits and (points - (basePoints or 0)) or nil
					grantRow(id, displayName, color, emoji, points, delta)
				elseif basePoints then
					grantRow(id, displayName, color, emoji, 0, -basePoints)
				end
			end

			for _, schoolId in ipairs(Spells.schoolOrder) do
				local school = Spells.schools[schoolId]
				if school then
					traitRows(schoolId, school.name, school.color, school.icon)
				end
			end
			for _, traitId in ipairs(Traits.order) do
				local traitDef = Traits.get(traitId)
				traitRows(
					traitId,
					traitDef and traitDef.name or traitId,
					traitDef and traitDef.color or Theme.Semantic.TextBody,
					traitDef and traitDef.icon
				)
			end
		end

		-- Flavor, italic and quoted (only when the def carries one).
		if typeof(def.flavor) == "string" and def.flavor ~= "" then
			local flavorRow = cardRow(card, 0)
			flavorRow.AutomaticSize = Enum.AutomaticSize.Y
			local flavor = cardText(
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
		main.frame.Visible = false
	end

	function handle.schedule(entry, lines, compareEntry)
		hoverToken += 1
		local token = hoverToken
		task.delay(ItemTooltip.DELAY, function()
			if token ~= hoverToken or (guard and not guard()) then
				return
			end
			buildCard(main, entry, lines, compareEntry)
			local s = UIKit.scaleFactor() -- rendered card size is design px × scale
			local guiSize = gui.AbsoluteSize
			main.frame.Position = UDim2.fromOffset(
				math.min(mouse.X + 14, guiSize.X - (ItemTooltip.WIDTH + 16) * s),
				math.min(mouse.Y + 10, guiSize.Y - 220 * s)
			)
			main.frame.Visible = true
		end)
	end

	return handle
end

return ItemTooltip
