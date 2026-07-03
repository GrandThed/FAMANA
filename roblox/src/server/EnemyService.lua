-- Enemies: spawn at fixed points, chase + melee the nearest player, take damage
-- from weapon swings, die, and respawn. On death, fires kill handlers (the drop
-- system hooks in here). Enemy types are data-driven (ENEMY_DEFS), so adding a
-- new enemy is just a new entry. In-memory per server.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HealthService = require(script.Parent.HealthService)
local ManaService = require(script.Parent.ManaService)
local ToolService = require(script.Parent.ToolService)
local TargetService = require(script.Parent.TargetService)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ArtKit = require(Shared:WaitForChild("ArtKit"))

local V = Vector3.new

local EnemyService = {}

local DEFAULT_REACH = Config.defaultReach -- fallback when a weapon def omits `reach`
local MISSILE_SPEED = 90 -- studs/second the magic missile travels

local notifyRemote -- RemoteEvent, resolved in start()

-- Rate-limit the "not enough mana" toast so staff-spamming doesn't spam it.
local lastManaWarn = {} -- [userId] = os.clock()
local MANA_WARN_COOLDOWN = 1.5

-- Data-driven enemy types.
local ENEMY_DEFS = {
	slime = {
		name = "Slime",
		hp = 30,
		damage = 5,
		attackCooldown = 1.5,
		aggroRange = 30,
		attackRange = 6,
		respawn = 15,
		lootSource = "slime",
		size = Vector3.new(3, 3, 3),
		color = ArtKit.Palette.slime,
		material = Enum.Material.SmoothPlastic,
		transparency = 0.2,
		-- Slimes only move by hopping (parabolic jumps with squash & stretch).
		movement = "hop",
		hop = { distance = 6, height = 2.5, time = 0.5, pause = 0.35 },
		-- Welded onto the body part; offsets from its center, front is -Z.
		details = {
			{ name = "Core", shape = "Ball", size = V(1.5, 1.5, 1.5), offset = V(0, -0.3, 0), color = "slime" },
			{ name = "EyeL", size = V(0.35, 0.5, 0.3), offset = V(-0.55, 0.5, -1.5), color = "ink" },
			{ name = "EyeR", size = V(0.35, 0.5, 0.3), offset = V(0.55, 0.5, -1.5), color = "ink" },
			{ name = "Mouth", size = V(0.7, 0.18, 0.3), offset = V(0, -0.1, -1.5), color = "ink" },
		},
		spots = {
			Vector3.new(-20, 0, 12),
			Vector3.new(-28, 0, 20),
			Vector3.new(-15, 0, 26),
		},
	},
	goblin = {
		name = "Goblin",
		hp = 60,
		damage = 10,
		attackCooldown = 1.2,
		walkSpeed = 12,
		aggroRange = 35,
		attackRange = 6,
		respawn = 20,
		lootSource = "goblin",
		size = Vector3.new(2.5, 4, 2.5),
		color = ArtKit.Palette.goblin,
		material = Enum.Material.SmoothPlastic,
		details = {
			{ name = "EyeL", size = V(0.32, 0.32, 0.25), offset = V(-0.5, 1.3, -1.3), color = "ink" },
			{ name = "EyeR", size = V(0.32, 0.32, 0.25), offset = V(0.5, 1.3, -1.3), color = "ink" },
			{ name = "Nose", size = V(0.3, 0.5, 0.45), offset = V(0, 0.95, -1.35), color = "goblinDark" },
			{ name = "Mouth", size = V(0.9, 0.16, 0.25), offset = V(0, 0.55, -1.3), color = "ink" },
			{ name = "EarL", size = V(0.25, 0.8, 0.55), offset = V(-1.4, 1.45, 0), rot = V(0, 0, 25), color = "goblin" },
			{ name = "EarR", size = V(0.25, 0.8, 0.55), offset = V(1.4, 1.45, 0), rot = V(0, 0, -25), color = "goblin" },
			{ name = "Belt", size = V(2.7, 0.5, 2.7), offset = V(0, -0.6, 0), color = "trunkDark" },
			{ name = "Cloth", size = V(1.0, 1.2, 0.22), offset = V(0, -1.35, -1.3), color = "dirt" },
		},
		spots = {
			Vector3.new(-34, 0, -8),
			Vector3.new(-40, 0, -18),
		},
	},
}

