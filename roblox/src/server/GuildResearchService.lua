-- Guild Research Service (Warframe Dojo Tech Tree Style).
-- Manages collaborative resource contributions, project progress tracking,
-- recipe unlocks across guild members, and Guild Level progression.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local GuildResearchCatalog = require(Shared:WaitForChild("GuildResearchCatalog"))
local PlayerService = require(script.Parent.PlayerService)
local GuildPlotService = require(script.Parent.GuildPlotService)

local GuildResearchService = {}

-- [guildId] = { xp = 0, level = 1, completed = { [projectId] = true }, funding = { [projectId] = { [itemOrGold] = amount } } }
local guildState = {}

local function getGuildState(guildId)
	if not guildId then
		return nil
	end
	if not guildState[guildId] then
		guildState[guildId] = {
			xp = 0,
			level = 1,
			completed = {},
			funding = {},
		}
	end
	return guildState[guildId]
end

local function notify(player, text)
	Remotes.get("Notify"):FireClient(player, text)
end

local function notifyGuild(guildId, text)
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("GuildId") == guildId then
			notify(p, text)
		end
	end
end

function GuildResearchService.isProjectCompleted(guildId, projectId)
	local state = getGuildState(guildId)
	return state and state.completed[projectId] == true
end

function GuildResearchService.contribute(player, projectId, resourceKey, amount)
	local guildId = player:GetAttribute("GuildId")
	if not guildId then
		notify(player, "Debes pertenecer a un gremio para realizar aportes de investigación.")
		return { ok = false, error = "no_guild" }
	end

	local project = GuildResearchCatalog.getProject(projectId)
	if not project then
		notify(player, "Proyecto de investigación no encontrado.")
		return { ok = false, error = "not_found" }
	end

	local state = getGuildState(guildId)
	if state.completed[projectId] then
		notify(player, "Este proyecto ya ha sido completado por el gremio.")
		return { ok = false, error = "already_completed" }
	end

	local required = project.cost[resourceKey]
	if not required then
		notify(player, "Recurso no requerido para este proyecto.")
		return { ok = false, error = "invalid_resource" }
	end

	state.funding[projectId] = state.funding[projectId] or {}
	local currentFunded = state.funding[projectId][resourceKey] or 0
	local needed = math.max(0, required - currentFunded)
	if needed <= 0 then
		notify(player, "Ese recurso ya fue financiado al 100%.")
		return { ok = false, error = "resource_full" }
	end

	local actualAmount = math.clamp(math.floor(tonumber(amount) or 1), 1, needed)

	-- Deduct gold or item
	if resourceKey == "gold" then
		if not PlayerService.spendGold(player, actualAmount) then
			notify(player, "No tienes suficiente oro.")
			return { ok = false, error = "no_gold" }
		end
	else
		if not PlayerService.removeItem(player, resourceKey, actualAmount) then
			notify(player, "No tienes suficientes materiales.")
			return { ok = false, error = "no_materials" }
		end
	end

	state.funding[projectId][resourceKey] = currentFunded + actualAmount
	notify(player, string.format("Aportaste +%dx %s al proyecto %s.", actualAmount, resourceKey, project.name))

	-- Check if project reached 100% completion across ALL required resources
	local isFullyFunded = true
	for rKey, rReq in pairs(project.cost) do
		local funded = state.funding[projectId][rKey] or 0
		if funded < rReq then
			isFullyFunded = false
			break
		end
	end

	if isFullyFunded then
		state.completed[projectId] = true
		state.xp += (project.guildXp or 100)
		state.level = 1 + math.floor(state.xp / 300)

		notifyGuild(
			guildId,
			string.format("🎉 ¡INVESTIGACIÓN COMPLETADA: %s! El Gremio alcanzó Nivel %d.", project.name, state.level)
		)
	end

	return { ok = true }
end

function GuildResearchService.start()
	local getResearchRemote = Remotes.getFunction("GetGuildResearch")
	local contributeRemote = Remotes.getFunction("ContributeGuildResearch")

	getResearchRemote.OnServerInvoke = function(player)
		local guildId = player:GetAttribute("GuildId")
		if not guildId then
			return { ok = false, error = "no_guild" }
		end

		local state = getGuildState(guildId)
		local catalogData = {}

		for labId, lab in pairs(GuildResearchCatalog.labs) do
			local labProjects = {}
			for projId, proj in pairs(lab.projects) do
				local projFunded = state.funding[projId] or {}
				table.insert(labProjects, {
					id = proj.id,
					name = proj.name,
					description = proj.description,
					cost = proj.cost,
					funded = projFunded,
					completed = state.completed[proj.id] == true,
					guildXp = proj.guildXp,
				})
			end
			table.insert(catalogData, {
				id = lab.id,
				name = lab.name,
				icon = lab.icon,
				description = lab.description,
				projects = labProjects,
			})
		end

		return {
			ok = true,
			guildLevel = state.level,
			guildXp = state.xp,
			labs = catalogData,
		}
	end

	contributeRemote.OnServerInvoke = function(player, payload)
		if typeof(payload) ~= "table" then
			return { ok = false }
		end
		return GuildResearchService.contribute(player, payload.projectId, payload.resourceKey, payload.amount)
	end
end

return GuildResearchService
