-- Shared, non-secret constants. Visible to client and server.
-- (The API key is NOT here — it lives server-only in Secret.lua.)

-- Note: which grid cell a Place represents now lives in GridConfig (derived
-- from PlaceId), not here.

return {
	-- The main inventory grid: fixed width, `height` rows for the basic
	-- backpack (bigger packs add rows later). MUST match backend items.js GRID.
	inventoryGrid = { width = 10, height = 30 },

	-- Reach (studs) now lives per-item as a `reach` stat on each weapon/tool def
	-- (see Items.lua). Server combat/gather and client focus all read that single
	-- value. This is the fallback for any equippable that forgot to set one.
	defaultReach = 9,

	HP = {
		max = 100,
		regenAmount = 1, -- HP restored per tick
		regenInterval = 2, -- seconds between regen ticks
		regenDelay = 5, -- seconds out of combat before regen starts
		respawnDelay = 5, -- seconds after death before respawning
	},

	-- Mana: a live gameplay resource (not persisted) that powers ranged magic.
	-- Regenerates steadily; the staff spends it per cast (see Items manaCost).
	Mana = {
		max = 100,
		regenAmount = 3, -- mana restored per tick
		regenInterval = 1, -- seconds between regen ticks
	},

	-- How often the server persists HP/position to the backend.
	autosaveInterval = 60,
}
