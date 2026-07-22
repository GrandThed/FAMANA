-- Custom ProximityPrompt UI.
-- Replaces default blocky black prompts with a sleek glassmorphic floating UI.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local CustomPromptUI = {}
local activeGuis = {}

local function getKeyboardKeyName(keyCode)
	if not keyCode or keyCode == Enum.KeyCode.Unknown then
		return "E"
	end
	local name = UserInputService:GetStringForKeyCode(keyCode)
	if name and name ~= "" then
		return name:upper()
	end
	return keyCode.Name:upper()
end

local function createCustomPromptGui(prompt, targetPart)
	if not targetPart then
		return nil
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "CustomPromptGui"
	gui.AlwaysOnTop = true
	gui.Size = UDim2.new(0, 210, 0, 52)
	gui.StudsOffset = Vector3.new(0, (prompt.UIOffset and prompt.UIOffset.Y or 0) + 1.8, 0)
	gui.MaxDistance = prompt.MaxActivationDistance + 4
	gui.Parent = targetPart

	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 1, 0)
	card.Position = UDim2.new(0.5, 0, 0.5, 0)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.BackgroundColor3 = Color3.fromRGB(18, 22, 28)
	card.BackgroundTransparency = 0.15
	card.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Semantic.Currency
	stroke.Transparency = 0.4
	stroke.Thickness = 1.4
	stroke.Parent = card

	-- Key badge
	local keyBadge = Instance.new("Frame")
	keyBadge.Size = UDim2.new(0, 34, 0, 34)
	keyBadge.Position = UDim2.new(0, 9, 0.5, 0)
	keyBadge.AnchorPoint = Vector2.new(0, 0.5)
	keyBadge.BackgroundColor3 = Color3.fromRGB(32, 38, 48)
	keyBadge.Parent = card

	local keyCorner = Instance.new("UICorner")
	keyCorner.CornerRadius = UDim.new(0, 8)
	keyCorner.Parent = keyBadge

	local keyStroke = Instance.new("UIStroke")
	keyStroke.Color = Color3.fromRGB(255, 255, 255)
	keyStroke.Transparency = 0.6
	keyStroke.Thickness = 1
	keyStroke.Parent = keyBadge

	local keyLabel = UIKit.label(
		keyBadge,
		getKeyboardKeyName(prompt.KeyboardKeyCode),
		14,
		Color3.fromRGB(255, 255, 255),
		Theme.Font.DisplayBold
	)
	keyLabel.Size = UDim2.new(1, 0, 1, 0)
	keyLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- Text Container
	local objectLabel = UIKit.label(
		card,
		prompt.ObjectText ~= "" and prompt.ObjectText or "Objeto",
		10,
		Color3.fromRGB(170, 180, 195),
		Theme.Font.Body
	)
	objectLabel.Size = UDim2.new(1, -52, 0, 14)
	objectLabel.Position = UDim2.new(0, 48, 0, 9)
	objectLabel.TextXAlignment = Enum.TextXAlignment.Left

	local actionLabel = UIKit.label(
		card,
		prompt.ActionText ~= "" and prompt.ActionText or "Interactuar",
		12,
		Color3.fromRGB(255, 255, 255),
		Theme.Font.BodyBold
	)
	actionLabel.Size = UDim2.new(1, -52, 0, 18)
	actionLabel.Position = UDim2.new(0, 48, 0, 23)
	actionLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Progress Bar for HoldDuration
	if prompt.HoldDuration and prompt.HoldDuration > 0 then
		local progressBarBg = Instance.new("Frame")
		progressBarBg.Name = "ProgressBarBg"
		progressBarBg.Size = UDim2.new(1, -18, 0, 4)
		progressBarBg.Position = UDim2.new(0, 9, 1, -7)
		progressBarBg.BackgroundColor3 = Color3.fromRGB(40, 48, 60)
		progressBarBg.Parent = card

		local progressCorner = Instance.new("UICorner")
		progressCorner.CornerRadius = UDim.new(0, 2)
		progressCorner.Parent = progressBarBg

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.new(0, 0, 1, 0)
		fill.BackgroundColor3 = Theme.Semantic.Currency
		fill.Parent = progressBarBg

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 2)
		fillCorner.Parent = fill

		prompt.PromptButtonHoldBegan:Connect(function()
			if fill and fill:IsDescendantOf(game) then
				fill:TweenSize(UDim2.new(1, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Linear, prompt.HoldDuration, true)
			end
		end)
		prompt.PromptButtonHoldEnded:Connect(function()
			if fill and fill:IsDescendantOf(game) then
				fill:TweenSize(UDim2.new(0, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.15, true)
			end
		end)
	end

	-- Micro Entrance animation
	card.Size = UDim2.new(0.85, 0, 0.85, 0)
	card.BackgroundTransparency = 1
	TweenService:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 0.15,
	}):Play()

	return gui
end

function CustomPromptUI.start()
	ProximityPromptService.PromptShown:Connect(function(prompt)
		prompt.Style = Enum.ProximityPromptStyle.Custom

		local parentPart = prompt.Parent
		if not parentPart then
			return
		end

		if activeGuis[prompt] then
			activeGuis[prompt]:Destroy()
		end

		local gui = createCustomPromptGui(prompt, parentPart)
		if gui then
			activeGuis[prompt] = gui
		end
	end)

	ProximityPromptService.PromptHidden:Connect(function(prompt)
		local gui = activeGuis[prompt]
		if gui then
			activeGuis[prompt] = nil
			gui:Destroy()
		end
	end)
end

return CustomPromptUI
