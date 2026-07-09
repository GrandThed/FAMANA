-- Vendor NPCs: low-poly merchants with a ProximityPrompt that opens the
-- store UI on the client (OpenStore remote). Deals come back through the
-- StoreDeal RemoteFunction (docs/VENDOR_UI.md §5.4) and are validated here —
-- the player is near the vendor, every line is tradable with the right
-- side, sell positions hold what the client claims — then PRICED (trade
-- list prices, shared ItemValue for trait gear, barter costs expanded into
-- removes) and settled through PlayerService.executeDeal: the backend lands
-- gold + removes + adds in ONE transaction, so the whole deal succeeds or
-- nothing changes.
--
-- Store contents/prices are data (shared/Stores, overlaid from GET /content);
-- vendor placement is world layout: authored maps use Vendor_<storeId>
-- markers (see shared/MapMarkers), VENDOR_DEFS positions are the fallback
-- for places without a map (the defs also carry the vendor's name).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtKit = require(Shared:WaitForChild("ArtKit"))
local Items = require(Shared:WaitForChild("Items"))
local ItemValue = require(Shared:WaitForChild("ItemValue"))
local MapMarkers = require(Shared:WaitForChild("MapMarkers"))
local Stores = require(Shared:WaitForChild("Stores"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local PlayerService = require(script.Parent.PlayerService)

local VendorService = {}

-- Prompt range is 10; the trade check is looser so a step back mid-purchase
-- doesn't reject a click the player already lined up.
local MAX_TRADE_DISTANCE = 16
local MAX_TRADE_QUANTITY = 99
local MAX_DEAL_LINES = 20
local MAX_DEAL_OPS = 64 -- backend /deal cap on removes + adds

-- { storeId, name, position, facing? (degrees yaw; vendor looks along -Z) }
local VENDOR_DEFS = {
	{ storeId = "general_goods", name = "Marla the Trader", position = Vector3.new(-16, 0, -34), facing = 205 },
}

local vendorFolder
local vendorsByStore = {} -- [storeId] = { Vector3 positions, for the distance check }
local notifyRemote

local function groundY(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { vendorFolder }
	local result = Workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -1000, 0), params)
	return result and result.Position.Y or 0
end

local function buildVendor(def)
	local store = Stores.get(def.storeId)
	if not store then
		warn("[VendorService] no store def for " .. tostring(def.storeId))
		return
	end

	local y = groundY(def.position.X, def.position.Z)
	local origin = CFrame.new(def.position.X, y, def.position.Z)
		* CFrame.Angles(0, math.rad(def.facing or 0), 0)

	local model = ArtKit.build("Vendor_" .. def.storeId, origin, {
		-- torso first: the PrimaryPart anchors the prompt
		{ name = "Tunic", size = Vector3.new(1.8, 1.8, 1.0), offset = Vector3.new(0, 2.3, 0), color = "leather", primary = true },
		{ name = "Belt", size = Vector3.new(1.9, 0.3, 1.1), offset = Vector3.new(0, 1.7, 0), color = "gold" },
		{ name = "LegL", size = Vector3.new(0.6, 1.4, 0.6), offset = Vector3.new(-0.4, 0.7, 0), color = "leatherDark" },
		{ name = "LegR", size = Vector3.new(0.6, 1.4, 0.6), offset = Vector3.new(0.4, 0.7, 0), color = "leatherDark" },
		{ name = "ArmL", size = Vector3.new(0.5, 1.5, 0.5), offset = Vector3.new(-1.2, 2.4, 0), rot = Vector3.new(0, 0, 8), color = "leather" },
		{ name = "ArmR", size = Vector3.new(0.5, 1.5, 0.5), offset = Vector3.new(1.2, 2.4, 0), rot = Vector3.new(0, 0, -8), color = "leather" },
		{ name = "Head", size = Vector3.new(1.1, 1.1, 1.1), offset = Vector3.new(0, 3.85, 0), color = "skin" },
		{ name = "EyeL", size = Vector3.new(0.14, 0.22, 0.06), offset = Vector3.new(-0.24, 3.95, -0.56), color = "ink" },
		{ name = "EyeR", size = Vector3.new(0.14, 0.22, 0.06), offset = Vector3.new(0.24, 3.95, -0.56), color = "ink" },
		{ name = "HatBrim", size = Vector3.new(1.7, 0.15, 1.7), offset = Vector3.new(0, 4.45, 0), color = "leatherDark" },
		{ name = "HatTop", size = Vector3.new(1.0, 0.55, 1.0), offset = Vector3.new(0, 4.8, 0), color = "leatherDark" },
	})
	model.Parent = vendorFolder

	vendorsByStore[def.storeId] = vendorsByStore[def.storeId] or {}
	table.insert(vendorsByStore[def.storeId], model.PrimaryPart.Position)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Trade"
	prompt.ObjectText = def.name
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart

	local openStore = Remotes.get("OpenStore")
	prompt.Triggered:Connect(function(player)
		openStore:FireClient(player, {
			storeId = def.storeId,
			storeName = store.name,
			vendorName = def.name,
			-- The client watches its distance to this and closes the panel
			-- when the player walks away.
			position = model.PrimaryPart.Position,
		})
	end)
end

-- Whether the player stands near any vendor running this store.
local function nearVendor(player, storeId)
	local positions = vendorsByStore[storeId]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not positions or not root then
		return false
	end
	for _, position in ipairs(positions) do
		if (root.Position - position).Magnitude <= MAX_TRADE_DISTANCE then
			return true
		end
	end
	return false
end

-- Non-meta main-grid quantity of an item (what generic id-based removal can
-- actually consume — rolled instances sell positionally instead).
local function countOwned(inventory, itemId)
	local total = 0
	for _, entry in ipairs(inventory) do
		if entry.containerId == "main" and entry.itemId == itemId and not entry.meta then
			total += entry.quantity
		end
	end
	return total
end

local function entryAt(inventory, x, y)
	for _, entry in ipairs(inventory) do
		if entry.containerId == "main" and entry.x == x and entry.y == y then
			return entry
		end
	end
	return nil
end

-- Validates and prices a whole deal, then settles it atomically. Lines:
--   { side = "buy",  itemId, quantity }          — gold or barter cost
--   { side = "sell", itemId, quantity }          — plain stacks, id-based
--   { side = "sell", itemId, x, y }              — whole row at a position
--                                                  (rolled instances)
local function handleDeal(player, payload)
	if
		typeof(payload) ~= "table"
		or typeof(payload.storeId) ~= "string"
		or typeof(payload.lines) ~= "table"
	then
		return { ok = false, error = "bad_request" }
	end
	local storeId = payload.storeId
	local lines = payload.lines
	if #lines == 0 or #lines > MAX_DEAL_LINES then
		return { ok = false, error = "too_many_lines" }
	end
	local store = Stores.get(storeId)
	if not store then
		return { ok = false, error = "bad_request" }
	end
	if not nearVendor(player, storeId) then
		return { ok = false, error = "too_far" }
	end
	local profile = PlayerService.get(player)
	if not profile then
		return { ok = false, error = "offline" }
	end
	local inventory = profile.inventory or {}

	local goldDelta = 0
	local adds = {}
	local removes = {} -- positional rows first; merged id-based removes appended below
	local idRemoves = {} -- [itemId] = qty: plain sells + barter costs share one remove
	local seenPositions = {}

	for _, line in ipairs(lines) do
		if typeof(line) ~= "table" or typeof(line.itemId) ~= "string" then
			return { ok = false, error = "bad_line" }
		end
		local itemId = line.itemId
		local def = Items.get(itemId)
		if not def then
			return { ok = false, error = "bad_line" }
		end

		if line.side == "buy" then
			local quantity = math.clamp(math.floor(tonumber(line.quantity) or 1), 1, MAX_TRADE_QUANTITY)
			local trade = Stores.trade(storeId, itemId)
			if not trade then
				return { ok = false, error = "not_traded" }
			end
			if trade.buyPrice then
				goldDelta -= trade.buyPrice * quantity
			elseif trade.barter then
				for _, cost in ipairs(trade.barter) do
					idRemoves[cost.itemId] = (idRemoves[cost.itemId] or 0) + cost.qty * quantity
				end
			else
				return { ok = false, error = "not_traded" } -- sell-only trade
			end
			table.insert(adds, { itemId = itemId, quantity = quantity })
		elseif line.side == "sell" then
			local x, y = tonumber(line.x), tonumber(line.y)
			if x and y then
				-- Positional: sells the WHOLE row at (x, y). Rolled instances
				-- go this way, keeping the id-based remove's meta-skip rule
				-- intact; the backend re-checks the position holds this item.
				x, y = math.floor(x), math.floor(y)
				local positionKey = x .. ":" .. y
				if seenPositions[positionKey] then
					return { ok = false, error = "bad_line" }
				end
				seenPositions[positionKey] = true
				local entry = entryAt(inventory, x, y)
				if not entry or entry.itemId ~= itemId then
					return { ok = false, error = "bad_line" }
				end
				-- Price resolution mirrors StoreUI.sellPriceFor: meta → formula,
				-- listed plain → curated sellPrice, unlisted def-trait → formula.
				local price
				if store.buysGear and entry.meta then
					price = ItemValue.forEntry(entry, def)
				end
				if not price then
					local trade = Stores.trade(storeId, itemId)
					price = trade and trade.sellPrice
				end
				if not price and store.buysGear then
					price = ItemValue.forEntry(entry, def)
				end
				if not price then
					return { ok = false, error = "not_traded" }
				end
				goldDelta += price * entry.quantity
				table.insert(removes, { containerId = "main", x = x, y = y, itemId = itemId })
			else
				local quantity = math.clamp(math.floor(tonumber(line.quantity) or 1), 1, MAX_TRADE_QUANTITY)
				local trade = Stores.trade(storeId, itemId)
				local price = trade and trade.sellPrice
				if not price and store.buysGear then
					-- Def-fixed trait gear (identical copies, no meta) can
					-- sell by id at the same formula price.
					price = ItemValue.forEntry(nil, def)
				end
				if not price then
					return { ok = false, error = "not_traded" }
				end
				goldDelta += price * quantity
				idRemoves[itemId] = (idRemoves[itemId] or 0) + quantity
			end
		else
			return { ok = false, error = "bad_line" }
		end
	end

	-- Pre-flight what the backend re-checks atomically anyway, so honest
	-- clients get precise errors without burning the HTTP round trip.
	for itemId, quantity in pairs(idRemoves) do
		if countOwned(inventory, itemId) < quantity then
			return { ok = false, error = "no_items" }
		end
	end
	if profile.gold + goldDelta < 0 then
		return { ok = false, error = "no_gold" }
	end

	for itemId, quantity in pairs(idRemoves) do
		table.insert(removes, { itemId = itemId, quantity = quantity })
	end
	if #removes + #adds > MAX_DEAL_OPS then
		return { ok = false, error = "too_many_lines" }
	end

	local ok, errorCode = PlayerService.executeDeal(player, {
		goldDelta = goldDelta,
		removes = removes,
		adds = adds,
	})
	if not ok then
		return { ok = false, error = errorCode or "bad_request" }
	end

	if goldDelta > 0 then
		notifyRemote:FireClient(player, ("Deal settled — got %dg"):format(goldDelta))
	elseif goldDelta < 0 then
		notifyRemote:FireClient(player, ("Deal settled — paid %dg"):format(-goldDelta))
	else
		notifyRemote:FireClient(player, "Deal settled")
	end
	return { ok = true }
end

function VendorService.start()
	notifyRemote = Remotes.get("Notify")

	vendorFolder = Instance.new("Folder")
	vendorFolder.Name = "Vendors"
	vendorFolder.Parent = Workspace

	if MapMarkers.mapPresent() then
		local defsByStore = {}
		for _, def in ipairs(VENDOR_DEFS) do
			defsByStore[def.storeId] = def
		end
		local markers = MapMarkers.takeFor("Vendor_", defsByStore)
		for storeId, def in pairs(defsByStore) do
			for _, marker in ipairs(markers[storeId] or {}) do
				buildVendor({
					storeId = def.storeId,
					name = def.name,
					position = marker.cframe.Position,
					facing = MapMarkers.facing(marker),
				})
			end
		end
	else
		for _, def in ipairs(VENDOR_DEFS) do
			buildVendor(def)
		end
	end

	local storeDeal = Remotes.getFunction("StoreDeal")
	storeDeal.OnServerInvoke = handleDeal
end

return VendorService