local spawns = {} -- { def, pos, enemy = { part, fill, hp, lastAttack, dead, def } | nil }
local enemyFolder

-- [n] = function(lootSource, position, killer)  registered by the drop system.
EnemyService.killedHandlers = {}
function EnemyService.onKilled(fn)
	table.insert(EnemyService.killedHandlers, fn)
end

-- [n] = function(lootSource, player)  fired when an enemy lands a melee hit
-- on a player (the effect system hooks in here, e.g. slime slowness).
EnemyService.playerHitHandlers = {}
function EnemyService.onPlayerHit(fn)
	table.insert(EnemyService.playerHitHandlers, fn)
end

local function groundY(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { enemyFolder }
	local result = Workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -1000, 0), params)
	return result and result.Position.Y or 0
end

local function updateHealthBar(enemy)
	enemy.fill.Size = UDim2.new(math.clamp(enemy.hp / enemy.def.hp, 0, 1), 0, 1, 0)
end

local function buildEnemy(pos, def)
	local y = groundY(pos.X, pos.Z)

	local part = Instance.new("Part")
	part.Name = def.name
	part.Anchored = true
	part.Size = def.size
	part.Color = def.color
	part.Material = def.material
	part.Transparency = def.transparency or 0
	part.Position = Vector3.new(pos.X, y + def.size.Y / 2, pos.Z)

	-- Face/body details ride along with the body via welds.
	if def.details then
		ArtKit.weld(part, def.details)
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Size = UDim2.new(0, 60, 0, 8)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, def.size.Y / 2 + 1, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bg.BorderSizePixel = 0
	bg.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	fill.BorderSizePixel = 0
	fill.Parent = bg

	part.Parent = enemyFolder

	return { part = part, fill = fill, hp = def.hp, lastAttack = 0, dead = false, def = def }
end

local function spawnAt(entry)
	entry.enemy = buildEnemy(entry.pos, entry.def)
end

local function nearestPlayer(position, range)
	local closest, closestDist
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local dist = (root.Position - position).Magnitude
			if dist <= range and (not closestDist or dist < closestDist) then
				closest, closestDist = player, dist
			end
		end
	end
	return closest
end

-- Squash/stretch the body around its bottom (feet stay planted). stretch > 1
-- elongates for the air phase, < 1 flattens for the landing. Volume is
-- roughly preserved by widening as it flattens.
local function setSquash(enemy, stretch)
	local part = enemy.part
	local base = enemy.def.size
	local widen = 1 / math.sqrt(stretch)
	local bottom = part.Position.Y - part.Size.Y / 2
	local size = Vector3.new(base.X * widen, base.Y * stretch, base.Z * widen)
	local pos = Vector3.new(part.Position.X, bottom + size.Y / 2, part.Position.Z)
	part.Size = size
	part.CFrame = (part.CFrame - part.CFrame.Position) + pos
end

local HOP_SQUASH_TIME = 0.12 -- how long the landing squash holds

-- Hop locomotion: parabolic jumps toward the player with squash & stretch.
-- A hop in flight always finishes, even if the target left aggro range.
local function updateHop(enemy, dt, root, def)
	local hop = def.hop
	local part = enemy.part
	enemy.hopT = (enemy.hopT or 0) + dt
	local state = enemy.hopState or "wait"

	if state == "air" then
		local a = math.min(enemy.hopT / hop.time, 1)
		local pos = enemy.hopFrom:Lerp(enemy.hopTo, a)
			+ Vector3.new(0, math.sin(a * math.pi) * hop.height, 0)
		local look = Vector3.new(enemy.hopTo.X - enemy.hopFrom.X, 0, enemy.hopTo.Z - enemy.hopFrom.Z)
		if look.Magnitude > 0.05 then
			part.CFrame = CFrame.lookAt(pos, pos + look)
		else
			part.CFrame = (part.CFrame - part.CFrame.Position) + pos
		end
		setSquash(enemy, 1 + 0.25 * math.sin(a * math.pi))
		if a >= 1 then
			enemy.hopState = "squash"
			enemy.hopT = 0
			setSquash(enemy, 0.7)
		end
	elseif state == "squash" then
		if enemy.hopT >= HOP_SQUASH_TIME then
			setSquash(enemy, 1)
			enemy.hopState = "wait"
			enemy.hopT = 0
		end
	elseif root then -- "wait": grounded; face the player and wind up the next hop
		local from = part.Position
		local flatTarget = Vector3.new(root.Position.X, from.Y, root.Position.Z)
		local toTarget = flatTarget - from
		local planarDist = toTarget.Magnitude
		if planarDist > 0.05 then
			part.CFrame = CFrame.lookAt(from, flatTarget)
		end
		if planarDist > def.attackRange and enemy.hopT >= hop.pause then
			local to = from + toTarget.Unit * math.min(hop.distance, planarDist)
			enemy.hopFrom = from
			enemy.hopTo = Vector3.new(to.X, groundY(to.X, to.Z) + def.size.Y / 2, to.Z)
			enemy.hopState = "air"
			enemy.hopT = 0
		end
	end
