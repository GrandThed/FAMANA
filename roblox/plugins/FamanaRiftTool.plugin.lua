--[[
	FAMANA Rift Tool — Studio plugin that carves a rift (bottomless dark
	fracture) into hand-sculpted voxel terrain. Click to lay a path along
	the ground, tune width/depth/halo, hit CARVE:

	  * digs the crevasse (Air core down to a black Basalt floor, Basalt
	    walls, water cleared) with noise-wobbled organic edges,
	  * paints the corruption halo around it (Basalt -> Slate -> LeafyGrass
	    speckle rings — pair with TerrainGen.applyPalette() for the tints),
	  * builds the "infinitely deep" dressing (pure-black Neon void floor,
	    translucent depth layers, dark veil Beams, dust, low rumble) into
	    Workspace.Map.TerrainRiftDecor, so the map pull/deploy carries it
	    and the RiftEffects client rim-darkening finds it.

	Everything is one undo step (Ctrl+Z). INSTALL: copy into the local
	Studio plugins folder; source of truth is roblox/plugins/ in the repo.
]]

if not plugin then
	return
end

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local state = {
	points = {}, -- Vector3 clicks along the ground
	width = 24, -- studs, half of the open crevasse
	depth = 45, -- studs below the lowest click
	halo = 25, -- studs of corruption beyond the walls
}

local VOXEL = 4
local WALL_CORE = 0.6 -- influence >= this: dig to the floor
local WALL_PAINT = 0.25 -- influence >= this: repaint the wall column Basalt

local COLOR_SLATE = Color3.fromRGB(84, 74, 90)
local COLOR_LEAFY = Color3.fromRGB(94, 108, 62)
local COLOR_BASALT = Color3.fromRGB(13, 11, 17)

local toolbar = plugin:CreateToolbar("FAMANA Rifts")
local button = toolbar:CreateButton(
	"Rift Tool",
	"Click a path on the terrain, then carve a dark rift along it",
	"rbxassetid://6035067856")

local widget = plugin:CreateDockWidgetPluginGui(
	"FamanaRiftTool",
	DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Float, false, false, 250, 330, 220, 260))
widget.Title = "FAMANA Rift Tool"

-- ------------------------------------------------------------------- ui ---
local BG = Color3.fromRGB(46, 46, 46)
local FG = Color3.fromRGB(220, 220, 220)

local frame = Instance.new("Frame")
frame.Size = UDim2.fromScale(1, 1)
frame.BackgroundColor3 = BG
frame.BorderSizePixel = 0
frame.Parent = widget

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = frame

local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 8)
pad.PaddingRight = UDim.new(0, 8)
pad.PaddingTop = UDim.new(0, 8)
pad.Parent = frame

local order = 0
local function nextOrder()
	order += 1
	return order
end

local function label(text)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 18)
	l.BackgroundTransparency = 1
	l.TextColor3 = FG
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Font = Enum.Font.SourceSansBold
	l.TextSize = 14
	l.Text = text
	l.LayoutOrder = nextOrder()
	l.Parent = frame
	return l
end

local function makeButton(text, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 26)
	b.BackgroundColor3 = color or Color3.fromRGB(62, 62, 62)
	b.BorderSizePixel = 0
	b.TextColor3 = FG
	b.Font = Enum.Font.SourceSansBold
	b.TextSize = 14
	b.Text = text
	b.LayoutOrder = nextOrder()
	b.Parent = frame
	return b
end

local function numberRow(text, initial, apply)
	label(text)
	local t = Instance.new("TextBox")
	t.Size = UDim2.new(1, 0, 0, 24)
	t.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
	t.BorderSizePixel = 0
	t.TextColor3 = FG
	t.Font = Enum.Font.SourceSans
	t.TextSize = 14
	t.ClearTextOnFocus = false
	t.Text = tostring(initial)
	t.LayoutOrder = nextOrder()
	t.Parent = frame
	t.FocusLost:Connect(function()
		t.Text = tostring(apply(tonumber(t.Text)))
	end)
	return t
end

