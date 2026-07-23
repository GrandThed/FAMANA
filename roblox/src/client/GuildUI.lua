-- Guild panel (G key / top-right button). Two states depending on whether
-- the local player is currently in a guild (GuildId attribute):
--   - no guild  -> a small "found a guild" form (name + tag)
--   - in guild  -> roster (with Kick, leader-only), an invite list (leader-
--     only, mirrors PartyUI's candidate scan), a Leave button, and a live
--     chat log
--
-- The roster comes from the RequestGuild RemoteFunction (a live backend
-- read — same pattern as QuestLogUI's RequestQuestLog) since it needs
-- offline members too, which attributes alone can't give us. Chat is
-- fire-and-forget over GuildChat/GuildChatReceived, appended straight to
-- the log with no history fetch, same spirit as Party's Notify toasts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent.Theme)
local TopRightMenu = require(script.Parent.TopRightMenu)
local UIKit = require(script.Parent.UIKit)
local Sfx = require(script.Parent.Sfx)
local GuildBankUI = require(script.Parent.GuildBankUI)

local player = Players.LocalPlayer

local GuildUI = {}

local COLORS = {
	section = Theme.Semantic.SurfaceWell,
	line = Theme.Semantic.BorderHair,
	tile = Theme.Color.Ink900,
	accent = Theme.Color.Ember300,
	officer = Theme.Semantic.TextSecondary,
	good = Theme.Semantic.Good,
	text = Theme.Semantic.TextBody,
	textDim = Theme.Semantic.TextMuted,
}

local PANEL_W = 440
local PANEL_H = 582
local MAX_CHAT_LINES = 60

local function makeLabel(parent, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font or Theme.Font.Body
	label.TextSize = size
	label.TextColor3 = color or COLORS.text
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = parent
	return label
end

local function makeTextBox(parent, placeholder)
	local box = Instance.new("TextBox")
	box.BackgroundColor3 = Theme.Color.Ink900
	box.BorderSizePixel = 0
	box.FontFace = Theme.Font.Body
	box.TextSize = Theme.Text.Body
	box.TextColor3 = COLORS.text
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = COLORS.textDim
	box.Text = ""
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Parent = parent

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = box

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = COLORS.line
	stroke.Parent = box

	return box
end

local function makeScrollList(parent, size, position)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = size
	scroll.Position = position
	scroll.BackgroundColor3 = COLORS.section
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = COLORS.line
	stroke.Parent = scroll

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = scroll

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = scroll

	return scroll
end

local function clearChildren(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

function GuildUI.start()
	local guildCreate = Remotes.get("GuildCreate")
	local guildInvite = Remotes.get("GuildInvite")
	local guildInviteReceived = Remotes.get("GuildInviteReceived")
	local guildRespond = Remotes.get("GuildRespond")
	local guildKick = Remotes.get("GuildKick")
	local guildSetRole = Remotes.get("GuildSetRole")
	local guildLeave = Remotes.get("GuildLeave")
	local guildChat = Remotes.get("GuildChat")
	local guildChatReceived = Remotes.get("GuildChatReceived")
	local requestGuild = Remotes.getFunction("RequestGuild")

	local gui = Instance.new("ScreenGui")
	gui.Name = "GuildUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Visible = false
	panel.Parent = gui
	UIKit.stylePanel(panel)
	UIKit.addShadow(panel)
	UIKit.autoScale(panel)

	local title = makeLabel(panel, "Guild", Theme.Text.Title, Theme.Semantic.TextTitle, Theme.Font.DisplayBold)
	title.Size = UDim2.new(1, -80, 0, 30)
	title.Position = UDim2.new(0, 12, 0, 4)

	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -6, 0, 6)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	-- ---- "no guild yet" state: a small founding form ----------------------
	local createSection = Instance.new("Frame")
	createSection.BackgroundTransparency = 1
	createSection.Size = UDim2.new(1, -24, 0, 160)
	createSection.Position = UDim2.new(0, 12, 0, 44)
	createSection.Parent = panel

	local createHint = makeLabel(
		createSection,
		"You're not in a guild. Found one:",
		13,
		COLORS.textDim,
		Theme.Font.BodyItalic
	)
	createHint.Size = UDim2.new(1, 0, 0, 20)

	local nameBox = makeTextBox(createSection, "Guild name (3-24 chars)")
	nameBox.Size = UDim2.new(1, 0, 0, 32)
	nameBox.Position = UDim2.new(0, 0, 0, 28)

	local tagBox = makeTextBox(createSection, "Tag (2-5 chars)")
	tagBox.Size = UDim2.new(1, 0, 0, 32)
	tagBox.Position = UDim2.new(0, 0, 0, 68)

	local foundBtn = UIKit.primaryButton(createSection, "Found Guild")
	foundBtn.Size = UDim2.new(1, 0, 0, 34)
	foundBtn.Position = UDim2.new(0, 0, 0, 110)
	foundBtn.Activated:Connect(function()
		guildCreate:FireServer({ name = nameBox.Text, tag = tagBox.Text })
	end)

	-- ---- "in a guild" state -------------------------------------------------
	local guildHeader = makeLabel(panel, "", Theme.Text.Lg, COLORS.accent, Theme.Font.DisplayBold)
	guildHeader.Size = UDim2.new(1, -24, 0, 22)
	guildHeader.Position = UDim2.new(0, 12, 0, 44)

	local territoryLabel = makeLabel(panel, "", 12, COLORS.textDim)
	territoryLabel.Size = UDim2.new(1, -24, 0, 18)
	territoryLabel.Position = UDim2.new(0, 12, 0, 68)

	local rosterLabel = makeLabel(panel, "Members", 12, COLORS.textDim)
	rosterLabel.Size = UDim2.new(1, -24, 0, 16)
	rosterLabel.Position = UDim2.new(0, 12, 0, 92)

	local rosterList = makeScrollList(panel, UDim2.new(1, -24, 0, 130), UDim2.new(0, 12, 0, 110))

	local inviteLabel = makeLabel(panel, "Invite (leader only)", 12, COLORS.textDim)
	inviteLabel.Size = UDim2.new(1, -24, 0, 16)
	inviteLabel.Position = UDim2.new(0, 12, 0, 248)

	local inviteScroll = makeScrollList(panel, UDim2.new(1, -24, 0, 80), UDim2.new(0, 12, 0, 266))

	local bankHintLabel = makeLabel(panel, "📦 Banco: usá un Cofre de Gremio en tu acampada", 11, COLORS.textDim)
	bankHintLabel.Size = UDim2.new(1, -124, 0, 28)
	bankHintLabel.Position = UDim2.new(0, 12, 0, 352)

	local leaveBtn = UIKit.ghostButton(panel, "Leave Guild")
	leaveBtn.Size = UDim2.new(0, 100, 0, 28)
	leaveBtn.Position = UDim2.new(1, -112, 0, 352)
	leaveBtn.Activated:Connect(function()
		guildLeave:FireServer()
	end)

	local chatLabel = makeLabel(panel, "Guild Chat", 12, COLORS.textDim)
	chatLabel.Size = UDim2.new(1, -24, 0, 16)
	chatLabel.Position = UDim2.new(0, 12, 0, 388)

	local chatLog = makeScrollList(panel, UDim2.new(1, -24, 0, 130), UDim2.new(0, 12, 0, 406))

	local chatInputBox = makeTextBox(panel, "Say something to your guild...")
	chatInputBox.Size = UDim2.new(1, -84, 0, 30)
	chatInputBox.Position = UDim2.new(0, 12, 1, -42)

	local sendBtn = UIKit.primaryButton(panel, "Send")
	sendBtn.Size = UDim2.new(0, 64, 0, 30)
	sendBtn.Position = UDim2.new(1, -76, 1, -42)

	local function sendChat()
		local text = chatInputBox.Text
		if text and #text > 0 then
			guildChat:FireServer(text)
			chatInputBox.Text = ""
		end
	end
	sendBtn.Activated:Connect(sendChat)
	chatInputBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			sendChat()
		end
	end)

	local chatLineCounter = 0

	local function appendChatLine(fromName, text)
		chatLineCounter += 1
		local line = makeLabel(chatLog, string.format("%s: %s", fromName, text), 12, COLORS.text)
		line.Size = UDim2.new(1, 0, 0, 0)
		line.AutomaticSize = Enum.AutomaticSize.Y
		line.LayoutOrder = chatLineCounter

		local rows = {}
		for _, child in ipairs(chatLog:GetChildren()) do
			if child:IsA("TextLabel") then
				table.insert(rows, child)
			end
		end
		if #rows > MAX_CHAT_LINES then
			table.sort(rows, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			rows[1]:Destroy()
		end

		task.defer(function()
			chatLog.CanvasPosition = Vector2.new(0, math.huge)
		end)
	end

	local function clearChat()
		clearChildren(chatLog)
	end

	guildChatReceived.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" or typeof(payload.text) ~= "string" then
			return
		end
		appendChatLine(tostring(payload.fromName or "?"), payload.text)
	end)

	-- ---- invite popup (accept/decline), same pattern as PartyUI -----------
	local invitePopup = Instance.new("Frame")
	invitePopup.Size = UDim2.new(0, 320, 0, 96)
	invitePopup.Position = UDim2.new(0.5, -160, 0, 90)
	invitePopup.Visible = false
	invitePopup.Parent = gui
	UIKit.stylePanel(invitePopup)
	UIKit.addShadow(invitePopup)

	local popupText = makeLabel(invitePopup, "", 14, COLORS.text)
	popupText.Size = UDim2.new(1, -20, 0, 40)
	popupText.Position = UDim2.new(0, 10, 0, 8)

	local acceptBtn = UIKit.primaryButton(invitePopup, "Accept")
	acceptBtn.Size = UDim2.new(0.45, -15, 0, 30)
	acceptBtn.Position = UDim2.new(0, 10, 1, -40)

	local declineBtn = UIKit.ghostButton(invitePopup, "Decline")
	declineBtn.Size = UDim2.new(0.45, -15, 0, 30)
	declineBtn.Position = UDim2.new(0.55, 5, 1, -40)

	local currentInvite
	local currentInviteToken = 0

	local function hideInvitePopup()
		invitePopup.Visible = false
		currentInvite = nil
	end

	guildInviteReceived.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" or typeof(payload.fromUserId) ~= "number" then
			return
		end
		currentInvite = { fromUserId = payload.fromUserId }
		currentInviteToken += 1
		local token = currentInviteToken
		popupText.Text = string.format(
			"%s invited you to join [%s] %s.",
			tostring(payload.fromName or "Someone"),
			tostring(payload.guildTag or "?"),
			tostring(payload.guildName or "a guild")
		)
		invitePopup.Visible = true
		local timeout = tonumber(payload.timeout) or 30
		task.delay(timeout, function()
			if currentInviteToken == token then
				hideInvitePopup()
			end
		end)
	end)

	acceptBtn.Activated:Connect(function()
		if currentInvite then
			guildRespond:FireServer({ fromUserId = currentInvite.fromUserId, accept = true })
			hideInvitePopup()
		end
	end)
	declineBtn.Activated:Connect(function()
		if currentInvite then
			guildRespond:FireServer({ fromUserId = currentInvite.fromUserId, accept = false })
			hideInvitePopup()
		end
	end)

	-- ---- roster / invite rows ----------------------------------------------
	local function buildRosterRow(member, iAmLeader, iAmOfficer)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 30)
		row.BackgroundColor3 = COLORS.tile
		row.BackgroundTransparency = 0.35
		row.BorderSizePixel = 0
		row.Parent = rosterList

		local isSelf = tostring(member.playerId) == tostring(player.UserId)
		local isLeaderRow = member.isLeader
		local isOfficerRow = member.role == "officer"

		local rankPrefix = isLeaderRow and "[L] " or (isOfficerRow and "[O] " or "")
		local label = string.format("%s%s%s", rankPrefix, member.username, isSelf and " (you)" or "")
		local nameColor = isLeaderRow and COLORS.accent or (isOfficerRow and COLORS.officer or COLORS.text)
		local nameLabel = makeLabel(row, label, 13, nameColor)
		nameLabel.Size = UDim2.new(0, 190, 1, 0)
		nameLabel.Position = UDim2.new(0, 8, 0, 0)

		local statusDot = makeLabel(row, member.online and "●" or "○", 12, member.online and COLORS.good or COLORS.textDim)
		statusDot.Size = UDim2.new(0, 16, 1, 0)
		statusDot.Position = UDim2.new(0, 202, 0, 0)

		local rightEdge = -6

		local canKick = not isSelf and not isLeaderRow and (iAmLeader or (iAmOfficer and not isOfficerRow))
		if canKick then
			local kickBtn = UIKit.ghostButton(row, "Kick")
			kickBtn.Size = UDim2.new(0, 50, 0, 20)
			kickBtn.Position = UDim2.new(1, rightEdge - 50, 0.5, -10)
			kickBtn.Activated:Connect(function()
				guildKick:FireServer(tonumber(member.playerId))
			end)
			rightEdge -= 54
		end

		if iAmLeader and not isSelf and not isLeaderRow then
			local roleBtn = UIKit.ghostButton(row, isOfficerRow and "Demote" or "Promote")
			roleBtn.Size = UDim2.new(0, 62, 0, 20)
			roleBtn.Position = UDim2.new(1, rightEdge - 62, 0.5, -10)
			roleBtn.Activated:Connect(function()
				guildSetRole:FireServer({
					targetUserId = tonumber(member.playerId),
					role = isOfficerRow and "member" or "officer",
				})
			end)
			rightEdge -= 66
		end

		return row
	end

	local function buildInviteRow(candidate)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 28)
		row.BackgroundColor3 = COLORS.tile
		row.BackgroundTransparency = 0.35
		row.BorderSizePixel = 0
		row.Parent = inviteScroll

		local nameLabel = makeLabel(row, candidate.Name, 13, COLORS.text)
		nameLabel.Size = UDim2.new(0.6, 0, 1, 0)
		nameLabel.Position = UDim2.new(0, 8, 0, 0)

		local inviteBtn = UIKit.ghostButton(row, "Invite")
		inviteBtn.Size = UDim2.new(0, 60, 0, 20)
		inviteBtn.Position = UDim2.new(1, -66, 0.5, -10)
		inviteBtn.Activated:Connect(function()
			guildInvite:FireServer(candidate.UserId)
		end)

		return row
	end

	-- ---- master refresh ------------------------------------------------------
	local isOpen = false

	local function render()
		local guildId = player:GetAttribute("GuildId")
		local inGuild = guildId ~= nil

		createSection.Visible = not inGuild
		guildHeader.Visible = inGuild
		territoryLabel.Visible = inGuild
		rosterLabel.Visible = inGuild
		rosterList.Visible = inGuild
		leaveBtn.Visible = inGuild
		bankHintLabel.Visible = inGuild
		chatLabel.Visible = inGuild
		chatLog.Visible = inGuild
		chatInputBox.Visible = inGuild
		sendBtn.Visible = inGuild

		if not inGuild then
			inviteLabel.Visible = false
			inviteScroll.Visible = false
			clearChildren(rosterList)
			clearChildren(inviteScroll)
			return
		end

		local iAmLeader = player:GetAttribute("GuildLeader") == true
		guildHeader.Text = string.format("[%s] %s", tostring(player:GetAttribute("GuildTag")), tostring(player:GetAttribute("GuildName")))
		territoryLabel.Text = "Territorio: cargando..."
		territoryLabel.TextColor3 = COLORS.textDim

		inviteLabel.Visible = iAmLeader
		inviteScroll.Visible = iAmLeader

		task.spawn(function()
			local ok, guild = pcall(function()
				return requestGuild:InvokeServer()
			end)
			if not ok or typeof(guild) ~= "table" or typeof(guild.members) ~= "table" then
				return
			end
			if tostring(guild.id) ~= tostring(player:GetAttribute("GuildId")) then
				return
			end

			local territories = typeof(guild.territories) == "table" and guild.territories or {}
			if #territories > 0 then
				local names = {}
				for _, t in ipairs(territories) do
					table.insert(names, string.format("%s (%s)", t.name, t.cell))
				end
				territoryLabel.Text = string.format("🏰 Territorio: %s", table.concat(names, ", "))
				territoryLabel.TextColor3 = COLORS.accent
				guildHeader.Text = string.format(
					"[%s] %s 🏰",
					tostring(player:GetAttribute("GuildTag")),
					tostring(player:GetAttribute("GuildName"))
				)
			else
				territoryLabel.Text = "Sin territorio — reclamá un asentamiento derrotando a su guardián"
				territoryLabel.TextColor3 = COLORS.textDim
			end

			clearChildren(rosterList)
			local iAmOfficer = player:GetAttribute("GuildOfficer") == true
			for _, member in ipairs(guild.members) do
				local onlinePlayer = Players:GetPlayerByUserId(tonumber(member.playerId))
				buildRosterRow({
					playerId = member.playerId,
					username = member.username,
					online = onlinePlayer ~= nil,
					isLeader = tostring(member.playerId) == tostring(guild.leaderId),
					role = member.role,
				}, iAmLeader, iAmOfficer)
			end
		end)

		if iAmLeader then
			clearChildren(inviteScroll)
			for _, other in ipairs(Players:GetPlayers()) do
				if other ~= player and other:GetAttribute("GuildId") == nil then
					buildInviteRow(other)
				end
			end
		end
	end

	local function setOpen(open)
		isOpen = open
		panel.Visible = open
		Sfx.play(open and "panelOpen" or "panelClose")
		if open then
			render()
		end
	end
	local function toggle()
		setOpen(not isOpen)
	end

	closeBtn.Activated:Connect(function()
		setOpen(false)
	end)

	local openBtn = TopRightMenu.addButton("Guild (G)", 5)
	openBtn.Name = "GuildButton"
	openBtn.Activated:Connect(toggle)

	ContextActionService:BindAction("ToggleGuildPanel", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.G)

	local wasInGuild = player:GetAttribute("GuildId") ~= nil
	local function onGuildAttributeChanged()
		local nowInGuild = player:GetAttribute("GuildId") ~= nil
		if wasInGuild and not nowInGuild then
			clearChat()
		end
		wasInGuild = nowInGuild
		if isOpen then
			render()
		end
	end
	player:GetAttributeChangedSignal("GuildId"):Connect(onGuildAttributeChanged)
	player:GetAttributeChangedSignal("GuildLeader"):Connect(onGuildAttributeChanged)

	local function watchOther(p)
		p:GetAttributeChangedSignal("GuildId"):Connect(function()
			if isOpen then
				render()
			end
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			watchOther(p)
		end
	end
	Players.PlayerAdded:Connect(function(p)
		if p ~= player then
			watchOther(p)
		end
		if isOpen then
			render()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if isOpen then
			render()
		end
	end)

	render()
end

return GuildUI
