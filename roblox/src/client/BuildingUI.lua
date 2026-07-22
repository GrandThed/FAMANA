-- Building UI (Rust-Style Building Plan Client Controller).
-- Renders preview hologram, grid snapping (6 studs), rotation (R key), piece selector, and demolition mode (X key).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local BuildingConfig = require(Shared:WaitForChild("BuildingConfig"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local BuildingUI = {}

local function mouseWorldPoint()
	local mouseLoc = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLoc.X, mouseLoc.Y)
	local params = RaycastParams.new()
	local character = player.Character
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = character and { character } or {}

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	if result then
		return result.Position, result.Instance
	end
	return ray.Origin + ray.Direction * 50, nil
end

function BuildingUI.start()
	local placeRemote = Remotes.getFunction("PlaceStructure")
	local demolishRemote = Remotes.getFunction("DemolishStructure")

	local gui = Instance.new("ScreenGui")
	gui.Name = "BuildingUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 520, 0, 60)
	bar.Position = UDim2.new(0.5, 0, 0.88, 0)
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Visible = false
	bar.Parent = gui
	UIKit.stylePanel(bar)
	UIKit.addShadow(bar)
	UIKit.autoScale(bar)

	local hintLabel = UIKit.label(
		bar,
		"📐 PLANO DE CONSTRUCCIÓN — R: Rotar 90° | Click: Construir | X: Modo Demoler",
		12,
		Theme.Semantic.Currency,
		Theme.Font.BodyBold
	)
	hintLabel.Position = UDim2.new(0, 12, 0, 6)

	local btnContainer = Instance.new("Frame")
	btnContainer.Size = UDim2.new(1, -24, 0, 28)
	btnContainer.Position = UDim2.new(0, 12, 0, 26)
	btnContainer.BackgroundTransparency = 1
	btnContainer.Parent = bar

	local btnLayout = Instance.new("UIListLayout")
	btnLayout.FillDirection = Enum.FillDirection.Horizontal
	btnLayout.SortOrder = Enum.SortOrder.LayoutOrder
	btnLayout.Padding = UDim.new(0, 6)
	btnLayout.Parent = btnContainer

	local activePieceId = "piso_madera"
	local rotationY = 0
	local active = false
	local previewPart = nil
	local renderConn = nil

	local piecesOrder = { "piso_madera", "pared_madera", "puerta_madera", "pared_ventana", "techo_madera" }

	for _, pId in ipairs(piecesOrder) do
		local pDef = BuildingConfig.getPiece(pId)
		local btn = UIKit.button(
			btnContainer,
			string.format("%s %s", pDef.icon or "", pDef.name),
			11,
			Theme.Semantic.SurfaceWell,
			Theme.Semantic.TextTitle
		)
		btn.Size = UDim2.new(0, 95, 1, 0)
		btn.Activated:Connect(function()
			activePieceId = pId
			Sfx.play("uiClick")
		end)
	end

	local function cleanupPreview()
		if previewPart then
			previewPart:Destroy()
			previewPart = nil
		end
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
	end

	local function startBuildingMode()
		active = true
		bar.Visible = true
		cleanupPreview()

		previewPart = Instance.new("Part")
		previewPart.Name = "BuildingHologram"
		previewPart.Color = Color3.fromRGB(0, 200, 255)
		previewPart.Material = Enum.Material.ForceField
		previewPart.Transparency = 0.4
		previewPart.CanCollide = false
		previewPart.Anchored = true
		previewPart.Parent = Workspace

		renderConn = RunService.RenderStepped:Connect(function()
			if not active or not previewPart then
				return
			end
			local point = mouseWorldPoint()
			local grid = BuildingConfig.GRID_SIZE
			local snappedX = math.floor(point.X / grid + 0.5) * grid
			local snappedZ = math.floor(point.Z / grid + 0.5) * grid
			local snappedY = math.floor(point.Y / 5 + 0.5) * 5

			local pDef = BuildingConfig.getPiece(activePieceId)
			if pDef then
				previewPart.Size = pDef.size
				local pos = Vector3.new(snappedX, snappedY, snappedZ) + (pDef.offset or Vector3.zero)
				previewPart.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(rotationY), 0)
			end
		end)
	end

	local function stopBuildingMode()
		active = false
		bar.Visible = false
		cleanupPreview()
	end

	-- Watch for holding plano_construccion
	RunService.Heartbeat:Connect(function()
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		local isHoldingPlan = tool and tool:GetAttribute("itemId") == "plano_construccion"

		if isHoldingPlan and not active then
			startBuildingMode()
		elseif not isHoldingPlan and active then
			stopBuildingMode()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or not active then
			return
		end

		if input.KeyCode == Enum.KeyCode.R then
			rotationY = (rotationY + 90) % 360
			Sfx.play("uiClick")
		elseif input.KeyCode == Enum.KeyCode.X then
			-- Demolish mode
			local point, targetInst = mouseWorldPoint()
			local targetModel = targetInst and targetInst:FindFirstAncestorWhichIsA("Model")
			if targetModel and targetModel:GetAttribute("PieceId") then
				demolishRemote:InvokeServer(targetModel)
				Sfx.play("spellDenied")
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			if previewPart then
				local point = mouseWorldPoint()
				local grid = BuildingConfig.GRID_SIZE
				local snappedX = math.floor(point.X / grid + 0.5) * grid
				local snappedZ = math.floor(point.Z / grid + 0.5) * grid
				local snappedY = math.floor(point.Y / 5 + 0.5) * 5
				local pos = Vector3.new(snappedX, snappedY, snappedZ)

				Sfx.play("equip")
				placeRemote:InvokeServer({
					pieceId = activePieceId,
					position = pos,
					rotationY = rotationY,
				})
			end
		end
	end)
end

return BuildingUI
