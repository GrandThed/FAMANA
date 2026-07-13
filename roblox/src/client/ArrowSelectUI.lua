-- Lets the player cycle which arrow type their bow fires (T key, only while
-- a bow — a weapon with `usesArrows = true`, shared/Items.lua — is
-- equipped). No local UI state to keep in sync: the server (EnemyService)
-- owns the current selection and confirms every cycle with a toast via the
-- existing Notify remote (NotificationUI already renders those).

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Items = require(Shared:WaitForChild("Items"))

local ArrowSelectUI = {}

local player = Players.LocalPlayer

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

function ArrowSelectUI.start()
	local cycleArrowRemote = Remotes.get("CycleArrow")

	ContextActionService:BindAction("CycleArrow", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and equippedUsesArrows() then
			cycleArrowRemote:FireServer()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.T)
end

return ArrowSelectUI
