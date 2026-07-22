-- Guilds: persisted in the backend (`guilds` / `guild_members` tables), so
-- unlike Party this survives server restarts and players logging off. Two
-- roles only for the MVP — leader and member; see docs on extending with
-- officers later (that's an additive column on guild_members, not a
-- reshape).
--
-- Membership replicates to every client through Player attributes (GuildId /
-- GuildName / GuildTag / GuildLeader), same mechanism as Party — no
-- roster-push remote needed. Remotes carry the action verbs (create/invite/
-- respond/kick/leave/chat) plus toasts, reusing the existing "Notify"
-- remote.
--
-- Invites are in-memory and ephemeral (same as Party's pendingInvites) —
-- only membership itself is persisted. A guild's online roster for chat/
-- broadcast purposes is derived by scanning Players:GetPlayers() for a
-- matching GuildId attribute, not tracked separately — the backend is
-- already the single source of truth for who's actually a member.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Settlements = require(Shared:WaitForChild("Settlements"))
local BackendService = require(script.Parent.BackendService)
local PlayerService = require(script.Parent.PlayerService)

local GUILD_CONFIG = Config.Guild
local INVITE_TIMEOUT = GUILD_CONFIG.inviteTimeout

local GuildService = {}

-- [targetUserId] = { fromUserId, fromName, guildId, guildName, guildTag, expires }
local pendingInvites = {}

local notifyRemote -- RemoteEvent, resolved in start()
local guildInviteReceivedRemote -- RemoteEvent, resolved in start()
local guildChatReceivedRemote -- RemoteEvent, resolved in start()

local function notify(player, message)
	if player and notifyRemote then
		notifyRemote:FireClient(player, message)
	end
end

local function trimmed(s)
	if typeof(s) ~= "string" then
		return nil
	end
	local t = s:gsub("^%s+", ""):gsub("%s+$", "")
	return t ~= "" and t or nil
end

-- Every online player currently attributed to `guildId` (source of truth is
-- the backend; this is just "who's around right now to talk to").
local function onlineMembers(guildId)
	local members = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr:GetAttribute("GuildId") == guildId then
			table.insert(members, plr)
		end
	end
	return members
end

local function broadcast(guildId, message, exceptUserId)
	for _, plr in ipairs(onlineMembers(guildId)) do
		if plr.UserId ~= exceptUserId then
			notify(plr, message)
		end
	end
end

-- Finds `player`'s own row in `guild.members` to read their rank. Falls
-- back to "member" if the roster doesn't have them for some reason (should
-- only happen for a stale/in-flight guild object) — never treat a missing
-- row as "officer".
local function myRole(player, guild)
	for _, member in ipairs(guild.members) do
		if tostring(member.playerId) == tostring(player.UserId) then
			return member.role
		end
	end
	return "member"
end

local function setGuildAttributes(player, guild)
	player:SetAttribute("GuildId", tonumber(guild.id))
	player:SetAttribute("GuildName", guild.name)
	player:SetAttribute("GuildTag", guild.tag)
	local isLeader = tostring(guild.leaderId) == tostring(player.UserId)
	player:SetAttribute("GuildLeader", isLeader)
	-- Not meaningful for the leader (who already passes every isLeader
	-- check first) — only set true for an actual officer-ranked member.
	player:SetAttribute("GuildOfficer", not isLeader and myRole(player, guild) == "officer")
end

local function clearGuildAttributes(player)
	player:SetAttribute("GuildId", nil)
	player:SetAttribute("GuildName", nil)
	player:SetAttribute("GuildTag", nil)
	player:SetAttribute("GuildLeader", nil)
	player:SetAttribute("GuildOfficer", nil)
end

-- Re-applies attributes (notably GuildLeader) to every currently-online
-- member after a roster change (join/kick/leadership transfer) — cheap,
-- guilds aren't expected to be huge, and this only runs on membership edits.
local function refreshOnlineAttributes(guild)
	for _, plr in ipairs(Players:GetPlayers()) do
		for _, member in ipairs(guild.members) do
			if tostring(member.playerId) == tostring(plr.UserId) then
				setGuildAttributes(plr, guild)
				break
			end
		end
	end
