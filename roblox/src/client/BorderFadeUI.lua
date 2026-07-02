-- Smooths border crossings with a black fade: fade out before a teleport,
-- fade in on arrival. Fail-safe -- every path ends fully transparent, so a
-- failed teleport (e.g. in Studio) can never leave the screen stuck black.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local player = Players.LocalPlayer

local BorderFadeUI = {}

function BorderFadeUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BorderFade"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 1 -- clear (Active=false: never blocks clicks below)
	frame.Parent = gui

	local function fadeTo(transparency, seconds)
		TweenService:Create(frame, TweenInfo.new(seconds), { BackgroundTransparency = transparency }):Play()
	end

	-- Arrived via a border teleport? Start black and fade in.
	local data = TeleportService:GetLocalPlayerTeleportData()
	if data and data.entryEdge then
		frame.BackgroundTransparency = 0
		task.delay(0.2, function()
			fadeTo(1, 0.5)
		end)
	end

	Remotes.get("Teleporting").OnClientEvent:Connect(function()
		fadeTo(0, 0.3)
	end)

	-- Teleport failed server-side: fade back in so we're not stuck black.
	Remotes.get("TeleportCancelled").OnClientEvent:Connect(function()
		fadeTo(1, 0.3)
	end)
end

return BorderFadeUI
