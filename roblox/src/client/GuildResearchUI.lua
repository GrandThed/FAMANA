-- Guild Research UI (Warframe Dojo Tech Tree Style).
-- Client interface for browsing guild research labs, inspecting project costs,
-- contributing resources, and viewing overall Guild Level progression.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Items = require(Shared:WaitForChild("Items"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local GuildResearchUI = {}

function GuildResearchUI.start()
	local openResearchRemote = Remotes.get("OpenGuildResearch")
	local getResearchRemote = Remotes.getFunction("GetGuildResearch")
	local contributeRemote = Remotes.getFunction("ContributeGuildResearch")

	local gui = Instance.new("ScreenGui")
	gui.Name = "GuildResearchUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 680, 0, 480)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Visible = false
	panel.Parent = gui
	UIKit.stylePanel(panel)
	UIKit.addShadow(panel)
	UIKit.autoScale(panel)

	-- Header
	local header = UIKit.label(panel, "🔬 Investigaciones del Gremio", 18, Theme.Semantic.TextTitle, Theme.Font.DisplayBold)
	header.Position = UDim2.new(0, 20, 0, 16)

	local levelLabel = UIKit.label(panel, "Gremio Nivel 1 (0 XP)", 13, Theme.Semantic.Currency, Theme.Font.BodyBold)
	levelLabel.Position = UDim2.new(0, 20, 0, 42)

	local closeBtn = UIKit.button(panel, "✕", 14, Theme.Semantic.SurfaceWell, Theme.Semantic.TextBody)
	closeBtn.Size = UDim2.new(0, 32, 0, 32)
	closeBtn.Position = UDim2.new(1, -44, 0, 16)
	closeBtn.Activated:Connect(function()
		panel.Visible = false
	end)

	-- Content Area
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -40, 1, -90)
	scroll.Position = UDim2.new(0, 20, 0, 70)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 14)
	listLayout.Parent = scroll

	local function renderResearchData(data)
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		if not data or not data.ok then
			levelLabel.Text = "Debes pertenecer a un gremio"
			return
		end

		levelLabel.Text = string.format("Gremio Nivel %d (%d XP)", data.guildLevel or 1, data.guildXp or 0)

		local totalCanvasH = 0

		for _, lab in ipairs(data.labs or {}) do
			local labFrame = Instance.new("Frame")
			labFrame.Size = UDim2.new(1, -10, 0, 40)
			labFrame.AutomaticSize = Enum.AutomaticSize.Y
			labFrame.BackgroundColor3 = Theme.Semantic.SurfaceWell
			labFrame.BorderSizePixel = 0
			labFrame.Parent = scroll
			UIKit.stylePanel(labFrame)

			local labTitle = UIKit.label(
				labFrame,
				string.format("%s %s", lab.icon or "🔬", lab.name or "Laboratorio"),
				15,
				Theme.Semantic.TextTitle,
				Theme.Font.DisplayBold
			)
			labTitle.Position = UDim2.new(0, 12, 0, 10)

			local projLayout = Instance.new("UIListLayout")
			projLayout.SortOrder = Enum.SortOrder.LayoutOrder
			projLayout.Padding = UDim.new(0, 8)
			projLayout.Parent = labFrame

			local headerSpacer = Instance.new("Frame")
			headerSpacer.Size = UDim2.new(1, 0, 0, 32)
			headerSpacer.BackgroundTransparency = 1
			headerSpacer.Parent = labFrame

			for _, proj in ipairs(lab.projects or {}) do
				local projCard = Instance.new("Frame")
				projCard.Size = UDim2.new(1, -24, 0, 110)
				projCard.Position = UDim2.new(0, 12, 0, 0)
				projCard.BackgroundColor3 = Theme.Semantic.SurfaceElevated
				projCard.BorderSizePixel = 0
				projCard.Parent = labFrame
				UIKit.stylePanel(projCard)

				local statusText = proj.completed and "✓ COMPLETADO" or "EN PROGRESO"
				local statusColor = proj.completed and Theme.Semantic.Good or Theme.Semantic.Currency

				local pTitle = UIKit.label(projCard, proj.name, 14, Theme.Semantic.TextTitle, Theme.Font.BodyBold)
				pTitle.Position = UDim2.new(0, 12, 0, 8)

				local pStatus = UIKit.label(projCard, statusText, 11, statusColor, Theme.Font.BodyBold)
				pStatus.Position = UDim2.new(1, -120, 0, 8)

				local pDesc = UIKit.label(projCard, proj.description or "", 12, Theme.Semantic.TextSecondary)
				pDesc.Size = UDim2.new(1, -24, 0, 30)
				pDesc.Position = UDim2.new(0, 12, 0, 26)
				pDesc.TextWrapped = true

				-- Render cost requirements
				local xOffset = 12
				for rKey, reqAmount in pairs(proj.cost or {}) do
					local fundedAmount = (proj.funded and proj.funded[rKey]) or 0
					local rDef = Items.get(rKey)
					local rName = rKey == "gold" and "Oro" or (rDef and rDef.name or rKey)

					local reqBtn = UIKit.button(
						projCard,
						string.format("%s: %d/%d  [+Aportar]", rName, fundedAmount, reqAmount),
						11,
						proj.completed and Theme.Semantic.SurfaceWell or Theme.Semantic.Accent,
						Theme.Semantic.TextTitle
					)
					reqBtn.Size = UDim2.new(0, 180, 0, 28)
					reqBtn.Position = UDim2.new(0, xOffset, 0, 68)
					xOffset += 190

					if not proj.completed and fundedAmount < reqAmount then
						reqBtn.Activated:Connect(function()
							Sfx.play("uiClick")
							contributeRemote:InvokeServer({
								projectId = proj.id,
								resourceKey = rKey,
								amount = 5,
							})
							-- Refresh data
							task.delay(0.2, function()
								local updated = getResearchRemote:InvokeServer()
								renderResearchData(updated)
							end)
						end)
					end
				end
			end
		end

		scroll.CanvasSize = UDim2.new(0, 0, 0, 600)
	end

	local function refresh()
		local data = getResearchRemote:InvokeServer()
		renderResearchData(data)
	end

	openResearchRemote.OnClientEvent:Connect(function()
		panel.Visible = true
		refresh()
	end)

	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape and panel.Visible then
			panel.Visible = false
		end
	end)
end

return GuildResearchUI