end

function GuildService.getGuildId(player)
	return player:GetAttribute("GuildId")
end

-- Public wrapper around the internal broadcast helper — for systems outside
-- this file (e.g. SettlementService announcing a capture) that need to
-- notify a whole guild's online roster without re-implementing the "scan
-- Players for a matching GuildId attribute" pattern.
function GuildService.notifyGuild(guildId, message)
	broadcast(guildId, message)
end

-- Cross-references the global claims list (all cells, not just this
-- server's) against the static Settlements defs, so a guild's territory
-- shows up in the UI even if it was captured on a different cell's server
-- than whichever one the viewing player happens to be on right now.
local function guildTerritories(guildId)
	local claims = BackendService.listSettlementClaims()
	if not claims then
		return {}
	end
	local territories = {}
	for _, claim in ipairs(claims) do
		if claim.guildId and tostring(claim.guildId) == tostring(guildId) then
			local def = Settlements.defs[claim.settlementId]
			table.insert(territories, {
				id = claim.settlementId,
				name = def and def.name or claim.settlementId,
				cell = def and def.cell or "?",
			})
		end
	end
	table.sort(territories, function(a, b)
		return a.name < b.name
	end)
	return territories
end

-- Full roster (including offline members) for `player`'s current guild, or
-- nil if they're not in one. A live backend read, same pattern as
-- QuestLogUI's RequestQuestLog — small payload, no cache to go stale.
-- Also attaches `territories` (see guildTerritories above) for the UI's
-- territory summary line.
function GuildService.getGuildInfo(player)
	local guildId = player:GetAttribute("GuildId")
	if not guildId then
		return nil
	end
	local guild = BackendService.getGuildById(guildId)
	if guild then
		guild.territories = guildTerritories(guild.id)
	end
	return guild
end

function GuildService.isLeader(player)
	return player:GetAttribute("GuildLeader") == true
end

function GuildService.isOfficer(player)
	return player:GetAttribute("GuildOfficer") == true
end

-- Called once per join (from PlayerService's load flow, or start()'s sweep
-- of already-connected players) to pull persisted membership and set
-- attributes. Silently no-ops if the player isn't in a guild.
function GuildService.loadForPlayer(player)
	local guild, failed = BackendService.getGuildForPlayer(player.UserId)
	if failed then
		-- Backend unreachable: leave attributes unset rather than guess.
		-- The player just won't see guild UI this session; next load retries.
		return
	end
	if guild then
		setGuildAttributes(player, guild)
	end
end

function GuildService.create(player, rawName, rawTag)
	if player:GetAttribute("GuildId") then
		notify(player, "You're already in a guild.")
		return false
	end

	local name = trimmed(rawName)
	local tag = trimmed(rawTag)
	if not name or #name < GUILD_CONFIG.nameMinLen or #name > GUILD_CONFIG.nameMaxLen then
		notify(player, string.format("Guild name must be %d-%d characters.", GUILD_CONFIG.nameMinLen, GUILD_CONFIG.nameMaxLen))
		return false
	end
	if not tag or #tag < GUILD_CONFIG.tagMinLen or #tag > GUILD_CONFIG.tagMaxLen then
		notify(player, string.format("Guild tag must be %d-%d characters.", GUILD_CONFIG.tagMinLen, GUILD_CONFIG.tagMaxLen))
		return false
	end

	local guild, err = BackendService.createGuild(player.UserId, name, tag)
	if not guild then
		if err == "name_taken" then
			notify(player, "That guild name is already taken.")
		elseif err == "already_in_guild" then
			notify(player, "You're already in a guild.")
		elseif err == "invalid_name" or err == "invalid_tag" then
			notify(player, "That guild name or tag isn't valid.")
		else
			notify(player, "Couldn't create the guild right now — try again shortly.")
		end
		return false
	end

	setGuildAttributes(player, guild)
	notify(player, string.format("Guild [%s] %s founded.", guild.tag, guild.name))
	return true
end

-- Invite is leader-only for the MVP (mirrors the "closed party" case, not
-- the open one) — a guild's roster is a bigger commitment than a party's.
function GuildService.invite(inviter, target)
	local guildId = inviter:GetAttribute("GuildId")
	if not guildId then
		notify(inviter, "You're not in a guild.")
		return
	end
	if not GuildService.isLeader(inviter) then
		notify(inviter, "Only the guild leader can invite.")
		return
	end
	if target == inviter then
		return
	end
	if target:GetAttribute("GuildId") then
		notify(inviter, target.Name .. " is already in a guild.")
		return
	end

	pendingInvites[target.UserId] = {
		fromUserId = inviter.UserId,
		fromName = inviter.Name,
		guildId = guildId,
		guildName = inviter:GetAttribute("GuildName"),
		guildTag = inviter:GetAttribute("GuildTag"),
		expires = os.clock() + INVITE_TIMEOUT,
	}

	guildInviteReceivedRemote:FireClient(target, {
		fromUserId = inviter.UserId,
		fromName = inviter.Name,
		guildName = inviter:GetAttribute("GuildName"),
		guildTag = inviter:GetAttribute("GuildTag"),
		timeout = INVITE_TIMEOUT,
	})
	notify(inviter, "Invite sent to " .. target.Name .. ".")

	task.delay(INVITE_TIMEOUT, function()
		local pending = pendingInvites[target.UserId]
		if pending and pending.fromUserId == inviter.UserId and pending.guildId == guildId then
			pendingInvites[target.UserId] = nil
		end
	end)
end

function GuildService.respond(target, fromUserId, accept)
	local pending = pendingInvites[target.UserId]
	if not pending or pending.fromUserId ~= fromUserId or pending.expires < os.clock() then
		pendingInvites[target.UserId] = nil
		notify(target, "That invite is no longer valid.")
		return
	end
	pendingInvites[target.UserId] = nil

	local inviter = Players:GetPlayerByUserId(fromUserId)

	if not accept then
		notify(inviter, target.Name .. " declined the invite.")
		return
	end

	if target:GetAttribute("GuildId") then
		notify(target, "You're already in a guild.")
		return
	end

	local guild, err = BackendService.joinGuild(pending.guildId, target.UserId)
	if not guild then
		if err == "already_in_guild" then
			notify(target, "You're already in a guild.")
		elseif err == "not_found" then
			notify(target, "That guild no longer exists.")
		else
			notify(target, "Couldn't join the guild right now — try again shortly.")
		end
		return
	end

	setGuildAttributes(target, guild)
	broadcast(guild.id, target.Name .. " joined the guild.", target.UserId)
	notify(target, string.format("You joined [%s] %s.", guild.tag, guild.name))
end

function GuildService.kick(actor, target)
	local guildId = actor:GetAttribute("GuildId")
	if not guildId or not (GuildService.isLeader(actor) or GuildService.isOfficer(actor)) then
		notify(actor, "Only the guild leader or an officer can remove members.")
		return
	end
	if target.UserId == actor.UserId then
		return
	end

	local guild, err = BackendService.kickFromGuild(guildId, actor.UserId, target.UserId)
	if not guild then
		if err == "target_not_member" then
			notify(actor, target.Name .. " isn't in your guild.")
		elseif err == "not_authorized" then
			notify(actor, "You can't remove " .. target.Name .. " (leader or fellow officer).")
		else
			notify(actor, "Couldn't remove " .. target.Name .. " right now — try again shortly.")
		end
		return
	end

	if target:GetAttribute("GuildId") == guildId then
		clearGuildAttributes(target)
		notify(target, "You were removed from the guild.")
	end
	broadcast(guildId, target.Name .. " was removed from the guild.", target.UserId)
end

-- Leader-only. `role` is "officer" (promote) or "member" (demote).
-- Re-applies attributes to `target` immediately if they're online so the
-- UI (Kick button, bank withdraw) updates without needing to reopen the
-- panel.
function GuildService.setRole(leader, target, role)
	local guildId = leader:GetAttribute("GuildId")
	if not guildId or not GuildService.isLeader(leader) then
		notify(leader, "Only the guild leader can change ranks.")
		return
	end
	if target.UserId == leader.UserId then
		return
	end

	local guild, err = BackendService.setGuildMemberRole(guildId, leader.UserId, target.UserId, role)
	if not guild then
		if err == "target_not_member" then
			notify(leader, target.Name .. " isn't in your guild.")
		else
			notify(leader, "Couldn't update " .. target.Name .. "'s rank right now — try again shortly.")
		end
		return
	end

	refreshOnlineAttributes(guild)
	local verb = role == "officer" and "promoted to officer" or "demoted to member"
	broadcast(guildId, target.Name .. " was " .. verb .. ".")
end

function GuildService.leave(player)
	local guildId = player:GetAttribute("GuildId")
	if not guildId then
		return
	end

	local disbanded, result = BackendService.leaveGuild(guildId, player.UserId)
	if disbanded == nil then
		notify(player, "Couldn't leave the guild right now — try again shortly.")
		return
	end

	local playerName = player.Name
	clearGuildAttributes(player)

	if disbanded then
		notify(player, "You left the guild. It has disbanded (no members left).")
		return
	end

	notify(player, "You left the guild.")
	refreshOnlineAttributes(result) -- picks up a leadership transfer, if any
	broadcast(guildId, playerName .. " left the guild.", player.UserId)
end

function GuildService.sendChat(player, rawText)
	local guildId = player:GetAttribute("GuildId")
	if not guildId then
		return
	end
	local text = trimmed(rawText)
	if not text then
		return
	end
	if #text > 200 then
		text = text:sub(1, 200)
	end

	for _, plr in ipairs(onlineMembers(guildId)) do
		guildChatReceivedRemote:FireClient(plr, {
			fromUserId = player.UserId,
			fromName = player.Name,
			text = text,
		})
	end
end

-- ---- guild bank -----------------------------------------------------------
--
-- Deposit/withdraw go through the backend directly (guildBank.js), which
-- moves the item in/out of the player's own inventory in the same
-- transaction as the bank stack — this service's job is just permission
-- checks, toasts, and telling PlayerService to push the player's now-stale
-- cached inventory to their client (deposit/withdraw bypass the normal
-- client-driven move/remove remotes, same situation AdminSyncService is in
-- after an admin-panel edit).

function GuildService.requestBank(player)
	local guildId = player:GetAttribute("GuildId")
	if not guildId then
		return nil
	end
	return BackendService.getGuildBank(guildId)
end

function GuildService.requestBankLog(player)
	local guildId = player:GetAttribute("GuildId")
	if not guildId then
		return nil
	end
	return BackendService.getGuildBankLog(guildId)
end

-- Any member can deposit.
function GuildService.depositToBank(player, itemId, quantity)
	local guildId = player:GetAttribute("GuildId")
	if not guildId then
		notify(player, "You're not in a guild.")
		return
	end
	local deposited, err = BackendService.depositToGuildBank(guildId, player.UserId, itemId, quantity)
	if not deposited then
		if err == "insufficient" then
			notify(player, "You don't have that many to deposit.")
		elseif err == "unknown_item" then
			notify(player, "That item can't be deposited.")
		else
			notify(player, "Couldn't deposit right now — try again shortly.")
		end
		return
	end
	PlayerService.refreshInventory(player)
	notify(player, string.format("Deposited %dx %s to the guild bank.", deposited, itemId))
end

-- Officer/leader only (enforced backend-side; also gated client-side by not
-- showing the button — see GuildUI).
function GuildService.withdrawFromBank(player, itemId, quantity)
	local guildId = player:GetAttribute("GuildId")
	if not guildId then
		notify(player, "You're not in a guild.")
		return
	end
	local withdrawn, err = BackendService.withdrawFromGuildBank(guildId, player.UserId, itemId, quantity)
	if not withdrawn then
		if err == "not_authorized" then
			notify(player, "Only the guild leader or an officer can withdraw.")
		elseif err == "insufficient" then
			notify(player, "The bank doesn't have that many.")
		elseif err == "no_room" then
			notify(player, "Your inventory is full.")
		else
			notify(player, "Couldn't withdraw right now — try again shortly.")
		end
		return
	end
	PlayerService.refreshInventory(player)
	if withdrawn < quantity then
		notify(player, string.format("Withdrew %dx %s (inventory was full for the rest).", withdrawn, itemId))
	else
		notify(player, string.format("Withdrew %dx %s from the guild bank.", withdrawn, itemId))
	end
end

function GuildService.start()
	notifyRemote = Remotes.get("Notify")
	guildInviteReceivedRemote = Remotes.get("GuildInviteReceived")
	guildChatReceivedRemote = Remotes.get("GuildChatReceived")

	local create = Remotes.get("GuildCreate")
	create.OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		GuildService.create(player, payload.name, payload.tag)
	end)

	local invite = Remotes.get("GuildInvite")
	invite.OnServerEvent:Connect(function(player, targetUserId)
		local target = Players:GetPlayerByUserId(tonumber(targetUserId))
		if target then
			GuildService.invite(player, target)
		end
	end)

	local respond = Remotes.get("GuildRespond")
	respond.OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		local fromUserId = tonumber(payload.fromUserId)
		if fromUserId then
			GuildService.respond(player, fromUserId, payload.accept == true)
		end
	end)

	local kick = Remotes.get("GuildKick")
	kick.OnServerEvent:Connect(function(player, targetUserId)
		local target = Players:GetPlayerByUserId(tonumber(targetUserId))
		if target then
			GuildService.kick(player, target)
		end
	end)

	local setRole = Remotes.get("GuildSetRole")
	setRole.OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		local target = Players:GetPlayerByUserId(tonumber(payload.targetUserId))
		if target and (payload.role == "officer" or payload.role == "member") then
			GuildService.setRole(player, target, payload.role)
		end
	end)

	local leave = Remotes.get("GuildLeave")
	leave.OnServerEvent:Connect(function(player)
		GuildService.leave(player)
	end)

	local chat = Remotes.get("GuildChat")
	chat.OnServerEvent:Connect(function(player, text)
		GuildService.sendChat(player, text)
	end)

	local requestGuild = Remotes.getFunction("RequestGuild")
	requestGuild.OnServerInvoke = function(player)
		return GuildService.getGuildInfo(player)
	end

	local requestBank = Remotes.getFunction("RequestGuildBank")
	requestBank.OnServerInvoke = function(player)
		return GuildService.requestBank(player)
	end

	local requestBankLog = Remotes.getFunction("RequestGuildBankLog")
	requestBankLog.OnServerInvoke = function(player)
		return GuildService.requestBankLog(player)
	end

	local bankDeposit = Remotes.get("GuildBankDeposit")
	bankDeposit.OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		local quantity = tonumber(payload.quantity)
		if typeof(payload.itemId) == "string" and quantity then
			GuildService.depositToBank(player, payload.itemId, quantity)
		end
	end)

	local bankWithdraw = Remotes.get("GuildBankWithdraw")
	bankWithdraw.OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		local quantity = tonumber(payload.quantity)
		if typeof(payload.itemId) == "string" and quantity then
			GuildService.withdrawFromBank(player, payload.itemId, quantity)
		end
	end)

	-- Sweep already-connected players (same rationale as PlayerService: the
	-- first player on a fresh server often joins before this Connect runs).
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(GuildService.loadForPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player)
		GuildService.loadForPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		pendingInvites[player.UserId] = nil
	end)
end

return GuildService
