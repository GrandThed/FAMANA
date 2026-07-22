-- Fishing UI (Minijuego de Pesca).
-- Shows bite alert when fishing rod is cast and handles timing prompt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local FishingUI = {}

function FishingUI.start()
	local startFishing = Remotes.getFunction("StartFishing")
	local catchFish = Remotes.getFunction("CatchFish")
	local castRodRemote = Remotes.get("CastFishingRod")
	local biteAlertRemote = Remotes.get("FishingBiteAlert")

	local gui = Instance.new("ScreenGui")
	gui.Name = "FishingUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.Parent = player:WaitForChild("PlayerGui")

	local alertFrame = Instance.new("Frame")
	alertFrame.Size = UDim2.new(0, 260, 0, 70)
	alertFrame.Position = UDim2.new(0.5, 0, 0.75, 0)
	alertFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	alertFrame.Visible = false
	alertFrame.Parent = gui
	UIKit.stylePanel(alertFrame)
	UIKit.addShadow(alertFrame)

	local alertTitle = UIKit.label(alertFrame, "¡PIQUE! Presiona ESPACIO", 14, Theme.Semantic.Currency, Theme.Font.DisplayBold)
	alertTitle.Size = UDim2.new(1, 0, 0, 30)
	alertTitle.Position = UDim2.new(0, 0, 0, 10)
	alertTitle.TextXAlignment = Enum.TextXAlignment.Center

	local activeToken = nil
	local activeConn = nil

	local function resetBite()
		alertFrame.Visible = false
		activeToken = nil
		if activeConn then
			activeConn:Disconnect()
			activeConn = nil
		end
	end

	castRodRemote.OnClientEvent:Connect(function()
		resetBite()
		startFishing:InvokeServer()
		Sfx.play("uiClick")
	end)

	biteAlertRemote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		activeToken = payload.token
		alertFrame.Visible = true
		Sfx.play("xpDing")

		activeConn = UserInputService.InputBegan:Connect(function(input, gpe)
			if gpe then
				return
			end
			if input.KeyCode == Enum.KeyCode.Space or input.UserInputType == Enum.UserInputType.MouseButton1 then
				if activeToken then
					catchFish:InvokeServer({ token = activeToken })
					resetBite()
				end
			end
		end)

		task.delay(1.8, function()
			if alertFrame.Visible then
				resetBite()
			end
		end)
	end)
end

return FishingUI
