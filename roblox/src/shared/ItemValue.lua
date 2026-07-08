-- Trait-value pricing for equipment (docs/VENDOR_UI.md §5.1). One shared
-- formula so the pack-tile price chip, the deal tile, the net row and the
-- server settlement all agree:
--
--   value = max(FLOOR, round( K × Σ over lines (points ^ EXP) ))
--
-- Each line is raised to EXP SEPARATELY (never the summed points), so
-- concentrated rolls beat spread ones: Brawler 6 (27.5) edges Brawler 5 +
-- Bastion 3 (27.3). That ordering flips below EXP ≈ 1.82 — never tune under
-- it. Rarity and item level need no explicit term: rarity's bonus points and
-- extra lines ARE the points (Traits.roll spends them).
--
-- The sum stays in floating point and rounds ONCE at the end — per-line
-- rounding erases the concentration edge (at K = 1 both examples above
-- round to 28).

local Traits = require(script.Parent.Traits)

local ItemValue = {}

ItemValue.EXP = 1.85
ItemValue.K = 3
ItemValue.FLOOR = 5

-- Value of a raw lines map ({ [traitOrSchoolId] = points }), or nil if it
-- has no positive lines.
function ItemValue.forLines(lines)
	if typeof(lines) ~= "table" then
		return nil
	end
	local sum = 0
	local any = false
	for _, points in pairs(lines) do
		if typeof(points) == "number" and points >= 1 then
			sum += points ^ ItemValue.EXP
			any = true
		end
	end
	if not any then
		return nil
	end
	return math.max(ItemValue.FLOOR, math.floor(ItemValue.K * sum + 0.5))
end

-- Value of an inventory entry (rolled instance meta overrides the def's
-- fixed traits, same precedence as tooltips), or nil when the item carries
-- no trait lines — plain items price through the store's trade list instead.
function ItemValue.forEntry(entry, def)
	local _, lines = Traits.entryInfo(entry, def)
	return ItemValue.forLines(lines)
end

return ItemValue