end

local function updateEnemy(enemy, dt)
	if enemy.dead then
		return
	end
	local def = enemy.def
	local target = nearestPlayer(enemy.part.Position, def.aggroRange)
	local root
	if target then
		root = target.Character:FindFirstChild("HumanoidRootPart")
	end

	if def.movement == "hop" then
		updateHop(enemy, dt, root, def)
	elseif root then
		-- Walk toward the player along the ground plane, facing the way we move.
		local from = enemy.part.Position
		local flatTarget = Vector3.new(root.Position.X, from.Y, root.Position.Z)
		local toTarget = flatTarget - from
		local planarDist = toTarget.Magnitude
		if planarDist > def.attackRange then
			local pos = from + toTarget.Unit * math.min(def.walkSpeed * dt, planarDist)
			enemy.part.CFrame = CFrame.lookAt(pos, Vector3.new(flatTarget.X, pos.Y, flatTarget.Z))
		elseif planarDist > 0.05 then
			enemy.part.CFrame = CFrame.lookAt(from, flatTarget)
		end
	end

	-- Attack if in range and off cooldown.
	if root and (root.Position - enemy.part.Position).Magnitude <= def.attackRange then
		local now = os.clock()
		if now - enemy.lastAttack >= def.attackCooldown then
			enemy.lastAttack = now
			local humanoid = target.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid:TakeDamage(def.damage)
				HealthService.registerDamage(target) -- pause the player's regen
				for _, fn in ipairs(EnemyService.playerHitHandlers) do
					task.spawn(fn, def.lootSource, target)
				end
			end
		end
	end
end

local function killEnemy(entry, enemy, killer)
	if enemy.dead then
		return
	end
	enemy.dead = true
	local position = enemy.part.Position
	local lootSource = enemy.def.lootSource
	local respawn = enemy.def.respawn
	enemy.part:Destroy()
	entry.enemy = nil

	for _, fn in ipairs(EnemyService.killedHandlers) do
		task.spawn(fn, lootSource, position, killer)
	end

	task.delay(respawn, function()
		spawnAt(entry)
	end)
end

