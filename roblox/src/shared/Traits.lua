-- Trait (synergy) definitions — Phase A of the TFT-style equipment system
-- (see docs/TRAITS_AND_SPELLS.md + docs/TRAITS.md). Equipment carries fixed
-- `traits` (points per trait) and an `itemLevel` on its def; the points of
-- every NON-INERT equipped piece sum per trait, and the highest threshold
-- the total reaches grants that tier's stats. An item is inert while its
-- itemLevel is above the player's ACTIVE class level (red square in the UI,
-- contributes nothing) — nothing is ever auto-unequipped.
--
-- Numbers are the Rasgos board's (demonstrative, made to be tuned). Deferred
-- traits (Guardián/ally shields, Rodar/Dash, mana regen, gathering) join the
-- catalog when their systems exist.

local Items = require(script.Parent.Items)

local Traits = {}

-- thresholds: { {points, stats} } — the highest reached entry applies.
-- Stat keys (aggregated additively across traits by statsFor):
--   crit        — added critical strike chance (fraction)
--   attackSpeed — swing rate bonus (fraction; cooldown = base / (1 + it))
--   duration    — buff/ability duration bonus (fraction)
--   hp          — max HP bonus (fraction)
--   regen       — HP regen per second, as a fraction of max HP (always on)
--   armor       — flat armor; damage taken × 100/(100+armor)
--   dodge       — chance to fully evade an enemy hit (fraction)
Traits.defs = {
	lynx_eye = {
		id = "lynx_eye",
		name = "Lynx Eye",
		icon = "👁️",
		color = Color3.fromRGB(240, 190, 70),
		description = "Sharpened senses raise your critical strike chance.",
		thresholds = {
			{ 1, { crit = 0.10 } },
			{ 4, { crit = 0.20 } },
			{ 7, { crit = 0.30 } },
			{ 10, { crit = 0.35 } },
			{ 13, { crit = 0.40 } },
			{ 16, { crit = 0.50 } },
			{ 20, { crit = 0.65 } },
			{ 22, { crit = 0.90 } },
		},
	},
	agile_hands = {
		id = "agile_hands",
		name = "Agile Hands",
		icon = "⚡",
		color = Color3.fromRGB(120, 210, 240),
		description = "Faster swings with every weapon and tool.",
		thresholds = {
			{ 1, { attackSpeed = 0.10 } },
			{ 4, { attackSpeed = 0.20 } },
			{ 7, { attackSpeed = 0.30 } },
			{ 10, { attackSpeed = 0.35 } },
			{ 13, { attackSpeed = 0.40 } },
			{ 16, { attackSpeed = 0.50 } },
			{ 20, { attackSpeed = 0.65 } },
			{ 22, { attackSpeed = 0.90 } },
		},
	},
	perseverance = {
		id = "perseverance",
		name = "Perseverance",
		icon = "⏳",
		color = Color3.fromRGB(200, 160, 220),
		description = "Your buffs and abilities last longer.",
		thresholds = {
			{ 3, { duration = 0.05 } },
			{ 7, { duration = 0.10 } },
			{ 11, { duration = 0.15 } },
		},
	},
	brawler = {
		id = "brawler",
		name = "Brawler",
		icon = "💪",
		color = Color3.fromRGB(220, 110, 90),
		description = "More max HP, and your health trickles back even in combat.",
		thresholds = {
			{ 2, { hp = 0.20, regen = 0.02 } },
			{ 5, { hp = 0.35, regen = 0.02 } },
			{ 8, { hp = 0.50, regen = 0.04 } },
			{ 11, { hp = 0.65, regen = 0.04 } },
			{ 16, { hp = 0.80, regen = 0.06 } },
			{ 22, { hp = 1.00, regen = 0.06 } },
		},
	},
	bastion = {
		id = "bastion",
		name = "Bastion",
		icon = "🧱",
		color = Color3.fromRGB(150, 160, 190),
		description = "Armor that shrugs off physical and magical punishment alike.",
		thresholds = {
			{ 2, { armor = 10 } },
			{ 5, { armor = 25 } },
			{ 8, { armor = 40 } },
			{ 11, { armor = 80 } },
			{ 16, { armor = 110 } },
		},
	},
	evasion = {
		id = "evasion",
		name = "Evasion",
		icon = "🍃",
		color = Color3.fromRGB(130, 210, 140),
		description = "A chance to fully evade enemy hits.",
		thresholds = {
			{ 5, { dodge = 0.05 } },
			{ 7, { dodge = 0.07 } },
			{ 9, { dodge = 0.09 } },
			{ 11, { dodge = 0.11 } },
			{ 13, { dodge = 0.13 } },
			{ 15, { dodge = 0.15 } },
			{ 17, { dodge = 0.17 } },
		},
	},
}

