-- Shared buff/debuff definitions. The server's EffectService applies these
-- (gameplay side) and replicates each active effect to its owner as a Player
-- attribute `Effect_<id>` holding the expiry time on the server clock
-- (Workspace:GetServerTimeNow()), so the client can render icons + countdowns
-- with no remotes. Effects are live-only (not persisted), like mana.

local Effects = {}

Effects.attributePrefix = "Effect_"

Effects.defs = {
	slow = {
		id = "slow",
		name = "Slowed",
		kind = "debuff",
		duration = 4, -- seconds; reapplying refreshes the timer
		walkSpeedMult = 0.5,
		color = Color3.fromRGB(80, 200, 120), -- slime green: reads as its source
	},
}

function Effects.get(effectId)
	return Effects.defs[effectId]
end

-- The attribute name an active effect replicates under.
function Effects.attributeFor(effectId)
	return Effects.attributePrefix .. effectId
end

-- Reverse of attributeFor: effect id from an attribute name, or nil.
function Effects.idFromAttribute(attributeName)
	if attributeName:sub(1, #Effects.attributePrefix) == Effects.attributePrefix then
		return attributeName:sub(#Effects.attributePrefix + 1)
	end
	return nil
end

return Effects
