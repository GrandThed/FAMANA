-- Lets the player cycle which arrow type their bow fires (R key, only while
-- a bow — a weapon with `usesArrows = true`, shared/Items.lua — is
-- equipped). No local UI state to keep in sync for the CYCLING itself: the
-- server (EnemyService) owns the current selection and confirms every cycle
-- with a toast via the existing Notify remote (NotificationUI already
-- renders those).
--
-- Also renders a small HUD chip above the crosshair, visible only while a
-- bow is equipped, showing the currently selected arrow (name + tint
-- matching its missile color, see EnemyService's ARROW_EFFECT_COLORS) and
-- how many are left in the inventory. The selection itself is read from the
-- player's replicated "SelectedArrow" attribute (see EnemyService.cycleArrow
-- and its default-init on join) — same pattern as HudUI's Mana attribute
-- binding, just for ammo instead of a stat.

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Items = require(Shared:WaitForChild("Items"))
local Theme = require(script.Parent.Theme)

local ArrowSelectUI = {}

local player = Players.LocalPlayer

-- Horizontal offset to the LEFT of dead-center, in px — sits beside the
-- crosshair instead of above it (SwingCooldownUI already owns the space
-- directly below), so it doesn't sit in the way of what you're aiming at.
local LEFT_OF_CROSSHAIR = 70

-- Tint per arrow itemId, purely cosmetic — kept in sync by hand with the
-- server's ARROW_EFFECT_COLORS (EnemyService.lua), which drives the actual
-- missile/trail color. Deliberately NOT pulled from Theme: these three
-- colors intentionally match the projectile, not the design-system ramp.
local ARROW_CHIP_COLORS = {
	arrow = Color3.fromRGB(245, 245, 245),
	arrow_fire = Color3.fromRGB(255, 110, 40),
	arrow_poison = Color3.fromRGB(110, 220, 90),
}

-- Whether the character currently has a bow (or any future usesArrows
-- weapon) equipped, by reading the itemId attribute ToolService stamps on
-- every Tool it builds.
local function equippedUsesArrows()
	local character = player.Character
	if not character then
		return false
	end
	local tool = character:FindFirstChildOfClass("Tool")
	local itemId = tool and tool:GetAttribute("itemId")
	local def = itemId and Items.get(itemId)
	return def ~= nil and def.usesArrows == true
end

-- Sums every stack matching itemId across the whole inventory (same read
-- PlayerService.getItemCount does server-side) from the client's cached
-- copy of the inventory array (pushed via InventoryUpdated/RequestInventory,
-- same pair HudUI already uses for the hotbar).
local function countItem(inventory, itemId)
	local total = 0
	for _, stack in ipairs(inventory) do
		if stack.itemId == itemId then
			total += stack.quantity
		end
	end
	return total
end

local function buildChip()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ArrowSelectUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "ArrowChip"
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.Size = UDim2.new(0, 0, 0, 26)
	frame.AnchorPoint = Vector2.new(1, 0.5)
	frame.Position = UDim2.new(0.5, -LEFT_OF_CROSSHAIR, 0.5, 0)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.55
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.45
	stroke.Thickness = 1
	stroke.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = frame

	-- Color swatch: same read as "which color is this arrow's trail/glow" —
	-- a quick colored dot reads faster than the name alone at a glance.
	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.Size = UDim2.new(0, 12, 0, 12)
	swatch.AnchorPoint = Vector2.new(0, 0.5)
	swatch.Position = UDim2.new(0, 0, 0.5, 0)
	swatch.BackgroundColor3 = Color3.new(1, 1, 1)
	swatch.BorderSizePixel = 0
	swatch.LayoutOrder = 1
	swatch.Parent = frame

	local swatchCorner = Instance.new("UICorner")
	swatchCorner.CornerRadius = UDim.new(1, 0)
	swatchCorner.Parent = swatch

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.new(0, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Font.Body
	label.TextSize = Theme.Text.Sm
	label.TextColor3 = Theme.Semantic.TextStrong
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.LayoutOrder = 2
	label.Text = ""
	label.Parent = frame

	return frame, swatch, label
end

function ArrowSelectUI.start()
	local cycleArrowRemote = Remotes.get("CycleArrow")

	ContextActionService:BindAction("CycleArrow", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and equippedUsesArrows() then
			cycleArrowRemote:FireServer()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.R)

	local frame, swatch, label = buildChip()
	local inventory = {}

	local function refresh()
		if not equippedUsesArrows() then
			frame.Visible = false
			return
		end
		frame.Visible = true

		local itemId = player:GetAttribute("SelectedArrow") or "arrow"
		local def = Items.get(itemId)
		local qty = countItem(inventory, itemId)

		swatch.BackgroundColor3 = ARROW_CHIP_COLORS[itemId] or ARROW_CHIP_COLORS.arrow
		label.Text = (def and def.name or itemId) .. "  x" .. qty
	end

	player:GetAttributeChangedSignal("SelectedArrow"):Connect(refresh)

	-- Re-check equip state (and thus visibility) on every tool (un)equip,
	-- same ChildAdded/ChildRemoved watch HudUI uses for its own hotbar
	-- highlight — cheaper than polling every frame for something that only
	-- changes on equip/unequip.
	local function bindCharacter(character)
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				refresh()
			end
		end)
		character.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				refresh()
			end
		end)
		refresh()
	end
	if player.Character then
		bindCharacter(player.Character)
	end
	player.CharacterAdded:Connect(bindCharacter)

	task.spawn(function()
		Remotes.get("InventoryUpdated").OnClientEvent:Connect(function(newInventory)
			inventory = newInventory
			refresh()
		end)

		local requestInventory = Remotes.getFunction("RequestInventory")
		local ok, initial = pcall(function()
			return requestInventory:InvokeServer()
		end)
		if ok then
			inventory = initial
			refresh()
		end
	end)
end

return ArrowSelectUI