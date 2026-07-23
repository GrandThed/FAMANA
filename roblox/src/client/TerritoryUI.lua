-- Territory HUD Banner: shows a top-center HUD indicator when the local player enters a settlement territory range.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Settlements = require(Shared:WaitForChild("Settlements"))
local GridConfig = require(Shared:WaitForChild("GridConfig"))

local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local TerritoryUI = {}

local currentInsideSettlement = nil
local bannerFrame = nil
local titleLabel = nil
local subtitleLabel = nil

local TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function distance2D(a, b)
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

function TerritoryUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TerritoryUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 150
	gui.Parent = player:WaitForChild("PlayerGui")

	bannerFrame = Instance.new("Frame")
	bannerFrame.Size = UDim2.new(0, 380, 0, 52)
	bannerFrame.Position = UDim2.new(0.5, 0, 0.08, 0)
	bannerFrame.AnchorPoint = Vector2.new(0.5, 0)
	bannerFrame.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	bannerFrame.BackgroundTransparency = 0.2
	bannerFrame.BorderSizePixel = 0
	bannerFrame.Visible = false
	bannerFrame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = bannerFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 210, 80)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = bannerFrame

	titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, 0, 0.5, 0)
	titleLabel.Position = UDim2.new(0, 0, 0.08, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = Theme.Font.DisplayBold
	titleLabel.TextSize = 16
	titleLabel.TextColor3 = Theme.Semantic.TextStrong
	titleLabel.TextStrokeTransparency = 0.3
	titleLabel.Text = ""
	titleLabel.Parent = bannerFrame

	subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Size = UDim2.new(1, 0, 0.4, 0)
	subtitleLabel.Position = UDim2.new(0, 0, 0.55, 0)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.FontFace = Theme.Font.BodyBold
	subtitleLabel.TextSize = 12
	subtitleLabel.TextColor3 = Color3.fromRGB(200, 220, 255)
	subtitleLabel.TextStrokeTransparency = 0.5
	subtitleLabel.Text = ""
	subtitleLabel.Parent = bannerFrame

	UIKit.autoScale(bannerFrame)

	local currentCell = GridConfig.currentCell()
	local localDefs = {}
	for id, def in pairs(Settlements.defs) do
		if def.cell == currentCell then
			localDefs[id] = def
		end
	end

	local pollTimer = 0
	RunService.Heartbeat:Connect(function(dt)
		pollTimer += dt
		if pollTimer < 0.25 then
			return
		end
		pollTimer = 0

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			if currentInsideSettlement then
				currentInsideSettlement = nil
				TerritoryUI.hideBanner()
			end
			return
		end

		local insideDefId = nil
		local insideDef = nil
		for id, def in pairs(localDefs) do
			if distance2D(root.Position, def.position) <= def.radius then
				insideDefId = id
				insideDef = def
				break
			end
		end

		if insideDefId ~= currentInsideSettlement then
			currentInsideSettlement = insideDefId
			if insideDef then
				TerritoryUI.showBanner(insideDef)
			else
				TerritoryUI.hideBanner()
			end
		end
	end)
end

function TerritoryUI.showBanner(def)
	if not bannerFrame then
		return
	end
	titleLabel.Text = "🏰 " .. string.upper(def.name)
	subtitleLabel.Text = string.format("Rango: %dm | Zona de Influencia y Recolección", def.radius)

	bannerFrame.Visible = true
	bannerFrame.BackgroundTransparency = 1
	titleLabel.TextTransparency = 1
	subtitleLabel.TextTransparency = 1

	TweenService:Create(bannerFrame, TWEEN_INFO, { BackgroundTransparency = 0.2 }):Play()
	TweenService:Create(titleLabel, TWEEN_INFO, { TextTransparency = 0 }):Play()
	TweenService:Create(subtitleLabel, TWEEN_INFO, { TextTransparency = 0 }):Play()
end

function TerritoryUI.hideBanner()
	if not bannerFrame or not bannerFrame.Visible then
		return
	end
	local fade = TweenService:Create(bannerFrame, TWEEN_INFO, { BackgroundTransparency = 1 })
	TweenService:Create(titleLabel, TWEEN_INFO, { TextTransparency = 1 }):Play()
	TweenService:Create(subtitleLabel, TWEEN_INFO, { TextTransparency = 1 }):Play()

	fade.Completed:Once(function()
		if not currentInsideSettlement then
			bannerFrame.Visible = false
		end
	end)
	fade:Play()
end

return TerritoryUI