-- Finds the enemy entry backed by a given part (the client's focused target).
local function entryForPart(part)
	for _, entry in ipairs(spawns) do
		if entry.enemy and not entry.enemy.dead and entry.enemy.part == part then
			return entry
		end
	end
	return nil
end

-- Picks the enemy a weapon should hit: the player's focused target if it's a
-- valid enemy within reach, otherwise the nearest enemy in range.
local function targetFor(player, root, reach)
	local focused = entryForPart(TargetService.get(player))
	if focused and (focused.enemy.part.Position - root.Position).Magnitude <= reach then
		return focused, focused.enemy
	end

	local hitEntry, hitEnemy, hitDist
	for _, entry in ipairs(spawns) do
		local enemy = entry.enemy
		if enemy and not enemy.dead then
			local dist = (enemy.part.Position - root.Position).Magnitude
			if dist <= reach and (not hitDist or dist < hitDist) then
				hitEntry, hitEnemy, hitDist = entry, enemy, dist
			end
		end
	end
	return hitEntry, hitEnemy
end

local function dealDamage(entry, enemy, damage, killer)
	if not enemy or enemy.dead then
		return
	end
	enemy.hp -= damage
	updateHealthBar(enemy)
	if enemy.hp <= 0 then
		killEnemy(entry, enemy, killer)
	end
end

-- Spawns a glowing magic missile that flies from `fromPos` to the target part,
-- then runs `onArrive`. Anchored + non-colliding so it just replicates as a
-- cosmetic projectile to every client.
local function fireMissile(fromPos, targetPart, onArrive)
	local missile = Instance.new("Part")
	missile.Name = "MagicMissile"
	missile.Shape = Enum.PartType.Ball
	missile.Size = Vector3.new(1.2, 1.2, 1.2)
	missile.Color = Color3.fromRGB(150, 90, 255)
	missile.Material = Enum.Material.Neon
	missile.Anchored = true
	missile.CanCollide = false
	missile.CanQuery = false
	missile.Position = fromPos

	local light = Instance.new("PointLight")
	light.Color = missile.Color
	light.Range = 8
	light.Brightness = 3
	light.Parent = missile

	-- NOT in enemyFolder: the client targets every part in there, and a
	-- projectile must never steal focus from the enemy it flies at.
	missile.Parent = Workspace

	local destination = targetPart.Position
	local travel = math.clamp((destination - fromPos).Magnitude / MISSILE_SPEED, 0.05, 1)
	local tween = TweenService:Create(missile, TweenInfo.new(travel, Enum.EasingStyle.Linear), { Position = destination })
	tween.Completed:Connect(function()
		missile:Destroy()
		onArrive()
	end)
	tween:Play()
end

-- Called by ToolService when a "weapon" item is activated. Melee weapons hit
-- instantly and can auto-swing at the nearest enemy; ranged weapons (staff)
-- only fire at an explicitly focused target and launch a magic missile that
-- damages on impact.
local function onWeaponSwing(player, tool, def)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local reach = def.reach or DEFAULT_REACH
	local ranged = def.weaponType == "ranged"

	local hitEntry, hitEnemy
	if ranged then
		-- Ranged weapons require a focus: fire only at the locked target, and
		-- only while it's within reach. No target, no shot.
		local focused = entryForPart(TargetService.get(player))
		if focused and (focused.enemy.part.Position - root.Position).Magnitude <= reach then
			hitEntry, hitEnemy = focused, focused.enemy
		end
	else
		hitEntry, hitEnemy = targetFor(player, root, reach)
	end

	if not hitEnemy then
		return
	end

	local damage = def.damage or 10
	if ranged then
		-- Ranged magic costs mana; block the cast (and warn) when too low. Only
		-- charged here, once we know there's a valid target to fire at.
		local cost = def.manaCost or 0
		if cost > 0 and not ManaService.trySpend(player, cost) then
			local now = os.clock()
			if notifyRemote and now - (lastManaWarn[player.UserId] or 0) >= MANA_WARN_COOLDOWN then
				lastManaWarn[player.UserId] = now
				notifyRemote:FireClient(player, "Not enough mana")
			end
			return
		end
		fireMissile(root.Position + Vector3.new(0, 2, 0), hitEnemy.part, function()
			dealDamage(hitEntry, hitEnemy, damage, player)
		end)
	else
		dealDamage(hitEntry, hitEnemy, damage, player)
	end
end

function EnemyService.start()
	notifyRemote = Remotes.get("Notify")

	Players.PlayerRemoving:Connect(function(player)
		lastManaWarn[player.UserId] = nil
	end)

	enemyFolder = Instance.new("Folder")
	enemyFolder.Name = "Enemies"
	enemyFolder.Parent = Workspace

	for _, def in pairs(ENEMY_DEFS) do
		for _, pos in ipairs(def.spots) do
			local entry = { def = def, pos = pos, enemy = nil }
			table.insert(spawns, entry)
			spawnAt(entry)
		end
	end

	ToolService.registerActivated("weapon", onWeaponSwing)

	RunService.Heartbeat:Connect(function(dt)
		for _, entry in ipairs(spawns) do
			if entry.enemy then
				updateEnemy(entry.enemy, dt)
			end
		end
	end)
end

return EnemyService
