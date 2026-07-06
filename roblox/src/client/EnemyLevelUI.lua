-- Recolors every enemy's level label RELATIVE to the local player's own
-- level, instead of the flat absolute-level color EnemyService paints as a
-- placeholder. A level 5 goblin should read as a red threat to a level 1
-- player, but as a routine white/equal target to a level 5 player.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local EnemyLevelUI = {}

-- Banded by (enemyLevel - playerLevel), not the enemy's raw level.
local DIFF_COLOR_BANDS = {
	{ maxDiff = 0, color = Color3.fromRGB(235, 235, 235) }, -- at or below your level
	{ maxDiff = 2, color = Color3.fromRGB(255, 221, 51) }, -- a bit above you
	{ maxDiff = math.huge, color = Color3.fromRGB(255, 90, 60) }, -- dangerously above you
}

local function colorForDiff(diff)
	for _, band in ipairs(DIFF_COLOR_BANDS) do
		if diff <= band.maxDiff then
			return band.color
		end
	end
	return DIFF_COLOR_BANDS[#DIFF_COLOR_BANDS].color
end

local function refreshLabel(enemyPart)
	local nameTag = enemyPart:FindFirstChild("NameTag")
	local levelLabel = nameTag and nameTag:FindFirstChild("LevelLabel")
	local enemyLevel = enemyPart:GetAttribute("Level")
	if not (levelLabel and enemyLevel) then
		return
	end
	local playerLevel = player:GetAttribute("Level") or 1
	levelLabel.TextColor3 = colorForDiff(enemyLevel - playerLevel)
end

local function watchEnemy(enemyPart)
	refreshLabel(enemyPart)
	-- The level attribute is set right when the part is created, but in
	-- case replication ever lands it a frame late, keep listening so the
	-- label doesn't get stuck on the server's placeholder color.
	enemyPart:GetAttributeChangedSignal("Level"):Connect(function()
		refreshLabel(enemyPart)
	end)
end

function EnemyLevelUI.start()
	local folder = Workspace:WaitForChild("Enemies")

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			watchEnemy(child)
		end
	end
	folder.ChildAdded:Connect(function(child)
		if child:IsA("BasePart") then
			watchEnemy(child)
		end
	end)

	-- Leveling up (or down, if that's ever a thing) should instantly
	-- repaint every enemy currently on screen, not just future spawns.
	player:GetAttributeChangedSignal("Level"):Connect(function()
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") then
				refreshLabel(child)
			end
		end
	end)
end

return EnemyLevelUI
