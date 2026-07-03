-- Client-side quick-bind registry for the hotbar.
-- Slots 0/1 are reserved for the equipped weapon/offhand (keys 1/2); slots
-- 2..9 (keys 3..0) are player-assigned binds: InventoryUI writes them (hover
-- an item + press the key), HudUI renders them. Binds reference item ids and
-- are session-only (not persisted); HudUI clears a bind when its item leaves
-- the inventory.

local HotbarBinds = {}

local binds = {} -- [hotbarSlotIndex 2..9] = itemId
local changed = Instance.new("BindableEvent")

HotbarBinds.changed = changed.Event

function HotbarBinds.set(slotIndex, itemId)
	-- One bind per item: rebinding an item moves it to the new key.
	for slot, id in pairs(binds) do
		if id == itemId and slot ~= slotIndex then
			binds[slot] = nil
		end
	end
	binds[slotIndex] = itemId
	changed:Fire()
end

function HotbarBinds.get(slotIndex)
	return binds[slotIndex]
end

-- Clears a slot (e.g. when its item is no longer in the inventory).
function HotbarBinds.clear(slotIndex)
	if binds[slotIndex] ~= nil then
		binds[slotIndex] = nil
		changed:Fire()
	end
end

return HotbarBinds
