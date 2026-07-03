-- Tracks each player's focused target (sent by the client while aiming). The
-- combat and gathering systems prefer this target, but always re-validate it
-- server-side (real object, within reach) so it can't be spoofed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local TargetService = {}

local focus = {} -- [userId] = BasePart (the target's anchor) or nil

function TargetService.get(player)
	local part = focus[player.UserId]
	-- Drop stale references (target despawned).
	if part and not part.Parent then
		focus[player.UserId] = nil
		return nil
	end
	return part
end

function TargetService.start()
	local setTarget = Remotes.get("SetTarget")

	setTarget.OnServerEvent:Connect(function(player, target)
		if target == nil then
			focus[player.UserId] = nil
		elseif typeof(target) == "Instance" and target:IsA("BasePart") then
			focus[player.UserId] = target
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		focus[player.UserId] = nil
	end)
end

return TargetService