label("Click terrain to lay the rift path.")
local pointsLabel = label("Path: 0 points")
numberRow("Width (studs)", state.width, function(v)
	state.width = math.clamp(v or 24, 8, 120)
	return state.width
end)
numberRow("Depth (studs)", state.depth, function(v)
	state.depth = math.clamp(v or 45, 12, 200)
	return state.depth
end)
numberRow("Corruption halo (studs)", state.halo, function(v)
	state.halo = math.clamp(v or 25, 0, 150)
	return state.halo
end)
local undoButton = makeButton("Undo last point")
local clearButton = makeButton("Clear path")
local carveButton = makeButton("CARVE RIFT", Color3.fromRGB(140, 50, 60))

-- --------------------------------------------------------------- preview ---
local preview

local function refreshPreview()
	pointsLabel.Text = ("Path: %d points"):format(#state.points)
	if preview then
		preview:Destroy()
		preview = nil
	end
	if #state.points == 0 then
		return
	end
	-- lives under the Camera so it never saves or pulls
	preview = Instance.new("Folder")
	preview.Name = "FamanaRiftPreview"
	for i, p in ipairs(state.points) do
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(3, 3, 3)
		ball.Position = p
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanQuery = false
		ball.Material = Enum.Material.Neon
		ball.Color = Color3.fromRGB(200, 40, 40)
		ball.Parent = preview
		if i > 1 then
			local a, b = state.points[i - 1], p
			local seg = Instance.new("Part")
			seg.Anchored = true
			seg.CanCollide = false
			seg.CanQuery = false
			seg.Material = Enum.Material.Neon
			seg.Color = Color3.fromRGB(160, 30, 30)
			seg.Transparency = 0.3
			seg.Size = Vector3.new(state.width * 2, 0.4, (b - a).Magnitude)
			seg.CFrame = CFrame.lookAt((a + b) / 2, b)
			seg.Parent = preview
		end
	end
	preview.Parent = workspace.CurrentCamera
end

-- ----------------------------------------------------------------- carve ---
local function pathDistance(x, z)
	local best = math.huge
	local pts = state.points
	for i = 1, #pts - 1 do
		local ax, az = pts[i].X, pts[i].Z
		local vx, vz = pts[i + 1].X - ax, pts[i + 1].Z - az
		local t = math.clamp(
			((x - ax) * vx + (z - az) * vz) / (vx * vx + vz * vz), 0, 1)
		local dx, dz = x - (ax + vx * t), z - (az + vz * t)
		best = math.min(best, dx * dx + dz * dz)
	end
	return math.sqrt(best)
end

local function smoothstep(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- 1 inside the crevasse -> 0 outside; noise-wobbled organic edge
local function influence(x, z)
	local d = pathDistance(x, z)
		+ 5 * math.noise(x / 17, z / 17, 7.7)
	return smoothstep((state.width + 6 - d) / 6)
end

local buildDecor -- forward declaration (defined below)

local function carve()
	if #state.points < 2 then
		warn("[RiftTool] need at least 2 path points")
		return
	end
	local terrain = workspace.Terrain
	local recording = ChangeHistoryService:TryBeginRecording(
		"FamanaRiftTool", "Carve rift")

	local minY, maxY = math.huge, -math.huge
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, p in ipairs(state.points) do
		minY = math.min(minY, p.Y)
		maxY = math.max(maxY, p.Y)
		minX = math.min(minX, p.X)
		maxX = math.max(maxX, p.X)
		minZ = math.min(minZ, p.Z)
		maxZ = math.max(maxZ, p.Z)
	end
	local floorY = minY - state.depth
	local reach = state.width + state.halo + 14
	local regionYMin = floorY - 8
	local regionYMax = maxY + 60

	-- process in tiles so ReadVoxels stays within budget
	local TILE = 128
	for tx = minX - reach, maxX + reach, TILE do
		for tz = minZ - reach, maxZ + reach, TILE do
			local region = Region3.new(
				Vector3.new(tx, regionYMin, tz),
				Vector3.new(math.min(tx + TILE, maxX + reach), regionYMax,
					math.min(tz + TILE, maxZ + reach))
			):ExpandToGrid(VOXEL)
			local mats, occs = terrain:ReadVoxels(region, VOXEL)
			local size = mats.Size
			local corner = region.CFrame.Position - region.Size / 2
			local changed = false
			for ix = 1, size.X do
				local wx = corner.X + (ix - 1) * VOXEL + VOXEL / 2
				for iz = 1, size.Z do
					local wz = corner.Z + (iz - 1) * VOXEL + VOXEL / 2
					local t = influence(wx, wz)
					local dist = pathDistance(wx, wz)
					if t >= WALL_CORE then
						-- crevasse core: dig to the floor
						changed = true
						for iy = 1, size.Y do
							local wy = corner.Y + (iy - 1) * VOXEL
							if wy < floorY then
								mats[ix][iy][iz] = Enum.Material.Basalt
								occs[ix][iy][iz] = 1
							else
								mats[ix][iy][iz] = Enum.Material.Air
								occs[ix][iy][iz] = 0
							end
						end
					elseif t >= WALL_PAINT then
						-- wall band: keep the shape, repaint it black
						for iy = 1, size.Y do
							if occs[ix][iy][iz] > 0
								and mats[ix][iy][iz] ~= Enum.Material.Air
								and mats[ix][iy][iz] ~= Enum.Material.Water then
								mats[ix][iy][iz] = Enum.Material.Basalt
								changed = true
							end
						end
					elseif state.halo > 0 and dist < state.width + state.halo then
						-- corruption halo: repaint the SURFACE voxels only
						local corr = 1 - (dist - state.width) / state.halo
						local speckle = corr
							+ 0.3 * math.noise(wx / 9 + 31, wz / 9 - 17, 3.3)
						local paint
						if speckle > 0.85 then
							paint = Enum.Material.Basalt
						elseif speckle > 0.55 then
							paint = Enum.Material.Slate
						elseif speckle > 0.25 then
							paint = Enum.Material.LeafyGrass
						end
						if paint then
							for iy = size.Y, 1, -1 do
								if occs[ix][iy][iz] > 0.4
									and mats[ix][iy][iz] ~= Enum.Material.Air
									and mats[ix][iy][iz] ~= Enum.Material.Water then
									mats[ix][iy][iz] = paint
									if iy > 1 then
										mats[ix][math.max(iy - 1, 1)][iz] = paint
									end
									changed = true
									break
								end
							end
						end
					end
				end
			end
			if changed then
				terrain:WriteVoxels(region, VOXEL, mats, occs)
			end
		end
	end

	-- palette tints for the corruption materials (idempotent)
	terrain:SetMaterialColor(Enum.Material.Basalt, COLOR_BASALT)
	terrain:SetMaterialColor(Enum.Material.Slate, COLOR_SLATE)
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, COLOR_LEAFY)

	buildDecor(floorY)

	if recording then
		ChangeHistoryService:FinishRecording(
			recording, Enum.FinishRecordingOperation.Commit)
	end
	print(("[RiftTool] carved %d-point rift (floor y=%.0f)")
		:format(#state.points, floorY))
	state.points = {}
	refreshPreview()
end

-- ------------------------------------------------------------- dressing ---
-- Void dressing per path segment, parented under Workspace.Map so the map
-- pull/deploy carries it and the RiftEffects client finds it.
function buildDecor(floorY) -- local, forward-declared above carve()
	local map = workspace:FindFirstChild("Map")
	if not map then
		map = Instance.new("Folder")
		map.Name = "Map"
		map.Parent = workspace
	end
	local folder = map:FindFirstChild("TerrainRiftDecor")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "TerrainRiftDecor"
		folder.Parent = map
	end
	local widthStuds = state.width * 2 + 8
	local pts = state.points
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local rim = math.min(a.Y, b.Y)
		local mid = (a + b) / 2
		local len = (a - b).Magnitude + widthStuds * 0.6
		local function slab(name, y, transparency, material)
			local part = Instance.new("Part")
			part.Name = name
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CastShadow = false
			part.Color = Color3.new(0, 0, 0)
			part.Material = material
			part.Transparency = transparency
			part.Size = Vector3.new(widthStuds, 0.5, len)
			part.CFrame = CFrame.lookAt(
				Vector3.new(mid.X, y, mid.Z), Vector3.new(b.X, y, b.Z))
			part.Parent = folder
			return part
		end
		local floor = slab("VoidFloor", floorY + 3, 0, Enum.Material.Neon)
		slab("VoidLayer1", floorY + (rim - floorY) * 0.5, 0.25,
			Enum.Material.SmoothPlastic)
		slab("VoidLayer2", rim - 7, 0.55, Enum.Material.SmoothPlastic)

		local dust = Instance.new("ParticleEmitter")
		dust.Rate = math.clamp(len / 8, 4, 14)
		dust.Lifetime = NumberRange.new(6, 10)
		dust.Speed = NumberRange.new(1.5, 3)
		dust.SpreadAngle = Vector2.new(12, 12)
		dust.EmissionDirection = Enum.NormalId.Top
		dust.Color = ColorSequence.new(Color3.fromRGB(110, 95, 150))
		dust.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 0.1),
		})
		dust.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.7, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		dust.LightEmission = 0.25
		dust.LightInfluence = 0
		dust.Parent = floor

		if i % 3 == 1 then
			local rumble = Instance.new("Sound")
			rumble.Name = "RiftRumble"
			rumble.SoundId = "rbxassetid://131187945"
			rumble.PlaybackSpeed = 0.35
			rumble.Volume = 0.9
			rumble.Looped = true
			rumble.RollOffMode = Enum.RollOffMode.Inverse
			rumble.RollOffMinDistance = 15
			rumble.RollOffMaxDistance = 110
			rumble.Playing = true
			rumble.Parent = floor
		end

		local dir = (b - a).Unit
		local flatDir = Vector3.new(dir.X, 0, dir.Z).Unit
		local sideways = flatDir:Cross(Vector3.yAxis)
		local function veilAttachment(p)
			local attachment = Instance.new("Attachment")
			attachment.WorldCFrame = CFrame.fromMatrix(
				Vector3.new(p.X, rim - 3, p.Z), flatDir, sideways)
			attachment.Parent = floor
			return attachment
		end
		local veil = Instance.new("Beam")
		veil.Attachment0 = veilAttachment(a - flatDir * widthStuds * 0.3)
		veil.Attachment1 = veilAttachment(b + flatDir * widthStuds * 0.3)
		veil.FaceCamera = false
		veil.Width0 = widthStuds
		veil.Width1 = widthStuds
		veil.Color = ColorSequence.new(Color3.new(0, 0, 0))
		veil.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.3),
			NumberSequenceKeypoint.new(0.8, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		veil.LightInfluence = 0
		veil.Segments = 10
		veil.Parent = floor
	end
end

-- --------------------------------------------------------------- activate ---
local mouse
local connections = {}

local function enable()
	plugin:Activate(true)
	mouse = plugin:GetMouse()
	table.insert(connections, mouse.Button1Down:Connect(function()
		local ray = mouse.UnitRay
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local exclude = { workspace.CurrentCamera }
		local map = workspace:FindFirstChild("Map")
		if map and map:FindFirstChild("TerrainRiftDecor") then
			table.insert(exclude, map.TerrainRiftDecor)
		end
		params.FilterDescendantsInstances = exclude
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 10000, params)
		if hit then
			table.insert(state.points, hit.Position)
			refreshPreview()
		end
	end))
end

local function disable()
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	table.clear(connections)
end

undoButton.MouseButton1Click:Connect(function()
	table.remove(state.points)
	refreshPreview()
end)
clearButton.MouseButton1Click:Connect(function()
	state.points = {}
	refreshPreview()
end)
carveButton.MouseButton1Click:Connect(carve)

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	button:SetActive(widget.Enabled)
	if widget.Enabled then
		enable()
	else
		disable()
		state.points = {}
		refreshPreview()
	end
end)

plugin.Deactivation:Connect(disable)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	if not widget.Enabled then
		disable()
		button:SetActive(false)
	end
end)