-- Display order (offense → defense).
Traits.order = { "lynx_eye", "agile_hands", "perseverance", "brawler", "bastion", "evasion" }

function Traits.get(traitId)
	return Traits.defs[traitId]
end

-- ---- thresholds ----------------------------------------------------------------

-- Stats of the highest threshold `points` reaches, or nil below the first.
function Traits.activeStats(traitId, points)
	local def = Traits.defs[traitId]
	if not def then
		return nil
	end
	local stats
	for _, threshold in ipairs(def.thresholds) do
		if points >= threshold[1] then
			stats = threshold[2]
		end
	end
	return stats
end

-- The next threshold above `points`, or nil once maxed.
function Traits.nextThreshold(traitId, points)
	local def = Traits.defs[traitId]
	if not def then
		return nil
	end
	for _, threshold in ipairs(def.thresholds) do
		if threshold[1] > points then
			return threshold[1]
		end
	end
	return nil
end

-- ---- aggregation ----------------------------------------------------------------

-- Whether an item def is inert (contributes nothing) at a player level.
function Traits.isInert(def, level)
	return def ~= nil and (def.itemLevel or 0) > level
end

-- Sums trait points across the equipped (paper doll) items of an inventory
-- listing, skipping inert pieces. Returns { [traitId] = points }.
function Traits.totalsFor(inventory, level)
	local totals = {}
	for _, entry in ipairs(inventory) do
		if entry.containerId == "equipment" then
			local def = Items.get(entry.itemId)
			local itemTraits = def and def.traits
			if itemTraits and not Traits.isInert(def, level) then
				for traitId, points in pairs(itemTraits) do
					if Traits.defs[traitId] and typeof(points) == "number" then
						totals[traitId] = (totals[traitId] or 0) + points
					end
				end
			end
		end
	end
	return totals
end

-- Collapses totals into one combined stat block (active tiers only, summed
-- additively across traits): { crit?, attackSpeed?, duration?, hp?, regen?,
-- armor?, dodge? }.
function Traits.statsFor(totals)
	local out = {}
	for traitId, points in pairs(totals) do
		local stats = Traits.activeStats(traitId, points)
		if stats then
			for key, value in pairs(stats) do
				out[key] = (out[key] or 0) + value
			end
		end
	end
	return out
end

-- ---- labels (tooltips) --------------------------------------------------------------

local STAT_ORDER = { "crit", "attackSpeed", "duration", "hp", "regen", "armor", "dodge" }

local STAT_LABELS = {
	crit = function(v)
		return ("+%d%% crit chance"):format(math.floor(v * 100 + 0.5))
	end,
	attackSpeed = function(v)
		return ("+%d%% attack speed"):format(math.floor(v * 100 + 0.5))
	end,
	duration = function(v)
		return ("+%d%% ability duration"):format(math.floor(v * 100 + 0.5))
	end,
	hp = function(v)
		return ("+%d%% max HP"):format(math.floor(v * 100 + 0.5))
	end,
	regen = function(v)
		return ("+%d%%/s HP regen"):format(math.floor(v * 100 + 0.5))
	end,
	armor = function(v)
		return ("+%d armor"):format(v)
	end,
	dodge = function(v)
		return ("+%d%% dodge"):format(math.floor(v * 100 + 0.5))
	end,
}

function Traits.statLabel(key, value)
	local format = STAT_LABELS[key]
	return format and format(value) or (key .. " " .. tostring(value))
end

-- One line for a tier's stat block: "+50% max HP, +4%/s HP regen".
function Traits.tierLabel(stats)
	local parts = {}
	for _, key in ipairs(STAT_ORDER) do
		if stats[key] then
			table.insert(parts, Traits.statLabel(key, stats[key]))
		end
	end
	return table.concat(parts, ", ")
end

return Traits
