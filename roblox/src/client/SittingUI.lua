-- Sitting UI.
-- Displays seating overlay hint and handles unseating on keypress.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local SittingUI = {}

function SittingUI.start()
	local toggleSittingRemote = Remotes.get("ToggleSitting")

	local gui = Instance.new("ScreenGui")
	gui.Name = "SittingUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 9
	gui.Parent = player:WaitForChild("PlayerGui")

	local isSeated = false
	local ProximityPromptService = game:GetService("ProximityPromptService")

	toggleSittingRemote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		isSeated = payload.seated == true
		ProximityPromptService.Enabled = not isSeated
	end)

	local function requestStandUp()
		if isSeated then
			toggleSittingRemote:FireServer({ standUp = true })
		end
	end

	UserInputService.InputBegan:Connect(function(input, gpe)
		if not isSeated then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.E or k == Enum.KeyCode.Space or k == Enum.KeyCode.W or k == Enum.KeyCode.A or k == Enum.KeyCode.S or k == Enum.KeyCode.D or k == Enum.KeyCode.Up or k == Enum.KeyCode.Down or k == Enum.KeyCode.Left or k == Enum.KeyCode.Right then
			requestStandUp()
		end
	end)

	local RunService = game:GetService("RunService")
	RunService.Heartbeat:Connect(function()
		if not isSeated then
			return
		end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and (hum.MoveDirection.Magnitude > 0.1 or hum.Jump) then
			requestStandUp()
		end
	end)
end

return SittingUI
