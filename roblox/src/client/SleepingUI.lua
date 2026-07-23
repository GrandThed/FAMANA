-- Sleeping UI.
-- Displays resting overlay hint and handles camera transition while lying down on a bed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local SleepingUI = {}

function SleepingUI.start()
	local toggleSleepingRemote = Remotes.get("ToggleSleeping")

	local gui = Instance.new("ScreenGui")
	gui.Name = "SleepingUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 9
	gui.Parent = player:WaitForChild("PlayerGui")

	local isSleeping = false
	local ProximityPromptService = game:GetService("ProximityPromptService")

	toggleSleepingRemote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		isSleeping = payload.sleeping == true
		ProximityPromptService.Enabled = not isSleeping
	end)

	local function requestWakeUp()
		if isSleeping then
			toggleSleepingRemote:FireServer({ wakeUp = true })
		end
	end

	UserInputService.InputBegan:Connect(function(input, gpe)
		if not isSleeping then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.E or k == Enum.KeyCode.Space or k == Enum.KeyCode.W or k == Enum.KeyCode.A or k == Enum.KeyCode.S or k == Enum.KeyCode.D or k == Enum.KeyCode.Up or k == Enum.KeyCode.Down or k == Enum.KeyCode.Left or k == Enum.KeyCode.Right then
			requestWakeUp()
		end
	end)

	local RunService = game:GetService("RunService")
	RunService.Heartbeat:Connect(function()
		if not isSleeping then
			return
		end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and (hum.MoveDirection.Magnitude > 0.1 or hum.Jump) then
			requestWakeUp()
		end
	end)
end

return SleepingUI
